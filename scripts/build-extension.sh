#!/usr/bin/env bash
#
# Build PECL extension package
# Usage: ./build-extension.sh <extension> <php-version> [--quiet]
# Example: ./build-extension.sh redis 8.5.0 --quiet
#
# Compatible with Bash 3.2+ (macOS default)
#

set -euo pipefail

# Parse arguments
EXTENSION=""
PHP_VERSION=""
QUIET=false

for arg in "$@"; do
    case "$arg" in
        -q|--quiet)
            QUIET=true
            ;;
        *)
            if [[ -z "$EXTENSION" ]]; then
                EXTENSION="$arg"
            elif [[ -z "$PHP_VERSION" ]]; then
                PHP_VERSION="$arg"
            fi
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/ext-build-$$"
DIST_DIR="${PROJECT_ROOT}/dist"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Build log file for quiet mode
BUILD_LOG="/tmp/build-ext-$$.log"

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

# Validate arguments
if [[ -z "$EXTENSION" ]] || [[ -z "$PHP_VERSION" ]]; then
    log_error "Usage: $0 <extension> <php-version>"
    log_error "Example: $0 redis 8.5.0"
    exit 1
fi

PHP_MAJOR_MINOR="${PHP_VERSION%.*}"
INSTALL_PREFIX="/opt/php/${PHP_MAJOR_MINOR}"

# Check if PHP is installed
if [[ ! -x "${INSTALL_PREFIX}/bin/php" ]]; then
    log_error "PHP ${PHP_MAJOR_MINOR} not found at ${INSTALL_PREFIX}"
    log_error "Please install php${PHP_MAJOR_MINOR}-cli first"
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

log_info "=========================================="
log_info "  Building extension: ${EXTENSION}"
log_info "  PHP version: ${PHP_VERSION}"
log_info "  Platform: ${PLATFORM}"
log_info "=========================================="

# Set up environment
export PATH="${INSTALL_PREFIX}/bin:$PATH"
export CC=clang
export CXX=clang++

if [[ "$OSTYPE" == "darwin"* ]]; then
    BREW_PREFIX="$(brew --prefix)"
    export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/opt/openssl@3/lib/pkgconfig"
    export LDFLAGS="-L${BREW_PREFIX}/lib"
    export CPPFLAGS="-I${BREW_PREFIX}/include"
fi

# Cleanup on exit
cleanup() {
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "Cleaning up..."
        rm -rf "$BUILD_DIR"
    fi
    rm -f "$BUILD_LOG"
}
trap cleanup EXIT

mkdir -p "$BUILD_DIR" "$DIST_DIR"
cd "$BUILD_DIR"

# Initialize build log
: > "$BUILD_LOG"

# Source package helper
source "${SCRIPT_DIR}/package.sh"

# Extension configuration function (Bash 3.2 compatible)
get_ext_config() {
    local ext="$1"
    local field="$2"

    case "$ext" in
        redis)
            case "$field" in
                version) echo "6.3.0" ;;
                pecl_name) echo "redis" ;;
                description) echo "Redis client extension" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        igbinary)
            case "$field" in
                version) echo "3.2.16" ;;
                pecl_name) echo "igbinary" ;;
                description) echo "Binary serializer" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        mongodb)
            case "$field" in
                version) echo "2.1.4" ;;
                pecl_name) echo "mongodb" ;;
                description) echo "MongoDB driver" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        amqp)
            case "$field" in
                version) echo "2.1.2" ;;
                pecl_name) echo "amqp" ;;
                description) echo "RabbitMQ AMQP client" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "rabbitmq-c" ;;
            esac
            ;;
        xdebug)
            case "$field" in
                version) echo "3.5.0" ;;
                pecl_name) echo "xdebug" ;;
                description) echo "Debugger and profiler" ;;
                depends) echo "" ;;
                zend) echo "true" ;;
                priority) echo "30" ;;
                static_lib) echo "" ;;
            esac
            ;;
        swoole)
            case "$field" in
                version) echo "6.0.0" ;;
                pecl_name) echo "swoole" ;;
                description) echo "Async programming framework" ;;
                depends) echo "php${PHP_MAJOR_MINOR}-sockets" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        ssh2)
            case "$field" in
                version) echo "1.4.1" ;;
                pecl_name) echo "ssh2" ;;
                description) echo "SSH2 client" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "libssh2" ;;
            esac
            ;;
        uuid)
            case "$field" in
                version) echo "1.2.1" ;;
                pecl_name) echo "uuid" ;;
                description) echo "UUID generation" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        mcrypt)
            case "$field" in
                version) echo "1.0.7" ;;
                pecl_name) echo "mcrypt" ;;
                description) echo "Encryption functions" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "libmcrypt" ;;
            esac
            ;;
        pcov)
            case "$field" in
                version) echo "1.0.12" ;;
                pecl_name) echo "pcov" ;;
                description) echo "Code coverage driver" ;;
                depends) echo "" ;;
                zend) echo "true" ;;
                priority) echo "30" ;;
                static_lib) echo "" ;;
            esac
            ;;
        apcu)
            case "$field" in
                version) echo "5.1.28" ;;
                pecl_name) echo "apcu" ;;
                description) echo "APC User Cache" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        memcached)
            case "$field" in
                version) echo "3.4.0" ;;
                pecl_name) echo "memcached" ;;
                description) echo "Memcached client" ;;
                depends) echo "php${PHP_MAJOR_MINOR}-igbinary" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        imagick)
            case "$field" in
                version) echo "3.7.0" ;;
                pecl_name) echo "imagick" ;;
                description) echo "ImageMagick binding" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "imagemagick" ;;
            esac
            ;;
        relay)
            case "$field" in
                version) echo "0.8.1" ;;
                pecl_name) echo "relay" ;;
                description) echo "High-performance Redis client" ;;
                depends) echo "" ;;
                zend) echo "false" ;;
                priority) echo "20" ;;
                static_lib) echo "" ;;
            esac
            ;;
        *)
            echo ""
            ;;
    esac
}

# Get extension configuration
EXT_VERSION=$(get_ext_config "$EXTENSION" "version")
if [[ -z "$EXT_VERSION" ]]; then
    log_error "Unknown extension: ${EXTENSION}"
    log_error "Available: redis, igbinary, mongodb, amqp, xdebug, swoole, ssh2, uuid, mcrypt, pcov, apcu, memcached, imagick, relay"
    exit 1
fi

PECL_NAME=$(get_ext_config "$EXTENSION" "pecl_name")
EXT_DESC=$(get_ext_config "$EXTENSION" "description")
EXT_DEPS=$(get_ext_config "$EXTENSION" "depends")
IS_ZEND=$(get_ext_config "$EXTENSION" "zend")
PRIORITY=$(get_ext_config "$EXTENSION" "priority")
STATIC_LIB=$(get_ext_config "$EXTENSION" "static_lib")

log_info "Extension version: ${EXT_VERSION}"
log_info "Description: ${EXT_DESC}"

# Build static library if required
STATIC_LIB_PATH=""

if [[ -n "$STATIC_LIB" ]]; then
    log_info "Building static ${STATIC_LIB}..."
    STATIC_LIB_PATH="${BUILD_DIR}/static-libs"
    mkdir -p "$STATIC_LIB_PATH"

    case "$STATIC_LIB" in
        rabbitmq-c)
            run_build git clone --depth 1 https://github.com/alanxz/rabbitmq-c.git
            cd rabbitmq-c
            mkdir build && cd build
            run_build cmake .. \
                -DCMAKE_INSTALL_PREFIX="$STATIC_LIB_PATH" \
                -DBUILD_SHARED_LIBS=OFF \
                -DBUILD_STATIC_LIBS=ON \
                -DBUILD_EXAMPLES=OFF \
                -DBUILD_TESTS=OFF \
                -DBUILD_TOOLS=OFF
            run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
            run_build make install
            cd "$BUILD_DIR"

            export AMQP_CFLAGS="-I${STATIC_LIB_PATH}/include"
            export AMQP_LIBS="${STATIC_LIB_PATH}/lib/librabbitmq.a"
            ;;

        libssh2)
            run_build curl -fSL -o libssh2.tar.gz "https://www.libssh2.org/download/libssh2-1.11.0.tar.gz"
            tar xf libssh2.tar.gz
            cd libssh2-*
            run_build ./configure \
                --prefix="$STATIC_LIB_PATH" \
                --disable-shared \
                --enable-static \
                --with-openssl="$(brew --prefix openssl@3)"
            run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
            run_build make install
            cd "$BUILD_DIR"

            export SSH2_CFLAGS="-I${STATIC_LIB_PATH}/include"
            export SSH2_LIBS="${STATIC_LIB_PATH}/lib/libssh2.a -L$(brew --prefix openssl@3)/lib -lssl -lcrypto"
            ;;

        libmcrypt)
            curl -fSL -o libmcrypt.tar.gz "https://sourceforge.net/projects/mcrypt/files/Libmcrypt/2.5.8/libmcrypt-2.5.8.tar.gz/download" || true
            if [[ -f libmcrypt.tar.gz ]]; then
                tar xf libmcrypt.tar.gz
                cd libmcrypt-*
                run_build ./configure \
                    --prefix="$STATIC_LIB_PATH" \
                    --disable-shared \
                    --enable-static
                run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
                run_build make install
                cd "$BUILD_DIR"

                export MCRYPT_CFLAGS="-I${STATIC_LIB_PATH}/include"
                export MCRYPT_LIBS="${STATIC_LIB_PATH}/lib/libmcrypt.a"
            else
                log_warn "Could not download libmcrypt, trying system library"
            fi
            ;;

        imagemagick)
            log_warn "ImageMagick static build is complex - using dynamic linking"
            log_warn "Users will need ImageMagick installed"
            ;;
    esac
fi

# Build extension
log_info "Building ${EXTENSION} extension..."
cd "$BUILD_DIR"

SO_FILE=""

# Special build procedures for certain extensions
case "$EXTENSION" in
    amqp)
        run_build pecl download "amqp-${EXT_VERSION}"
        tar xf "amqp-${EXT_VERSION}.tgz"
        cd "amqp-${EXT_VERSION}"

        run_build phpize
        run_build ./configure \
            --with-php-config="${INSTALL_PREFIX}/bin/php-config" \
            --with-amqp \
            CFLAGS="${AMQP_CFLAGS:-}" \
            LDFLAGS="${AMQP_LIBS:-}"
        run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

        SO_FILE="$(pwd)/modules/amqp.so"
        ;;

    ssh2)
        run_build pecl download "ssh2-${EXT_VERSION}"
        tar xf "ssh2-${EXT_VERSION}.tgz"
        cd "ssh2-${EXT_VERSION}"

        run_build phpize
        run_build ./configure \
            --with-php-config="${INSTALL_PREFIX}/bin/php-config" \
            --with-ssh2="${STATIC_LIB_PATH:-$(brew --prefix libssh2)}"
        run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)" \
            LDFLAGS="${SSH2_LIBS:-}"

        SO_FILE="$(pwd)/modules/ssh2.so"
        ;;

    swoole)
        run_build pecl download "swoole-${EXT_VERSION}"
        tar xf "swoole-${EXT_VERSION}.tgz"
        cd "swoole-${EXT_VERSION}"

        run_build phpize
        run_build ./configure \
            --with-php-config="${INSTALL_PREFIX}/bin/php-config" \
            --enable-swoole \
            --enable-sockets \
            --enable-openssl \
            --enable-http2 \
            --enable-mysqlnd \
            --with-openssl-dir="$(brew --prefix openssl@3)"
        run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

        SO_FILE="$(pwd)/modules/swoole.so"
        ;;

    xdebug)
        run_build pecl download "xdebug-${EXT_VERSION}"
        tar xf "xdebug-${EXT_VERSION}.tgz"
        cd "xdebug-${EXT_VERSION}"

        run_build phpize
        run_build ./configure \
            --with-php-config="${INSTALL_PREFIX}/bin/php-config" \
            --enable-xdebug
        run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

        SO_FILE="$(pwd)/modules/xdebug.so"
        ;;

    relay)
        log_info "Downloading pre-built Relay extension..."
        RELAY_URL="https://builds.r2.relay.so/v${EXT_VERSION}/relay-v${EXT_VERSION}-php${PHP_MAJOR_MINOR}-darwin-${PLATFORM#darwin-}.tar.gz"

        if curl -fSL -o relay.tar.gz "$RELAY_URL" 2>/dev/null; then
            tar xf relay.tar.gz
            SO_FILE="$(find . -name 'relay.so' | head -1)"
        else
            log_warn "Pre-built Relay not available for this platform"
            exit 0
        fi
        ;;

    *)
        # Standard PECL build
        log_info "Standard PECL build for ${EXTENSION}..."

        run_build pecl download "${PECL_NAME}-${EXT_VERSION}"
        tar xf "${PECL_NAME}-${EXT_VERSION}.tgz"
        cd "${PECL_NAME}-${EXT_VERSION}"

        run_build phpize
        run_build ./configure --with-php-config="${INSTALL_PREFIX}/bin/php-config"
        run_build make -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

        SO_FILE="$(pwd)/modules/${EXTENSION}.so"
        ;;
esac

# Verify .so file exists
if [[ ! -f "$SO_FILE" ]]; then
    log_error "Build failed: ${SO_FILE} not found"
    exit 1
fi

log_info "Extension built: ${SO_FILE}"

# Create package
ZEND_FLAG=""
PRIORITY_FLAG=""

if [[ "$IS_ZEND" == "true" ]]; then
    ZEND_FLAG="--zend"
fi

PRIORITY_FLAG="--priority $PRIORITY"

create_extension_package \
    "$EXTENSION" \
    "$EXT_VERSION" \
    "$PHP_VERSION" \
    "1" \
    "$PLATFORM" \
    "$SO_FILE" \
    --description "$EXT_DESC" \
    --depends "$EXT_DEPS" \
    $ZEND_FLAG \
    $PRIORITY_FLAG

log_info "=========================================="
log_info "  Extension build complete!"
log_info "  Package created in: ${DIST_DIR}"
log_info "=========================================="
