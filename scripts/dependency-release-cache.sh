#!/usr/bin/env bash
# Actions cache validation and durable, versioned release fallback.
set -euo pipefail

MODE="${1:?restore or save}"
: "${CACHE_KEY:?}" "${CACHE_DIR:?}" "${DEP_NAME:?}" "${DEP_PLATFORM:?}" "${DEP_LIBS:?}"
REPOSITORY="${GITHUB_REPOSITORY:-phm-dev/php-packages}"
TAG="native-dependency-cache-v1"
ASSET="${CACHE_KEY}.tar.gz"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

output() {
    echo "$1"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "$1" >> "$GITHUB_OUTPUT"; fi
}

validate() {
    local directory="$1" library
    for library in $DEP_LIBS; do
        [[ -s "${directory}/lib/${library}" ]] || return 1
        ar -t "${directory}/lib/${library}" >/dev/null 2>&1 || return 1
    done
    [[ -d "${directory}/include" ]] || return 1
}

assets() {
    gh release view "$TAG" --repo "$REPOSITORY" --json assets --jq '.assets[].name'
}

if [[ "$MODE" == restore ]]; then
    if [[ "${FORCE_REBUILD:-false}" == true ]]; then
        rm -rf "$CACHE_DIR"
        output 'hit=false'
        exit 0
    fi
    # The workflow supplies only an exact key or the explicitly approved migration key.
    if [[ -n "${MATCHED_KEY:-}" ]] && validate "$CACHE_DIR"; then
        output 'hit=true'
        output 'source=actions'
        exit 0
    fi
    rm -rf "$CACHE_DIR"
    if ! gh release download "$TAG" --repo "$REPOSITORY" \
        --pattern "$ASSET" --pattern "${ASSET}.sha256" --dir "$WORK"; then
        echo 'No usable release cache; building from source.'
        output 'hit=false'
        exit 0
    fi
    # Ignore any filename supplied by the checksum file.
    EXPECTED="$(awk 'NR == 1 { print $1 }' "$WORK/${ASSET}.sha256")"
    ACTUAL="$(shasum -a 256 "$WORK/$ASSET" | awk '{print $1}')"
    if [[ "$EXPECTED" != "$ACTUAL" ]]; then
        echo 'Release cache checksum mismatch; building from source.'
        output 'hit=false'
        exit 0
    fi
    # Reject absolute paths, traversal and links before extraction.
    if ! python3 - "$WORK/$ASSET" <<'PY'
import sys, tarfile
from pathlib import PurePosixPath
with tarfile.open(sys.argv[1]) as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
            sys.exit(1)
PY
    then
        output 'hit=false'
        exit 0
    fi
    mkdir "$WORK/unpack"
    tar -xzf "$WORK/$ASSET" -C "$WORK/unpack"
    if ! jq -e --arg key "$CACHE_KEY" --arg name "$DEP_NAME" --arg platform "$DEP_PLATFORM" \
        '.schema == 1 and .key == $key and .name == $name and .platform == $platform' \
        "$WORK/unpack/cache-manifest.json" >/dev/null || ! validate "$WORK/unpack"; then
        echo 'Release cache metadata/content mismatch; building from source.'
        output 'hit=false'
        exit 0
    fi
    mkdir -p "$(dirname "$CACHE_DIR")"
    mv "$WORK/unpack" "$CACHE_DIR"
    # Artifact transport may strip executable permissions; restore helper tools.
    if [[ -d "$CACHE_DIR/bin" ]]; then chmod +x "$CACHE_DIR/bin/"* 2>/dev/null || true; fi
    output 'hit=true'
    output 'source=release'
elif [[ "$MODE" == save ]]; then
    validate "$CACHE_DIR" || { echo 'Refusing to publish incomplete dependency cache' >&2; exit 1; }
    if ! assets > "$WORK/assets"; then
        # Concurrent jobs may create the same release; verify it exists after a race.
        gh release create "$TAG" --repo "$REPOSITORY" --target "${GITHUB_SHA:-main}" \
            --title 'Native dependency build cache' \
            --notes 'Versioned native build dependencies. Managed by GitHub Actions; not PHP installable packages.' \
            --prerelease || gh release view "$TAG" --repo "$REPOSITORY" >/dev/null
        assets > "$WORK/assets"
    fi
    if grep -Fxq "$ASSET" "$WORK/assets" && grep -Fxq "${ASSET}.sha256" "$WORK/assets" \
        && [[ "${FORCE_REBUILD:-false}" != true ]]; then
        echo 'Release cache already published.'
        exit 0
    fi
    # Only ship ordinary files/directories: omit libtool-generated symlinks.
    python3 - "$CACHE_DIR" "$WORK/$ASSET" "$CACHE_KEY" "$DEP_NAME" "$DEP_PLATFORM" <<'PY'
import io, json, sys, tarfile
from pathlib import Path
root, target, key, name, platform = sys.argv[1:]
manifest = json.dumps(dict(schema=1, key=key, name=name, platform=platform)).encode()
with tarfile.open(target, 'w:gz') as archive:
    for path in sorted(Path(root).rglob('*')):
        if not path.is_symlink() and (path.is_file() or path.is_dir()) and path.name != 'cache-manifest.json':
            archive.add(path, arcname=str(path.relative_to(root)), recursive=False)
    info = tarfile.TarInfo('cache-manifest.json')
    info.size = len(manifest)
    archive.addfile(info, io.BytesIO(manifest))
PY
    (cd "$WORK" && shasum -a 256 "$ASSET" > "${ASSET}.sha256")
    gh release upload "$TAG" "$WORK/$ASSET" "$WORK/${ASSET}.sha256" --repo "$REPOSITORY" --clobber
else
    echo "Unknown mode: $MODE" >&2
    exit 1
fi
