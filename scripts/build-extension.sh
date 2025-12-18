#!/usr/bin/env bash
#
# Build PHP extension using PIE (with PECL fallback)
# Usage: ./build-extension.sh <extension> <ext_version> <php_version> [options...]
#
# Examples:
#   ./build-extension.sh redis 6.3.0 8.5.0
#   ./build-extension.sh xdebug 3.4.0 8.4.7
#   ./build-extension.sh redis 6.3.0 8.5.0 --enable-redis-igbinary --enable-redis-zstd
#
# Compatible with Bash 3.2+ (macOS default)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_ROOT}/extensions/config.json"
DIST_DIR="${DIST_DIR:-${PROJECT_ROOT}/dist}"

# Source package utilities
source "${SCRIPT_DIR}/package.sh"

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
EXTENSION=""
EXT_VERSION=""
PHP_VERSION=""
QUIET=false
declare -a PIE_OPTIONS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        --*)
            PIE_OPTIONS+=("$1")
            shift
            ;;
        *)
            if [[ -z "$EXTENSION" ]]; then
                EXTENSION="$1"
            elif [[ -z "$EXT_VERSION" ]]; then
                EXT_VERSION="$1"
            elif [[ -z "$PHP_VERSION" ]]; then
                PHP_VERSION="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$EXTENSION" || -z "$EXT_VERSION" || -z "$PHP_VERSION" ]]; then
    echo "Usage: $0 <extension> <ext_version> <php_version> [pie_options...]"
    echo "Example: $0 redis 6.3.0 8.5.0 --enable-redis-igbinary"
    exit 1
fi

# Detect platform
detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"
    case "$arch" in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
    esac
    echo "${os}-${arch}"
}

PLATFORM="$(detect_platform)"
PHP_MAJOR_MINOR="${PHP_VERSION%.*}"
PHP_PATH="/opt/php/${PHP_MAJOR_MINOR}"
PHP_BIN="${PHP_PATH}/bin/php"
PHPIZE="${PHP_PATH}/bin/phpize"
PHP_CONFIG="${PHP_PATH}/bin/php-config"
PECL_BIN="${PHP_PATH}/bin/pecl"

# Build directory
BUILD_DIR="/tmp/ext-build-${EXTENSION}-$$"
BUILD_LOG="${BUILD_DIR}/build.log"

cleanup() {
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR"
    fi
}
trap cleanup EXIT

# Run build command (shows output only on error in quiet mode)
run_build() {
    if [[ "$QUIET" == "true" ]]; then
        if ! "$@" >> "$BUILD_LOG" 2>&1; then
            log_error "Build failed. Last 50 lines of output:"
            tail -50 "$BUILD_LOG" >&2
            return 1
        fi
    else
        "$@"
    fi
}

# Check PHP installation
check_php() {
    if [[ ! -x "$PHP_BIN" ]]; then
        log_error "PHP ${PHP_VERSION} not found at ${PHP_PATH}"
        log_info "Please install PHP first or download from releases"
        exit 1
    fi

    log_info "Using PHP: $($PHP_BIN -v | head -1)"
}

# Load extension config from JSON
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_warn "Config file not found: $CONFIG_FILE"
        return 1
    fi

    if ! command -v jq &>/dev/null; then
        log_warn "jq not found, cannot parse config"
        return 1
    fi

    local ext_config
    ext_config=$(jq -r ".extensions.${EXTENSION} // empty" "$CONFIG_FILE" 2>/dev/null)

    if [[ -z "$ext_config" ]]; then
        log_warn "Extension ${EXTENSION} not found in config"
        return 1
    fi

    # Load config values
    PACKAGIST=$(echo "$ext_config" | jq -r '.packagist // empty')
    IS_ZEND=$(echo "$ext_config" | jq -r '.zend_extension // false')
    PRIORITY=$(echo "$ext_config" | jq -r '.priority // 20')
    DESCRIPTION=$(echo "$ext_config" | jq -r '.description // empty')
    SPECIAL_BUILD=$(echo "$ext_config" | jq -r '.special_build // false')

    # Load brew dependencies into array (Bash 3.2 compatible)
    BREW_DEPS=()
    while IFS= read -r dep; do
        [[ -n "$dep" ]] && BREW_DEPS+=("$dep")
    done < <(echo "$ext_config" | jq -r '.brew_deps[]? // empty' 2>/dev/null)

    # Load default PIE options from config (if not provided via CLI)
    if [[ ${#PIE_OPTIONS[@]} -eq 0 ]]; then
        while IFS= read -r opt; do
            [[ -n "$opt" ]] && PIE_OPTIONS+=("$opt")
        done < <(echo "$ext_config" | jq -r '.pie_options[]? // empty' 2>/dev/null)
    fi

    return 0
}

# Install brew dependencies
install_brew_deps() {
    if [[ ${#BREW_DEPS[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Installing brew dependencies: ${BREW_DEPS[*]}"

    for dep in "${BREW_DEPS[@]}"; do
        if [[ -n "$dep" ]]; then
            brew install "$dep" 2>/dev/null || true
        fi
    done
}

# Set up environment
setup_env() {
    export PATH="${PHP_PATH}/bin:$PATH"
    export CC=clang
    export CXX=clang++

    if [[ "$OSTYPE" == "darwin"* ]]; then
        BREW_PREFIX="$(brew --prefix)"
        export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/openssl@3/lib/pkgconfig"
        export LDFLAGS="-L${BREW_PREFIX}/lib"
        export CPPFLAGS="-I${BREW_PREFIX}/include"
    fi
}

# Try to build with PIE
build_with_pie() {
    log_info "Attempting build with PIE..."

    local pie_phar="${BUILD_DIR}/pie.phar"

    # Download PIE
    log_info "Downloading PIE..."
    local pie_url="https://github.com/php/pie/releases/latest/download/pie.phar"

    mkdir -p "$BUILD_DIR"
    if ! curl -fsSL --retry 3 --retry-delay 2 "$pie_url" -o "$pie_phar" 2>/dev/null; then
        log_warn "Failed to download PIE"
        return 1
    fi
    chmod +x "$pie_phar"

    if [[ ! -s "$pie_phar" ]]; then
        log_warn "PIE download resulted in empty file"
        return 1
    fi

    if [[ -z "$PACKAGIST" || "$PACKAGIST" == "null" ]]; then
        log_warn "No packagist package defined for ${EXTENSION}"
        return 1
    fi

    # Build PIE command - options are passed directly (no -- separator)
    local pie_args=("$pie_phar" "build" "${PACKAGIST}:${EXT_VERSION}")

    # Add PIE options (configure options) - PIE accepts them directly
    if [[ ${#PIE_OPTIONS[@]} -gt 0 ]]; then
        for opt in "${PIE_OPTIONS[@]}"; do
            [[ -n "$opt" ]] && pie_args+=("$opt")
        done
    fi

    log_info "Running: $PHP_BIN ${pie_args[*]}"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    : > "$BUILD_LOG"

    if run_build "$PHP_BIN" "${pie_args[@]}"; then
        log_success "PIE build successful"
        return 0
    else
        log_warn "PIE build failed"
        return 1
    fi
}

# Fallback to PECL binary (if available)
build_with_pecl() {
    log_info "Attempting PECL build..."

    if [[ ! -x "$PECL_BIN" ]]; then
        log_warn "PECL not found at ${PECL_BIN}"
        return 1
    fi

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    : > "$BUILD_LOG"

    # Download and extract
    log_info "Downloading ${EXTENSION}-${EXT_VERSION}..."
    if ! run_build "$PECL_BIN" download "${EXTENSION}-${EXT_VERSION}"; then
        log_error "Failed to download extension"
        return 1
    fi

    tar xf "${EXTENSION}-${EXT_VERSION}.tgz" 2>/dev/null || tar xf "${EXTENSION}"-*.tgz 2>/dev/null
    cd "${EXTENSION}-${EXT_VERSION}" 2>/dev/null || cd "${EXTENSION}"-* 2>/dev/null

    # Build configure options string
    local configure_opts=("--with-php-config=${PHP_CONFIG}")
    if [[ ${#PIE_OPTIONS[@]} -gt 0 ]]; then
        for opt in "${PIE_OPTIONS[@]}"; do
            [[ -n "$opt" ]] && configure_opts+=("$opt")
        done
    fi

    log_info "Building with options: ${configure_opts[*]}"

    run_build "$PHPIZE"
    run_build ./configure "${configure_opts[@]}"
    run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

    log_success "PECL build successful"
    return 0
}

# Manual build from pecl.php.net (no pecl binary needed)
build_manual() {
    log_info "Attempting manual build from pecl.php.net..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    : > "$BUILD_LOG"

    # Download from pecl.php.net
    local pecl_url="https://pecl.php.net/get/${EXTENSION}-${EXT_VERSION}.tgz"
    log_info "Downloading from ${pecl_url}..."

    if ! curl -fsSL --retry 3 "$pecl_url" -o "${EXTENSION}-${EXT_VERSION}.tgz"; then
        log_warn "Failed to download from pecl.php.net"
        return 1
    fi

    # Extract
    tar xf "${EXTENSION}-${EXT_VERSION}.tgz" 2>/dev/null
    cd "${EXTENSION}-${EXT_VERSION}" 2>/dev/null || cd "${EXTENSION}"-* 2>/dev/null || {
        log_warn "Failed to find extracted directory"
        return 1
    }

    # Build configure options string
    local configure_opts=("--with-php-config=${PHP_CONFIG}")
    if [[ ${#PIE_OPTIONS[@]} -gt 0 ]]; then
        for opt in "${PIE_OPTIONS[@]}"; do
            [[ -n "$opt" ]] && configure_opts+=("$opt")
        done
    fi

    log_info "Building with options: ${configure_opts[*]}"

    if ! run_build "$PHPIZE"; then
        log_warn "phpize failed"
        return 1
    fi

    if ! run_build ./configure "${configure_opts[@]}"; then
        log_warn "configure failed"
        return 1
    fi

    if ! run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"; then
        log_warn "make failed"
        return 1
    fi

    log_success "Manual build successful"
    return 0
}

# Special build for relay (pre-built binaries)
build_relay() {
    log_info "Downloading pre-built Relay extension..."

    local arch="${PLATFORM#darwin-}"
    local relay_url="https://builds.r2.relay.so/v${EXT_VERSION}/relay-v${EXT_VERSION}-php${PHP_MAJOR_MINOR}-darwin-${arch}.tar.gz"

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if ! curl -fsSL -o relay.tar.gz "$relay_url"; then
        log_warn "Pre-built Relay not available for this platform"
        return 1
    fi

    tar xf relay.tar.gz
    log_success "Downloaded Relay extension"
    return 0
}

# Find the built .so file
find_extension_so() {
    local ext_dir
    ext_dir=$("$PHP_CONFIG" --extension-dir 2>/dev/null || echo "")

    # Check in extension directory
    if [[ -n "$ext_dir" && -f "${ext_dir}/${EXTENSION}.so" ]]; then
        echo "${ext_dir}/${EXTENSION}.so"
        return 0
    fi

    # Check in build directory
    local found
    found=$(find "$BUILD_DIR" -name "${EXTENSION}.so" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi

    # Check in modules subdirectory
    found=$(find "$BUILD_DIR" -path "*/modules/${EXTENSION}.so" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi

    return 1
}

# Create the package
create_pkg() {
    local so_file="$1"

    log_info "Creating package..."

    # Get extension directory name
    local ext_dir_name=""
    if [[ -d "/opt/php/${PHP_MAJOR_MINOR}/lib/php/extensions" ]]; then
        ext_dir_name=$(ls "/opt/php/${PHP_MAJOR_MINOR}/lib/php/extensions" 2>/dev/null | head -1)
    fi

    local pkg_opts=()
    [[ -n "$DESCRIPTION" ]] && pkg_opts+=("--description" "$DESCRIPTION")
    [[ -n "$PRIORITY" ]] && pkg_opts+=("--priority" "$PRIORITY")
    [[ "$IS_ZEND" == "true" ]] && pkg_opts+=("--zend")
    [[ -n "$ext_dir_name" ]] && pkg_opts+=("--ext-dir" "$ext_dir_name")

    create_extension_package_v2 \
        "$EXTENSION" \
        "$EXT_VERSION" \
        "$PHP_VERSION" \
        "$PLATFORM" \
        "$so_file" \
        "${pkg_opts[@]}"
}

# Main
main() {
    log_info "=========================================="
    log_info "  Building extension: ${EXTENSION}"
    log_info "  Extension version: ${EXT_VERSION}"
    log_info "  PHP version: ${PHP_VERSION}"
    log_info "  Platform: ${PLATFORM}"
    log_info "=========================================="

    # Initialize defaults
    PACKAGIST=""
    IS_ZEND="false"
    PRIORITY="20"
    DESCRIPTION="${EXTENSION} extension for PHP"
    SPECIAL_BUILD="false"
    BREW_DEPS=()

    # Check PHP
    check_php

    # Setup environment
    setup_env

    # Load config (optional - provides defaults)
    load_config || true

    # Install dependencies
    install_brew_deps

    # Build extension
    local build_success=false

    if [[ "$SPECIAL_BUILD" == "true" && "$EXTENSION" == "relay" ]]; then
        # Special handling for relay
        if build_relay; then
            build_success=true
        fi
    else
        # Try build methods in order: PIE -> PECL -> Manual
        if build_with_pie; then
            build_success=true
        elif build_with_pecl; then
            build_success=true
        elif build_manual; then
            build_success=true
        fi
    fi

    if [[ "$build_success" != "true" ]]; then
        log_error "All build methods failed for ${EXTENSION}"
        if [[ -f "$BUILD_LOG" ]]; then
            log_error "Build log:"
            tail -50 "$BUILD_LOG"
        fi
        exit 1
    fi

    # Find .so file
    local so_file
    so_file=$(find_extension_so) || {
        log_error "Could not find built extension: ${EXTENSION}.so"
        exit 1
    }

    log_info "Found extension: $so_file"

    # Create package
    create_pkg "$so_file"

    log_info "=========================================="
    log_info "  Extension build complete!"
    log_info "  Package: php${PHP_VERSION}-${EXTENSION}${EXT_VERSION}_${PLATFORM}.tar.zst"
    log_info "=========================================="
}

main "$@"
