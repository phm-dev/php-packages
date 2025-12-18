#!/usr/bin/env bash
#
# Get latest stable extension version from Packagist API
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

# Fetch package info from Packagist API
RESPONSE=$(curl -fsSL "https://repo.packagist.org/p2/${PACKAGE}.json" 2>/dev/null || echo "")

if [[ -z "$RESPONSE" ]]; then
    echo "Error: Could not fetch package info for ${PACKAGE}" >&2
    exit 1
fi

# Extract versions - filter only stable releases (no dev, alpha, beta, RC)
if [[ "$SHOW_ALL" == true ]]; then
    echo "$RESPONSE" | jq -r --arg pkg "$PACKAGE" '
        .packages[$pkg][]
        | select(.version | test("^[0-9]"))
        | select(.version | test("dev|alpha|beta|RC|rc") | not)
        | .version
    ' | head -20
else
    # Get only the latest stable version
    VERSION=$(echo "$RESPONSE" | jq -r --arg pkg "$PACKAGE" '
        .packages[$pkg][]
        | select(.version | test("^[0-9]"))
        | select(.version | test("dev|alpha|beta|RC|rc") | not)
        | .version
    ' | head -1)

    if [[ -z "$VERSION" || "$VERSION" == "null" ]]; then
        echo "Error: No stable version found for ${PACKAGE}" >&2
        exit 1
    fi

    echo "$VERSION"
fi
