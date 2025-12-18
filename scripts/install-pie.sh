#!/usr/bin/env bash
#
# Install PIE (PHP Installer for Extensions)
# Usage: ./install-pie.sh <php_path> [pie_version]
#
# Examples:
#   ./install-pie.sh /opt/php/8.5
#   ./install-pie.sh /opt/php/8.4 0.5.0
#

set -euo pipefail

PHP_PATH="${1:-}"
PIE_VERSION="${2:-}"

if [[ -z "$PHP_PATH" ]]; then
    echo "Usage: $0 <php_path> [pie_version]" >&2
    echo "Example: $0 /opt/php/8.5" >&2
    exit 1
fi

PHP_BIN="${PHP_PATH}/bin/php"

if [[ ! -x "$PHP_BIN" ]]; then
    echo "Error: PHP binary not found at ${PHP_BIN}" >&2
    exit 1
fi

# Get latest PIE version if not specified
if [[ -z "$PIE_VERSION" ]]; then
    echo "Fetching latest PIE version..."
    PIE_VERSION=$(curl -fsSL "https://api.github.com/repos/php/pie/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    if [[ -z "$PIE_VERSION" || "$PIE_VERSION" == "null" ]]; then
        echo "Error: Could not determine latest PIE version" >&2
        exit 1
    fi
fi

echo "Installing PIE version ${PIE_VERSION}..."

PIE_URL="https://github.com/php/pie/releases/download/${PIE_VERSION}/pie.phar"
PIE_DEST="${PHP_PATH}/bin/pie"

# Download PIE
if ! curl -fsSL "$PIE_URL" -o "$PIE_DEST"; then
    echo "Error: Failed to download PIE from ${PIE_URL}" >&2
    exit 1
fi

chmod +x "$PIE_DEST"

# Verify PIE works
if ! "$PHP_BIN" "$PIE_DEST" --version &>/dev/null; then
    echo "Warning: PIE may not work correctly with this PHP version" >&2
fi

echo "PIE installed successfully at ${PIE_DEST}"
"$PHP_BIN" "$PIE_DEST" --version
