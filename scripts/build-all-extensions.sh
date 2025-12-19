#!/usr/bin/env bash
#
# Build all extensions for a given PHP version
# Usage: ./build-all-extensions.sh <php_version> [--continue-on-error]
#
# Environment variables:
#   EXT_VERSIONS - JSON object with extension versions (optional)
#                  If not provided, fetches from Packagist/PECL
#
# Examples:
#   ./build-all-extensions.sh 8.5.0
#   EXT_VERSIONS='{"redis":"6.3.0","xdebug":"3.4.0"}' ./build-all-extensions.sh 8.5.0
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/extensions/config.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Parse arguments
PHP_VERSION="${1:-}"
CONTINUE_ON_ERROR=false

if [[ -z "$PHP_VERSION" ]]; then
    echo "Usage: $0 <php_version> [--continue-on-error]"
    echo "Example: $0 8.5.0"
    exit 1
fi

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --continue-on-error)
            CONTINUE_ON_ERROR=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

PHP_MAJOR_MINOR="${PHP_VERSION%.*}"

# Check dependencies
if ! command -v jq &>/dev/null; then
    log_error "jq is required"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    exit 1
fi

# Get extension version from EXT_VERSIONS env or fetch it
get_ext_version() {
    local ext="$1"
    local packagist="$2"

    # Try from EXT_VERSIONS env first
    if [[ -n "${EXT_VERSIONS:-}" ]]; then
        local ver
        ver=$(echo "$EXT_VERSIONS" | jq -r --arg e "$ext" '.[$e] // empty' 2>/dev/null)
        if [[ -n "$ver" ]]; then
            echo "$ver"
            return 0
        fi
    fi

    # Fetch from API
    "${SCRIPT_DIR}/get-extension-version.sh" "$packagist" 2>/dev/null
}

# Build single extension
build_extension() {
    local ext="$1"
    local ext_version="$2"
    local ext_config="$3"

    log_info "Building $ext $ext_version for PHP $PHP_VERSION..."

    # Get brew dependencies
    local brew_deps
    brew_deps=$(echo "$ext_config" | jq -r '.brew_deps[]? // empty' 2>/dev/null | tr '\n' ' ')

    # Build PIE options array
    local pie_opts=()
    while IFS= read -r opt; do
        [[ -n "$opt" ]] && pie_opts+=("$opt")
    done < <(echo "$ext_config" | jq -r '.pie_options[]? // empty' 2>/dev/null)

    # Run build-extension.sh
    local build_args=("$ext" "$ext_version" "$PHP_VERSION")
    if [[ ${#pie_opts[@]} -gt 0 ]]; then
        build_args+=("${pie_opts[@]}")
    fi

    if "${SCRIPT_DIR}/build-extension.sh" "${build_args[@]}"; then
        log_success "$ext $ext_version built successfully"
        return 0
    else
        log_error "$ext $ext_version build failed"
        return 1
    fi
}

# Main
main() {
    log_info "=========================================="
    log_info "  Building all extensions for PHP $PHP_VERSION"
    log_info "=========================================="

    local failed_extensions=()
    local success_count=0

    # Get list of extensions from config
    local extensions
    extensions=$(jq -r '.extensions | keys[]' "$CONFIG_FILE")

    for ext in $extensions; do
        # Skip opcache for PHP 8.5+ (built-in)
        if [[ "$ext" == "opcache" && "${PHP_MAJOR_MINOR}" == "8.5" ]]; then
            log_info "Skipping opcache (built-in for PHP 8.5+)"
            continue
        fi

        # Skip relay (special build, pre-built binaries)
        if [[ "$ext" == "relay" ]]; then
            log_warn "Skipping relay (requires special build)"
            continue
        fi

        # Get extension config
        local ext_config
        ext_config=$(jq ".extensions.${ext}" "$CONFIG_FILE")

        # Get packagist package name
        local packagist
        packagist=$(echo "$ext_config" | jq -r '.packagist // empty')

        if [[ -z "$packagist" || "$packagist" == "null" ]]; then
            log_warn "Skipping $ext (no packagist defined)"
            continue
        fi

        # Get extension version
        local ext_version
        if ! ext_version=$(get_ext_version "$ext" "$packagist"); then
            log_error "Could not determine version for $ext"
            if [[ "$CONTINUE_ON_ERROR" == "true" ]]; then
                failed_extensions+=("$ext")
                continue
            else
                exit 1
            fi
        fi

        # Build extension
        if build_extension "$ext" "$ext_version" "$ext_config"; then
            ((success_count++))
        else
            if [[ "$CONTINUE_ON_ERROR" == "true" ]]; then
                failed_extensions+=("$ext")
            else
                exit 1
            fi
        fi

        log_info ""
    done

    # Summary
    log_info "=========================================="
    log_info "  Build Summary"
    log_info "=========================================="
    log_success "Successfully built: $success_count extensions"

    if [[ ${#failed_extensions[@]} -gt 0 ]]; then
        log_error "Failed extensions: ${failed_extensions[*]}"
        if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
            exit 1
        fi
        log_warn "Continuing despite failures (--continue-on-error)"
    else
        log_success "All extensions built successfully!"
    fi
}

main "$@"
