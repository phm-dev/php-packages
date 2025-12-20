#!/usr/bin/env bash
#
# Build all extensions for a given PHP version
# Usage: ./build-all-extensions.sh <php_version> [--continue-on-error]
#
# Environment variables:
#   EXT_VERSIONS - JSON object with extension versions (optional)
#                  If not provided, fetches from Packagist/PECL
#
# Output:
#   - Built packages in dist/
#   - Build logs in dist/logs/
#   - Build report in dist/build-report.json
#
# Examples:
#   ./build-all-extensions.sh 8.5.0
#   EXT_VERSIONS='{"redis":"6.3.0","xdebug":"3.4.0"}' ./build-all-extensions.sh 8.5.0
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/extensions/config.json"
DIST_DIR="${PROJECT_ROOT}/dist"
LOGS_DIR="${DIST_DIR}/logs"
BUILD_REPORT="${DIST_DIR}/build-report.json"

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

# Initialize logs directory and build report
mkdir -p "$LOGS_DIR"
echo '{"php_version":"'"$PHP_VERSION"'","extensions":[],"summary":{}}' > "$BUILD_REPORT"

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

# Add extension result to build report
add_to_report() {
    local ext="$1"
    local version="$2"
    local status="$3"
    local error_msg="${4:-}"
    local log_file="${5:-}"

    local entry
    entry=$(jq -n \
        --arg ext "$ext" \
        --arg ver "$version" \
        --arg status "$status" \
        --arg error "$error_msg" \
        --arg log "$log_file" \
        '{name: $ext, version: $ver, status: $status, error: $error, log_file: $log}')

    # Update report atomically
    local tmp_report="${BUILD_REPORT}.tmp"
    jq --argjson entry "$entry" '.extensions += [$entry]' "$BUILD_REPORT" > "$tmp_report"
    mv "$tmp_report" "$BUILD_REPORT"
}

# Build single extension
build_extension() {
    local ext="$1"
    local ext_version="$2"
    local ext_config="$3"

    log_info "Building $ext $ext_version for PHP $PHP_VERSION..."

    # Create log file for this extension
    local log_file="${LOGS_DIR}/${ext}-${ext_version}.log"

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

    # Execute build and capture output
    local build_exit_code=0
    {
        echo "========================================"
        echo "Building: $ext $ext_version"
        echo "PHP Version: $PHP_VERSION"
        echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "Command: ${SCRIPT_DIR}/build-extension.sh ${build_args[*]}"
        echo "========================================"
        echo ""
    } > "$log_file"

    if "${SCRIPT_DIR}/build-extension.sh" "${build_args[@]}" >> "$log_file" 2>&1; then
        log_success "$ext $ext_version built successfully"
        add_to_report "$ext" "$ext_version" "success" "" "$(basename "$log_file")"
        return 0
    else
        build_exit_code=$?
        log_error "$ext $ext_version build failed (exit code: $build_exit_code)"

        # Extract last error from log
        local last_error
        last_error=$(tail -20 "$log_file" | grep -i -E '(error|failed|fatal)' | tail -1 || echo "Unknown error")

        add_to_report "$ext" "$ext_version" "failed" "$last_error" "$(basename "$log_file")"

        # Show last 30 lines of log for debugging
        echo ""
        log_error "=== Last 30 lines of build log for $ext ==="
        tail -30 "$log_file" | sed 's/^/    /'
        echo ""

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

    # Update build report summary
    local total_extensions=${#failed_extensions[@]}
    ((total_extensions += success_count))

    local tmp_report="${BUILD_REPORT}.tmp"
    jq \
        --argjson success "$success_count" \
        --argjson failed "${#failed_extensions[@]}" \
        --argjson total "$total_extensions" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '.summary = {success: $success, failed: $failed, total: $total, timestamp: $timestamp}' \
        "$BUILD_REPORT" > "$tmp_report"
    mv "$tmp_report" "$BUILD_REPORT"

    # Summary
    log_info "=========================================="
    log_info "  Build Summary"
    log_info "=========================================="
    log_success "Successfully built: $success_count extensions"
    log_info "Total attempted: $total_extensions extensions"

    if [[ ${#failed_extensions[@]} -gt 0 ]]; then
        log_error "Failed extensions (${#failed_extensions[@]}): ${failed_extensions[*]}"
        log_info ""
        log_info "Build logs saved to: ${LOGS_DIR}/"
        log_info "Build report saved to: ${BUILD_REPORT}"
        log_info ""

        # Show failed extensions summary from report
        log_error "=== Failed Extensions Details ==="
        jq -r '.extensions[] | select(.status == "failed") | "  \(.name) \(.version): \(.error)"' "$BUILD_REPORT"
        echo ""

        if [[ "$CONTINUE_ON_ERROR" != "true" ]]; then
            exit 1
        fi
        log_warn "Continuing despite failures (--continue-on-error)"
    else
        log_success "All extensions built successfully!"
    fi

    log_info ""
    log_info "Build report: ${BUILD_REPORT}"
}

main "$@"
