#!/usr/bin/env bash
#
# Get latest PHP versions for all secure branches
# Usage: ./get-php-versions.sh [--json]
#
# Fetches actively supported PHP branches from php.watch API,
# then resolves each to its latest patch version from php.net
#

set -euo pipefail

OUTPUT_JSON=false

if [[ "${1:-}" == "--json" ]]; then
    OUTPUT_JSON=true
fi

# Get secure PHP branches from php.watch API
get_secure_branches() {
    curl -fsSL "https://php.watch/api/v1/versions/secure" 2>/dev/null | \
        jq -r '.data | to_entries[] | select(.value.isSecureVersion == true) | .value.name' 2>/dev/null || \
        echo "8.3 8.4 8.5"  # Fallback
}

get_latest_version() {
    local branch="$1"
    local version=""

    # Try PHP releases API
    version=$(curl -fsSL "https://www.php.net/releases/index.php?json&version=${branch}" 2>/dev/null | \
        jq -r '.version // empty' 2>/dev/null || true)

    # Fallback: scrape from downloads page
    if [[ -z "$version" ]]; then
        version=$(curl -fsSL "https://www.php.net/downloads.php" 2>/dev/null | \
            grep -oE "php-${branch}\.[0-9]+\.tar" | \
            head -1 | \
            sed 's/php-//;s/\.tar//' || true)
    fi

    # Fallback: try GitHub releases
    if [[ -z "$version" ]]; then
        version=$(curl -fsSL "https://api.github.com/repos/php/php-src/tags" 2>/dev/null | \
            jq -r ".[].name | select(startswith(\"php-${branch}\"))" 2>/dev/null | \
            head -1 | \
            sed 's/php-//' || true)
    fi

    echo "$version"
}

VERSIONS=()

# Get branches from php.watch API
BRANCHES=$(get_secure_branches)

for branch in $BRANCHES; do
    ver=$(get_latest_version "$branch")
    if [[ -n "$ver" ]]; then
        VERSIONS+=("$ver")
    fi
done

if [[ "$OUTPUT_JSON" == true ]]; then
    printf '%s\n' "${VERSIONS[@]}" | jq -R . | jq -s .
else
    for ver in "${VERSIONS[@]}"; do
        echo "$ver"
    done
fi
