#!/usr/bin/env bash
#
# Check for PHP and extension updates
# Usage: ./check-updates.sh [--force]
#
# Output (for GitHub Actions):
#   php_versions - JSON array of PHP versions to build
#   ext_versions - JSON object of extension versions
#   has_builds - "true" or "false"
#
# Logic:
#   - If PHP version changed → build only that PHP version
#   - If any extension changed → build ALL PHP versions
#   - If --force → build all PHP versions
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VERSIONS_FILE="${PROJECT_ROOT}/versions.json"
CONFIG_FILE="${PROJECT_ROOT}/extensions/config.json"

# Colors for local output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_change() { echo -e "${YELLOW}[CHANGE]${NC} $*" >&2; }

FORCE_BUILD=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_BUILD=true
fi

# Check dependencies
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required" >&2
    exit 1
fi

# Load current versions from versions.json
load_current_versions() {
    if [[ ! -f "$VERSIONS_FILE" ]]; then
        log_warn "versions.json not found, will build everything"
        echo "{}"
        return
    fi
    cat "$VERSIONS_FILE"
}

# Fetch latest PHP versions from php.watch API
fetch_php_versions() {
    log_info "Fetching PHP versions from php.watch API..."
    local response
    response=$(curl -fsSL "https://php.watch/api/v1/versions/secure" 2>/dev/null || echo "{}")

    if [[ -z "$response" || "$response" == "{}" ]]; then
        log_warn "Failed to fetch PHP versions from API"
        return 1
    fi

    # Extract versions grouped by major.minor
    echo "$response" | jq -r '
        to_entries
        | map(select(.value.isSecure == true))
        | map({key: (.key | split(".") | .[0:2] | join(".")), value: .key})
        | group_by(.key)
        | map({key: .[0].key, value: (map(.value) | max)})
        | from_entries
    ' 2>/dev/null || echo "{}"
}

# Fetch latest extension version from Packagist (with PECL fallback)
fetch_extension_version() {
    local ext_name="$1"
    local packagist="$2"

    # Try Packagist first
    if [[ -n "$packagist" && "$packagist" != "null" ]]; then
        local response
        response=$(curl -fsSL "https://repo.packagist.org/p2/${packagist}.json" 2>/dev/null || echo "")

        if [[ -n "$response" ]]; then
            local version
            version=$(echo "$response" | jq -r --arg pkg "$packagist" '
                .packages[$pkg][]
                | select(.version | test("^v?[0-9]"))
                | select(.version | test("dev|alpha|beta|RC|rc") | not)
                | .version
                | ltrimstr("v")
            ' 2>/dev/null | head -1)

            if [[ -n "$version" && "$version" != "null" ]]; then
                echo "$version"
                return 0
            fi
        fi
    fi

    # Fallback to PECL
    local pecl_response
    pecl_response=$(curl -fsSL "https://pecl.php.net/rest/r/${ext_name}/allreleases.xml" 2>/dev/null || echo "")

    if [[ -n "$pecl_response" ]]; then
        local version
        version=$(echo "$pecl_response" | sed -n 's/.*<v>\([^<]*\)<\/v>.*/\1/p' | grep -v -i -E '(alpha|beta|rc|dev)' | head -1)

        if [[ -n "$version" ]]; then
            echo "$version"
            return 0
        fi
    fi

    return 1
}

# Fetch all extension versions
fetch_extension_versions() {
    log_info "Fetching extension versions..."

    local ext_versions="{}"

    # Read extensions from config
    local extensions
    extensions=$(jq -r '.extensions | keys[]' "$CONFIG_FILE" 2>/dev/null || echo "")

    for ext in $extensions; do
        # Skip opcache (built into PHP 8.5+)
        [[ "$ext" == "opcache" ]] && continue
        # Skip relay (special build)
        [[ "$ext" == "relay" ]] && continue

        local packagist
        packagist=$(jq -r ".extensions.${ext}.packagist // empty" "$CONFIG_FILE" 2>/dev/null)

        local version
        if version=$(fetch_extension_version "$ext" "$packagist"); then
            ext_versions=$(echo "$ext_versions" | jq --arg ext "$ext" --arg ver "$version" '. + {($ext): $ver}')
            log_info "  $ext: $version"
        else
            log_warn "  $ext: failed to fetch version"
        fi
    done

    echo "$ext_versions"
}

# Compare versions and determine what to build
compare_versions() {
    local current_versions="$1"
    local latest_php="$2"
    local latest_ext="$3"

    local php_changed=()
    local ext_changed=false

    # Compare PHP versions
    log_info "Comparing PHP versions..."
    for minor in $(echo "$latest_php" | jq -r 'keys[]'); do
        local latest_ver=$(echo "$latest_php" | jq -r --arg m "$minor" '.[$m]')
        local current_ver=$(echo "$current_versions" | jq -r --arg m "$minor" '.php[$m] // "none"')

        if [[ "$latest_ver" != "$current_ver" ]]; then
            log_change "PHP $minor: $current_ver -> $latest_ver"
            php_changed+=("$latest_ver")
        else
            log_info "  PHP $minor: $current_ver (unchanged)"
        fi
    done

    # Compare extension versions
    log_info "Comparing extension versions..."
    for ext in $(echo "$latest_ext" | jq -r 'keys[]'); do
        local latest_ver=$(echo "$latest_ext" | jq -r --arg e "$ext" '.[$e]')
        local current_ver=$(echo "$current_versions" | jq -r --arg e "$ext" '.extensions[$e] // "none"')

        if [[ "$latest_ver" != "$current_ver" ]]; then
            log_change "$ext: $current_ver -> $latest_ver"
            ext_changed=true
        fi
    done

    # Determine what to build
    local php_to_build=()

    if [[ "$FORCE_BUILD" == "true" ]]; then
        log_info "Force build requested - building all PHP versions"
        for minor in $(echo "$latest_php" | jq -r 'keys[]'); do
            php_to_build+=("$(echo "$latest_php" | jq -r --arg m "$minor" '.[$m]')")
        done
    elif [[ "$ext_changed" == "true" ]]; then
        log_info "Extension changed - building ALL PHP versions"
        for minor in $(echo "$latest_php" | jq -r 'keys[]'); do
            php_to_build+=("$(echo "$latest_php" | jq -r --arg m "$minor" '.[$m]')")
        done
    elif [[ ${#php_changed[@]} -gt 0 ]]; then
        log_info "PHP changed - building only changed versions"
        php_to_build=("${php_changed[@]}")
    fi

    # Output results
    local has_builds="false"
    if [[ ${#php_to_build[@]} -gt 0 ]]; then
        has_builds="true"
    fi

    # Create JSON array of PHP versions
    local php_json="[]"
    for ver in "${php_to_build[@]}"; do
        php_json=$(echo "$php_json" | jq --arg v "$ver" '. + [$v]')
    done

    echo "php_versions=${php_json}"
    echo "ext_versions=${latest_ext}"
    echo "has_builds=${has_builds}"
}

# Main
main() {
    log_info "=========================================="
    log_info "  Checking for updates"
    log_info "=========================================="

    # Load current versions
    local current_versions
    current_versions=$(load_current_versions)

    # Fetch latest versions
    local latest_php
    latest_php=$(fetch_php_versions)

    if [[ -z "$latest_php" || "$latest_php" == "{}" ]]; then
        log_warn "Could not fetch PHP versions, using current"
        latest_php=$(echo "$current_versions" | jq '.php // {}')
    fi

    local latest_ext
    latest_ext=$(fetch_extension_versions)

    # Compare and output results
    log_info "=========================================="
    compare_versions "$current_versions" "$latest_php" "$latest_ext"
}

main "$@"
