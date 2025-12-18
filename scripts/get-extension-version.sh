#!/usr/bin/env bash
#
# Get latest stable extension version from Packagist API (with PECL fallback)
# Usage: ./get-extension-version.sh <vendor/package> [--all]
#
# Examples:
#   ./get-extension-version.sh phpredis/phpredis
#   ./get-extension-version.sh xdebug/xdebug --all
#

set -euo pipefail

PACKAGE="${1:-}"
SHOW_ALL=false

if [[ -z "$PACKAGE" ]]; then
    echo "Usage: $0 <vendor/package> [--all]" >&2
    echo "Example: $0 phpredis/phpredis" >&2
    exit 1
fi

if [[ "${2:-}" == "--all" ]]; then
    SHOW_ALL=true
fi

# Extract extension name from package (e.g., igbinary/igbinary -> igbinary)
EXT_NAME="${PACKAGE##*/}"

# Try to get version from Packagist
get_from_packagist() {
    local response
    response=$(curl -fsSL "https://repo.packagist.org/p2/${PACKAGE}.json" 2>/dev/null || echo "")

    if [[ -z "$response" ]]; then
        return 1
    fi

    # Extract stable versions (no dev, alpha, beta, RC)
    # Handles both "1.2.3" and "v1.2.3" formats, strips "v" prefix
    local version
    version=$(echo "$response" | jq -r --arg pkg "$PACKAGE" '
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

    return 1
}

# Fallback to PECL
get_from_pecl() {
    local response
    response=$(curl -fsSL "https://pecl.php.net/rest/r/${EXT_NAME}/allreleases.xml" 2>/dev/null || echo "")

    if [[ -z "$response" ]]; then
        return 1
    fi

    # Extract stable versions from XML (skip alpha, beta, RC)
    local version
    version=$(echo "$response" | sed -n 's/.*<v>\([^<]*\)<\/v>.*/\1/p' | grep -v -i -E '(alpha|beta|rc|dev)' | head -1)

    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi

    return 1
}

# Main logic
VERSION=""

# Try Packagist first
if VERSION=$(get_from_packagist); then
    if [[ -n "$VERSION" ]]; then
        echo "$VERSION"
        exit 0
    fi
fi

# Fallback to PECL
if VERSION=$(get_from_pecl); then
    if [[ -n "$VERSION" ]]; then
        echo "$VERSION"
        exit 0
    fi
fi

echo "Error: No stable version found for ${PACKAGE} (tried Packagist and PECL)" >&2
exit 1
