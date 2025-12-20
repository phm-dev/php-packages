#!/usr/bin/env bash
#
# Generate index.json from GitHub Releases
# Usage: ./generate-index.sh [--base-url <url>]
#
# Parses all releases (PHP and extensions) and generates a unified index.json
# New naming convention:
#   - PHP core: php{VERSION}-{type}_{platform}.tar.zst
#   - Extensions: php{VERSION}-{ext}{extver}_{platform}.tar.zst
#
# Compatible with Bash 3.2+ (macOS default)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default base URL for GitHub Releases
BASE_URL="${BASE_URL:-https://github.com/phm-dev/php-packages/releases/download}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            BASE_URL="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

# Check for required tools
if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is required but not installed"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed"
    exit 1
fi

# Temporary directory for processing
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Initialize platform files
mkdir -p "$TEMP_DIR/platforms"

log_info "Fetching releases from GitHub..."

# Get all releases
RELEASES=$(gh release list --json tagName,name -L 1000 2>/dev/null || echo "[]")
RELEASE_COUNT=$(echo "$RELEASES" | jq 'length')

if [[ "$RELEASE_COUNT" -eq 0 ]]; then
    log_error "No releases found"
    exit 1
fi

log_info "Found ${RELEASE_COUNT} releases"

# Process each release
echo "$RELEASES" | jq -r '.[].tagName' | while read -r TAG; do
    if [[ -z "$TAG" ]]; then
        continue
    fi

    log_info "Processing release: ${TAG}"

    # Get release assets
    ASSETS=$(gh release view "$TAG" --json assets -q '.assets[].name' 2>/dev/null || echo "")

    if [[ -z "$ASSETS" ]]; then
        log_info "  No assets found, skipping"
        continue
    fi

    # Determine release type and version
    if [[ "$TAG" =~ ^php-([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
        RELEASE_TYPE="php"
        PHP_FULL_VERSION="${BASH_REMATCH[1]}"
        EXT_VERSION=""
    elif [[ "$TAG" =~ ^([a-z]+)-([0-9]+\.[0-9]+\.?[0-9]*)$ ]]; then
        RELEASE_TYPE="extension"
        EXT_NAME="${BASH_REMATCH[1]}"
        EXT_VERSION="${BASH_REMATCH[2]}"
        PHP_FULL_VERSION=""
    else
        log_info "  Unknown tag format: ${TAG}, skipping"
        continue
    fi

    # Process each asset
    echo "$ASSETS" | while read -r ASSET; do
        if [[ ! "$ASSET" =~ \.tar\.zst$ ]]; then
            continue
        fi

        # Parse asset filename
        # PHP core: php8.5.0-cli_darwin-arm64.tar.zst
        # Extension: php8.5.0-redis6.3.0_darwin-arm64.tar.zst

        if [[ "$ASSET" =~ ^php([0-9]+\.[0-9]+\.[0-9]+)-([a-z]+)_([a-z]+-[a-z0-9]+)\.tar\.zst$ ]]; then
            # PHP core package
            PKG_PHP_VERSION="${BASH_REMATCH[1]}"
            PKG_TYPE="${BASH_REMATCH[2]}"
            PLATFORM="${BASH_REMATCH[3]}"

            PHP_MINOR="${PKG_PHP_VERSION%.*}"
            PKG_NAME="php${PHP_MINOR}-${PKG_TYPE}"
            PKG_VERSION="$PKG_PHP_VERSION"

            case "$PKG_TYPE" in
                common)
                    DESCRIPTION="PHP ${PHP_MINOR} common files"
                    DEPENDS="[]"
                    ;;
                cli)
                    DESCRIPTION="PHP ${PHP_MINOR} CLI interpreter"
                    DEPENDS="[\"php${PHP_MINOR}-common (>= ${PKG_PHP_VERSION})\"]"
                    ;;
                fpm)
                    DESCRIPTION="PHP ${PHP_MINOR} FastCGI Process Manager"
                    DEPENDS="[\"php${PHP_MINOR}-common (>= ${PKG_PHP_VERSION})\"]"
                    ;;
                cgi)
                    DESCRIPTION="PHP ${PHP_MINOR} CGI binary"
                    DEPENDS="[\"php${PHP_MINOR}-common (>= ${PKG_PHP_VERSION})\"]"
                    ;;
                dev)
                    DESCRIPTION="PHP ${PHP_MINOR} development files"
                    DEPENDS="[\"php${PHP_MINOR}-common (>= ${PKG_PHP_VERSION})\"]"
                    ;;
                pear)
                    DESCRIPTION="PHP ${PHP_MINOR} PEAR/PECL tools"
                    DEPENDS="[\"php${PHP_MINOR}-cli (>= ${PKG_PHP_VERSION})\"]"
                    ;;
                *)
                    DESCRIPTION="PHP ${PHP_MINOR} ${PKG_TYPE}"
                    DEPENDS="[\"php${PHP_MINOR}-common (>= ${PKG_PHP_VERSION})\"]"
                    ;;
            esac

        elif [[ "$ASSET" =~ ^php([0-9]+\.[0-9]+\.[0-9]+)-([a-z]+)([0-9]+\.[0-9]+\.?[0-9]*)_([a-z]+-[a-z0-9]+)\.tar\.zst$ ]]; then
            # Extension package
            PKG_PHP_VERSION="${BASH_REMATCH[1]}"
            PKG_EXT_NAME="${BASH_REMATCH[2]}"
            PKG_EXT_VERSION="${BASH_REMATCH[3]}"
            PLATFORM="${BASH_REMATCH[4]}"

            PHP_MINOR="${PKG_PHP_VERSION%.*}"
            PKG_NAME="php${PHP_MINOR}-${PKG_EXT_NAME}"
            PKG_VERSION="$PKG_EXT_VERSION"
            DESCRIPTION="${PKG_EXT_NAME} extension for PHP ${PHP_MINOR}"
            DEPENDS="[\"php${PHP_MINOR}-common (>= ${PKG_PHP_VERSION})\"]"

        else
            log_info "    Unknown asset format: ${ASSET}, skipping"
            continue
        fi

        DOWNLOAD_URL="${BASE_URL}/${TAG}/${ASSET}"

        # Create package entry JSON (minimal - only essential fields)
        PACKAGE_ENTRY=$(jq -n \
            --arg name "$PKG_NAME" \
            --arg version "$PKG_VERSION" \
            --arg description "$DESCRIPTION" \
            --argjson depends "$DEPENDS" \
            --arg url "$DOWNLOAD_URL" \
            '{
                name: $name,
                version: $version,
                description: $description,
                depends: $depends,
                url: $url
            }')

        # Append to platform file
        echo "$PACKAGE_ENTRY" >> "${TEMP_DIR}/platforms/${PLATFORM}.json"

    done
done

# Deduplicate and keep latest version for each package per platform
log_info "Deduplicating packages (keeping latest versions)..."

for platform_file in "$TEMP_DIR/platforms"/*.json; do
    if [[ ! -f "$platform_file" ]]; then
        continue
    fi

    PLATFORM_NAME=$(basename "$platform_file" .json)

    # Sort by name then version (descending) and keep first occurrence of each name
    jq -s 'sort_by(.name, .version) | reverse | unique_by(.name)' "$platform_file" > "${platform_file}.dedup"
    mv "${platform_file}.dedup" "$platform_file"
done

# Build final index.json
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

log_info "Building index.json..."

# Start JSON
cat > "${PROJECT_ROOT}/index.json" << EOF
{
  "version": 1,
  "generated": "${GENERATED_AT}",
  "platforms": {
EOF

# Add platforms
FIRST_PLATFORM=true
for platform_file in "$TEMP_DIR/platforms"/*.json; do
    if [[ ! -f "$platform_file" ]]; then
        continue
    fi

    PLATFORM_NAME=$(basename "$platform_file" .json)

    if [[ "$FIRST_PLATFORM" == "true" ]]; then
        FIRST_PLATFORM=false
    else
        echo "," >> "${PROJECT_ROOT}/index.json"
    fi

    # Count packages for this platform (file is already a JSON array)
    PKG_COUNT=$(jq 'length' "$platform_file")

    echo -n "    \"${PLATFORM_NAME}\": {\"packages\": " >> "${PROJECT_ROOT}/index.json"

    # Add packages array (file is already a JSON array after deduplication)
    cat "$platform_file" >> "${PROJECT_ROOT}/index.json"

    echo -n "}" >> "${PROJECT_ROOT}/index.json"

    log_info "  ${PLATFORM_NAME}: ${PKG_COUNT} packages"
done

# Close JSON
cat >> "${PROJECT_ROOT}/index.json" << EOF

  }
}
EOF

# Pretty print the final JSON
jq '.' "${PROJECT_ROOT}/index.json" > "${PROJECT_ROOT}/index.json.tmp"
mv "${PROJECT_ROOT}/index.json.tmp" "${PROJECT_ROOT}/index.json"

TOTAL_PACKAGES=$(jq '[.platforms[].packages[]] | length' "${PROJECT_ROOT}/index.json")

log_info "=========================================="
log_info "Generated: ${PROJECT_ROOT}/index.json"
log_info "Total packages: ${TOTAL_PACKAGES}"
log_info "=========================================="
