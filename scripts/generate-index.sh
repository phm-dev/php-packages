#!/usr/bin/env bash
#
# Generate index.json from package files in dist/
# Usage: ./generate-index.sh [--base-url <url>]
#
# Compatible with Bash 3.2+ (macOS default)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="${PROJECT_ROOT}/dist"

# Default base URL for GitHub Releases
BASE_URL="${BASE_URL:-https://github.com/USER/php-packages/releases/download}"
RELEASE_TAG="${RELEASE_TAG:-latest}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            BASE_URL="$2"
            shift 2
            ;;
        --release-tag)
            RELEASE_TAG="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

if [[ ! -d "$DIST_DIR" ]]; then
    log_error "Dist directory not found: ${DIST_DIR}"
    exit 1
fi

# Find all package tarballs
PACKAGES=$(find "$DIST_DIR" -name '*.tar.zst' -type f | sort)

if [[ -z "$PACKAGES" ]]; then
    log_error "No packages found in ${DIST_DIR}"
    exit 1
fi

PKG_COUNT=$(echo "$PACKAGES" | wc -l | tr -d ' ')
log_info "Found ${PKG_COUNT} packages"

# Temporary files for collecting platform packages
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Process each package (use process substitution to avoid subshell)
while read -r pkg_path; do
    if [[ -z "$pkg_path" ]]; then
        continue
    fi

    pkg_file="$(basename "$pkg_path")"
    log_info "Processing: ${pkg_file}"

    # Extract pkginfo.json from tarball (zstd compressed)
    PKGINFO=$(zstd -dc "$pkg_path" 2>/dev/null | tar -xf - -O pkginfo.json 2>/dev/null || echo "{}")

    if [[ "$PKGINFO" == "{}" ]]; then
        log_error "  Failed to extract pkginfo.json, skipping"
        continue
    fi

    # Parse package info using jq
    NAME=$(echo "$PKGINFO" | jq -r '.name // empty')
    VERSION=$(echo "$PKGINFO" | jq -r '.version // empty')
    REVISION=$(echo "$PKGINFO" | jq -r '.revision // 1')
    PLATFORM=$(echo "$PKGINFO" | jq -r '.platform // empty')
    DESCRIPTION=$(echo "$PKGINFO" | jq -r '.description // empty')
    DEPENDS=$(echo "$PKGINFO" | jq -c '.depends // []')
    PROVIDES=$(echo "$PKGINFO" | jq -c '.provides // []')
    INSTALLED_SIZE=$(echo "$PKGINFO" | jq -r '.installed_size // 0')

    if [[ -z "$NAME" ]] || [[ -z "$PLATFORM" ]]; then
        log_error "  Invalid package metadata, skipping"
        continue
    fi

    # Get file size and SHA256
    if [[ "$OSTYPE" == "darwin"* ]]; then
        FILE_SIZE=$(stat -f%z "$pkg_path")
    else
        FILE_SIZE=$(stat --printf="%s" "$pkg_path")
    fi

    if [[ -f "${pkg_path}.sha256" ]]; then
        SHA256=$(cat "${pkg_path}.sha256")
    else
        SHA256=$(shasum -a 256 "$pkg_path" | cut -d' ' -f1)
    fi

    # Build download URL
    DOWNLOAD_URL="${BASE_URL}/${RELEASE_TAG}/${pkg_file}"

    # Create package entry JSON
    PACKAGE_ENTRY=$(cat << EOFPKG
{
  "name": "${NAME}",
  "version": "${VERSION}",
  "revision": ${REVISION},
  "description": "${DESCRIPTION}",
  "depends": ${DEPENDS},
  "provides": ${PROVIDES},
  "url": "${DOWNLOAD_URL}",
  "sha256": "${SHA256}",
  "size": ${FILE_SIZE},
  "installed_size": ${INSTALLED_SIZE}
}
EOFPKG
)

    # Append to platform file (single line JSON for easier parsing)
    echo "$PACKAGE_ENTRY" | jq -c '.' >> "${TEMP_DIR}/${PLATFORM}.json"
done <<< "$PACKAGES"

# Build final index.json
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Start JSON
cat > "${DIST_DIR}/index.json" << EOF
{
  "version": 1,
  "generated": "${GENERATED_AT}",
  "platforms": {
EOF

# Add platforms
FIRST_PLATFORM=true
for platform_file in "$TEMP_DIR"/*.json; do
    if [[ ! -f "$platform_file" ]]; then
        continue
    fi

    PLATFORM_NAME=$(basename "$platform_file" .json)

    if [[ "$FIRST_PLATFORM" == "true" ]]; then
        FIRST_PLATFORM=false
    else
        echo "," >> "${DIST_DIR}/index.json"
    fi

    # Count packages for this platform
    PKG_COUNT=$(wc -l < "$platform_file" | tr -d ' ')

    echo -n "    \"${PLATFORM_NAME}\": {\"packages\": [" >> "${DIST_DIR}/index.json"

    # Add packages (join with comma)
    FIRST_PKG=true
    while IFS= read -r pkg_json; do
        if [[ -z "$pkg_json" ]]; then
            continue
        fi

        if [[ "$FIRST_PKG" == "true" ]]; then
            FIRST_PKG=false
        else
            echo -n "," >> "${DIST_DIR}/index.json"
        fi

        # Already compact single-line JSON
        echo -n "$pkg_json" >> "${DIST_DIR}/index.json"
    done < "$platform_file"

    echo -n "]}" >> "${DIST_DIR}/index.json"

    log_info "  ${PLATFORM_NAME}: ${PKG_COUNT} packages"
done

# Close JSON
cat >> "${DIST_DIR}/index.json" << EOF

  }
}
EOF

# Pretty print the final JSON
if command -v jq &> /dev/null; then
    jq '.' "${DIST_DIR}/index.json" > "${DIST_DIR}/index.json.tmp"
    mv "${DIST_DIR}/index.json.tmp" "${DIST_DIR}/index.json"
fi

log_info "=========================================="
log_info "Generated: ${DIST_DIR}/index.json"
log_info "=========================================="
