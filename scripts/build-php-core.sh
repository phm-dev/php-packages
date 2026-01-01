#!/usr/bin/env bash
#
# Build PHP core packages (common, cli, fpm, dev, cgi)
# Usage: ./build-php-core.sh <php-version> [--quiet]
# Example: ./build-php-core.sh 8.5.0 --quiet
#

set -euo pipefail

# Parse arguments
PHP_VERSION=""
QUIET=false

for arg in "$@"; do
    case "$arg" in
        -q|--quiet)
            QUIET=true
            ;;
        *)
            if [[ -z "$PHP_VERSION" ]]; then
                PHP_VERSION="$arg"
            fi
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="/tmp/php-build-$$"
INSTALL_PREFIX="/opt/php/${PHP_VERSION%.*}"  # e.g., /opt/php/8.5
DIST_DIR="${PROJECT_ROOT}/dist"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Build log file for quiet mode
BUILD_LOG="/tmp/php-build-$$.log"

# Run build command (shows output only on error in quiet mode)
run_build() {
    if [[ "$QUIET" == "true" ]]; then
        if ! "$@" >> "$BUILD_LOG" 2>&1; then
            log_error "Build failed. Last 100 lines of output:"
            tail -100 "$BUILD_LOG" >&2
            return 1
        fi
    else
        "$@"
    fi
}

# Validate arguments
if [[ -z "$PHP_VERSION" ]]; then
    log_error "Usage: $0 <php-version>"
    log_error "Example: $0 8.5.0"
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
PHP_MAJOR_MINOR="${PHP_VERSION%.*}"  # e.g., 8.5

log_info "=========================================="
log_info "  Building PHP ${PHP_VERSION}"
log_info "  Platform: ${PLATFORM}"
log_info "=========================================="

# Cleanup on exit (only if successful)
cleanup() {
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        if [[ -d "$BUILD_DIR" ]]; then
            log_info "Cleaning up build directory..."
            rm -rf "$BUILD_DIR"
        fi
        rm -f "$BUILD_LOG"
    else
        log_warn "Build failed (exit code: $exit_code), keeping build directory for debugging: $BUILD_DIR"
    fi
}
trap cleanup EXIT

# Create directories
mkdir -p "$BUILD_DIR" "$DIST_DIR"
cd "$BUILD_DIR"

# Initialize build log
: > "$BUILD_LOG"

# Set compiler (C++17 support required)
export CC=clang
export CXX=clang++

log_info "Using compiler: CC=$CC, CXX=$CXX"

# Set up paths for static dependencies (macOS)
# Check for macOS using uname (more reliable than $OSTYPE in some shells)
if [[ "$(uname -s)" == "Darwin" ]]; then
    # Use our statically built dependencies instead of Homebrew
    DEPS_PREFIX="/opt/phm-deps/${PLATFORM}"

    if [[ ! -d "$DEPS_PREFIX" ]]; then
        log_error "Static dependencies not found at ${DEPS_PREFIX}"
        log_error "Run php-packages/scripts/deps/build-all-deps.sh first"
        exit 1
    fi

    # Verify critical dependencies exist
    for lib in libz.a libssl.a libcrypto.a libedit.a libxml2.a libcurl.a libsqlite3.a; do
        if [[ ! -f "${DEPS_PREFIX}/lib/${lib}" ]]; then
            log_error "Missing required library: ${lib}"
            log_error "Run php-packages/scripts/deps/build-all-deps.sh first"
            exit 1
        fi
    done

    log_info "Using static dependencies from: ${DEPS_PREFIX}"

    # Set PKG_CONFIG to use ONLY our static libraries
    export PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="${DEPS_PREFIX}/lib/pkgconfig"

    # Compiler flags for static linking
    # CRITICAL: LDFLAGS should only contain -L paths and framework flags, NOT libraries (-l flags)
    # Libraries in LDFLAGS appear before object files and get discarded by the linker
    # This breaks autoconf's AC_CHECK_FUNC tests (e.g., fork() check fails)
    # Libraries like sharpyuv are handled via pkg-config when webp is detected
    export LDFLAGS="-L${DEPS_PREFIX}/lib -framework CoreFoundation -framework CoreServices -framework SystemConfiguration -framework Security"
    export CPPFLAGS="-I${DEPS_PREFIX}/include -I${DEPS_PREFIX}/include/libxml2"
    export CFLAGS="-O2 -I${DEPS_PREFIX}/include -I${DEPS_PREFIX}/include/libxml2"

    # All dependency paths point to our static build
    DEPS_DIR="$DEPS_PREFIX"
    OPENSSL_DIR="$DEPS_PREFIX"
    ZLIB_DIR="$DEPS_PREFIX"
    BZ2_DIR="$DEPS_PREFIX"
    LIBEDIT_DIR="$DEPS_PREFIX"
    ICU_DIR="$DEPS_PREFIX"
    LIBPQ_DIR="$DEPS_PREFIX"
    LIBZIP_DIR="$DEPS_PREFIX"
    ONIGURUMA_DIR="$DEPS_PREFIX"
    FREETYPE_DIR="$DEPS_PREFIX"
    JPEG_DIR="$DEPS_PREFIX"
    LIBPNG_DIR="$DEPS_PREFIX"
    WEBP_DIR="$DEPS_PREFIX"
    LIBXML2_DIR="$DEPS_PREFIX"
    LIBXSLT_DIR="$DEPS_PREFIX"
    CURL_DIR="$DEPS_PREFIX"
    ICONV_DIR="$DEPS_PREFIX"
    SODIUM_DIR="$DEPS_PREFIX"
    SQLITE_DIR="$DEPS_PREFIX"

    # Add our deps bin to PATH (for pg_config, etc.)
    export PATH="${DEPS_PREFIX}/bin:$PATH"

    # Add bison to PATH (required for PHP build) - still need Homebrew for bison
    if command -v brew &>/dev/null; then
        export PATH="$(brew --prefix bison)/bin:$PATH"
    else
        # Fallback: expect bison in PATH
        if ! command -v bison &>/dev/null; then
            log_error "bison not found in PATH. Install bison or Homebrew."
            exit 1
        fi
    fi
else
    log_error "This build script currently only supports macOS"
    exit 1
fi

# Download PHP source
PHP_TARBALL="php-${PHP_VERSION}.tar.gz"
PHP_URL="https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz"

log_info "Downloading PHP ${PHP_VERSION}..."
if ! run_build curl -fSL -o "$PHP_TARBALL" "$PHP_URL"; then
    # Try .tar.bz2 if .tar.gz fails
    PHP_TARBALL="php-${PHP_VERSION}.tar.bz2"
    PHP_URL="https://www.php.net/distributions/php-${PHP_VERSION}.tar.bz2"
    run_build curl -fSL -o "$PHP_TARBALL" "$PHP_URL"
fi

log_info "Extracting source..."
run_build tar xf "$PHP_TARBALL"
cd "php-${PHP_VERSION}"
PHP_SRC_DIR="$(pwd)"

# Configure PHP
log_info "Configuring PHP..."

CONFIGURE_OPTS=(
    --prefix="$INSTALL_PREFIX"
    --with-config-file-path="${INSTALL_PREFIX}/etc"
    --with-config-file-scan-dir="${INSTALL_PREFIX}/etc/conf.d"

    # SAPI
    --enable-cli
    --enable-fpm
    --enable-cgi
    --enable-phpdbg

    # Core features
    --enable-mbstring
    --enable-intl
    --enable-pcntl
    --enable-sockets
    --enable-bcmath
    --enable-calendar
    --enable-exif
    --enable-ftp
    --enable-shmop
    --enable-sysvmsg
    --enable-sysvsem
    --enable-sysvshm

    # Extensions with external deps (using static libraries)
    --with-openssl="${OPENSSL_DIR}"
    --with-zlib="${ZLIB_DIR}"
    --with-bz2="${BZ2_DIR}"
    --with-libedit="${LIBEDIT_DIR}"
    --with-curl="${CURL_DIR}"
    --with-iconv="${ICONV_DIR}"
    --with-sodium="${SODIUM_DIR}"
    --with-zip
    --with-pear

    # Database
    --with-pdo-mysql
    --with-mysqli
    --with-pdo-pgsql="${LIBPQ_DIR}"
    --with-pgsql="${LIBPQ_DIR}"
    --with-pdo-sqlite="${SQLITE_DIR}"
    --with-sqlite3="${SQLITE_DIR}"

    # XML
    --enable-soap
    --enable-dom
    --enable-xml
    --enable-xmlreader
    --enable-xmlwriter
    --enable-simplexml
    --with-xsl="${LIBXSLT_DIR}"
    --with-libxml

    # GD
    --enable-gd
    --with-freetype="${FREETYPE_DIR}"
    --with-jpeg="${JPEG_DIR}"
    --with-webp="${WEBP_DIR}"
)

run_build ./configure "${CONFIGURE_OPTS[@]}"

# Build PHP
log_info "Building PHP (this will take a while)..."
NPROC="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
run_build make -j"$NPROC"

# Install to staging directory
STAGING_DIR="${BUILD_DIR}/staging"
log_info "Installing to staging directory..."
run_build make INSTALL_ROOT="$STAGING_DIR" install

# Create php.ini from production template
log_info "Setting up php.ini..."
mkdir -p "${STAGING_DIR}${INSTALL_PREFIX}/etc/conf.d"
cp php.ini-production "${STAGING_DIR}${INSTALL_PREFIX}/etc/php.ini"

# Determine extension directory name from php-config
EXT_DIR_NAME="$("${STAGING_DIR}${INSTALL_PREFIX}/bin/php-config" --extension-dir | xargs basename)"
FULL_EXT_DIR="${INSTALL_PREFIX}/lib/php/extensions/${EXT_DIR_NAME}"
STAGING_EXT_DIR="${STAGING_DIR}${FULL_EXT_DIR}"

# Create extension directory
log_info "Setting up extensions directory: ${EXT_DIR_NAME}"
mkdir -p "$STAGING_EXT_DIR"

# In PHP 8.5+, OPcache is built into PHP core - no separate .so file
# For older versions, we need to copy opcache.so
PHP_MAJOR="${PHP_VERSION%%.*}"
PHP_MINOR="${PHP_VERSION#*.}"
PHP_MINOR="${PHP_MINOR%%.*}"

if [[ "$PHP_MAJOR" -lt 8 ]] || [[ "$PHP_MAJOR" -eq 8 && "$PHP_MINOR" -lt 5 ]]; then
    # PHP < 8.5: Copy opcache.so
    OPCACHE_FOUND=false
    for opcache_path in \
        "${PHP_SRC_DIR}/modules/opcache.so" \
        "$(pwd)/modules/opcache.so" \
        "${STAGING_DIR}${FULL_EXT_DIR}/opcache.so"
    do
        if [[ -f "$opcache_path" ]]; then
            cp "$opcache_path" "$STAGING_EXT_DIR/"
            log_info "Copied opcache.so from ${opcache_path}"
            OPCACHE_FOUND=true
            break
        fi
    done

    if [[ "$OPCACHE_FOUND" == "false" ]]; then
        log_warn "opcache.so not found - searching entire build directory..."
        FOUND_OPCACHE=$(find "${BUILD_DIR}" -name "opcache.so" -type f 2>/dev/null | head -1)
        if [[ -n "$FOUND_OPCACHE" ]]; then
            cp "$FOUND_OPCACHE" "$STAGING_EXT_DIR/"
            log_info "Copied opcache.so from ${FOUND_OPCACHE}"
        else
            log_error "opcache.so not found anywhere in build directory!"
        fi
    fi
else
    log_info "PHP ${PHP_VERSION}: OPcache is built into PHP core (no separate .so file)"
fi

# Download peclcmd.php and pearcmd.php from PEAR repository
log_info "Downloading PEAR command files..."
PEAR_LIB_DIR="${STAGING_DIR}${INSTALL_PREFIX}/lib/php"
curl -fsSL -o "${PEAR_LIB_DIR}/peclcmd.php" \
    "https://raw.githubusercontent.com/pear/pear-core/master/scripts/peclcmd.php" || \
    log_warn "Failed to download peclcmd.php"
curl -fsSL -o "${PEAR_LIB_DIR}/pearcmd.php" \
    "https://raw.githubusercontent.com/pear/pear-core/master/scripts/pearcmd.php" || \
    log_warn "Failed to download pearcmd.php"

# =============================================================================
# Create separated CLI/FPM configuration structure (like Ubuntu/Debian)
# =============================================================================
log_info "Setting up separated CLI/FPM configuration..."

ETC_DIR="${STAGING_DIR}${INSTALL_PREFIX}/etc"
MODS_DIR="${ETC_DIR}/mods-available"
CLI_DIR="${ETC_DIR}/cli"
FPM_DIR="${ETC_DIR}/fpm"

# Create directory structure
mkdir -p "${MODS_DIR}"
mkdir -p "${CLI_DIR}/conf.d"
mkdir -p "${FPM_DIR}/conf.d"
mkdir -p "${FPM_DIR}/pool.d"

# Base php.ini template with common settings
PHP_INI_TEMPLATE="${STAGING_DIR}${INSTALL_PREFIX}/etc/php.ini"

# Apply common settings to template
sed -i '' 's/;date.timezone =/date.timezone = UTC/' "$PHP_INI_TEMPLATE"
sed -i '' 's/;opcache.enable=1/opcache.enable=1/' "$PHP_INI_TEMPLATE"
sed -i '' 's/;opcache.memory_consumption=128/opcache.memory_consumption=256/' "$PHP_INI_TEMPLATE"
sed -i '' 's/;opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=16/' "$PHP_INI_TEMPLATE"
sed -i '' 's/;opcache.max_accelerated_files=10000/opcache.max_accelerated_files=20000/' "$PHP_INI_TEMPLATE"
sed -i '' 's/;opcache.validate_timestamps=1/opcache.validate_timestamps=1/' "$PHP_INI_TEMPLATE"
sed -i '' "s|;extension_dir = \"ext\"|extension_dir = \"${FULL_EXT_DIR}\"|" "$PHP_INI_TEMPLATE"

# Create CLI php.ini (optimized for command-line usage)
cp "$PHP_INI_TEMPLATE" "${CLI_DIR}/php.ini"
sed -i '' 's/memory_limit = 128M/memory_limit = -1/' "${CLI_DIR}/php.ini"
sed -i '' 's/max_execution_time = 30/max_execution_time = 0/' "${CLI_DIR}/php.ini"
sed -i '' 's/max_input_time = 60/max_input_time = -1/' "${CLI_DIR}/php.ini"
sed -i '' 's/upload_max_filesize = 2M/upload_max_filesize = -1/' "${CLI_DIR}/php.ini"
sed -i '' 's/post_max_size = 8M/post_max_size = -1/' "${CLI_DIR}/php.ini"
sed -i '' 's/display_errors = Off/display_errors = On/' "${CLI_DIR}/php.ini"
sed -i '' 's/display_startup_errors = Off/display_startup_errors = On/' "${CLI_DIR}/php.ini"
sed -i '' 's/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/error_reporting = E_ALL/' "${CLI_DIR}/php.ini"
sed -i '' 's/log_errors = On/log_errors = Off/' "${CLI_DIR}/php.ini"
sed -i '' 's/html_errors = On/html_errors = Off/' "${CLI_DIR}/php.ini"
sed -i '' 's/implicit_flush = Off/implicit_flush = On/' "${CLI_DIR}/php.ini"
# Add PHM-specific settings for CLI
cat >> "${CLI_DIR}/php.ini" << 'EOFCLI'

; === PHM CLI Settings ===

; Scan for additional .ini files
EOFCLI
echo "scan_dir = ${INSTALL_PREFIX}/etc/cli/conf.d" >> "${CLI_DIR}/php.ini"
cat >> "${CLI_DIR}/php.ini" << 'EOFCLI'

; Realpath cache - helps Composer and other tools
realpath_cache_size = 4096K
realpath_cache_ttl = 600
EOFCLI

# Create FPM php.ini (optimized for development on modern MacBooks)
cp "$PHP_INI_TEMPLATE" "${FPM_DIR}/php.ini"

# Resource limits - generous for development
sed -i '' 's/memory_limit = 128M/memory_limit = 512M/' "${FPM_DIR}/php.ini"
sed -i '' 's/max_execution_time = 30/max_execution_time = 300/' "${FPM_DIR}/php.ini"
sed -i '' 's/max_input_time = 60/max_input_time = 300/' "${FPM_DIR}/php.ini"

# Upload limits - comfortable for development
sed -i '' 's/upload_max_filesize = 2M/upload_max_filesize = 128M/' "${FPM_DIR}/php.ini"
sed -i '' 's/post_max_size = 8M/post_max_size = 128M/' "${FPM_DIR}/php.ini"

# Error display - helpful for development
sed -i '' 's/display_errors = Off/display_errors = On/' "${FPM_DIR}/php.ini"
sed -i '' 's/display_startup_errors = Off/display_startup_errors = On/' "${FPM_DIR}/php.ini"
sed -i '' 's/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/error_reporting = E_ALL/' "${FPM_DIR}/php.ini"

# Session - longer lifetime for development
sed -i '' 's/session.gc_maxlifetime = 1440/session.gc_maxlifetime = 7200/' "${FPM_DIR}/php.ini"

# Add PHM-specific settings for development
cat >> "${FPM_DIR}/php.ini" << 'EOFPHM'

; === PHM Development Settings ===

; Scan for additional .ini files
EOFPHM
echo "scan_dir = ${INSTALL_PREFIX}/etc/fpm/conf.d" >> "${FPM_DIR}/php.ini"
cat >> "${FPM_DIR}/php.ini" << 'EOFPHM'

; Realpath cache - critical for framework performance
realpath_cache_size = 4096K
realpath_cache_ttl = 600

; Input variables - needed for complex forms
max_input_vars = 5000

; Security (less important for dev, but good practice)
expose_php = Off
EOFPHM

# Remove template (we now have separate cli/fpm versions)
rm -f "$PHP_INI_TEMPLATE"

# Create opcache.ini in mods-available
# PHP 8.5+: OPcache is built-in, no need for zend_extension line
if [[ "$PHP_MAJOR" -lt 8 ]] || [[ "$PHP_MAJOR" -eq 8 && "$PHP_MINOR" -lt 5 ]]; then
    cat > "${MODS_DIR}/opcache.ini" << EOF
; OPcache configuration (optimized for development)
; Priority: 10
zend_extension=opcache.so
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=1
; revalidate_freq=0 means check for file changes on every request (best for dev)
opcache.revalidate_freq=0
opcache.save_comments=1
; JIT disabled by default (can cause issues with debuggers)
opcache.jit=off
EOF
else
    cat > "${MODS_DIR}/opcache.ini" << EOF
; OPcache configuration (optimized for development)
; Priority: 10
; Note: In PHP 8.5+, OPcache is built into PHP core (no zend_extension needed)
opcache.enable=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=1
; revalidate_freq=0 means check for file changes on every request (best for dev)
opcache.revalidate_freq=0
opcache.save_comments=1
; JIT disabled by default (can cause issues with debuggers)
opcache.jit=off
EOF
fi

# Enable opcache for both CLI and FPM by default
ln -sf "${INSTALL_PREFIX}/etc/mods-available/opcache.ini" "${CLI_DIR}/conf.d/10-opcache.ini"
ln -sf "${INSTALL_PREFIX}/etc/mods-available/opcache.ini" "${FPM_DIR}/conf.d/10-opcache.ini"

# Remove old conf.d if exists
rm -rf "${ETC_DIR}/conf.d"

# Create php-fpm.conf with version-specific settings
log_info "Setting up php-fpm configuration..."

# Create run directory path
FPM_RUN_DIR="/var/run/php"
FPM_SOCKET="${FPM_RUN_DIR}/php${PHP_MAJOR_MINOR}-fpm.sock"
FPM_PID_FILE="${FPM_RUN_DIR}/php${PHP_MAJOR_MINOR}-fpm.pid"

# Create php-fpm.conf in fpm directory
cat > "${FPM_DIR}/php-fpm.conf" << FPMCONF
[global]
pid = ${FPM_PID_FILE}
error_log = /var/log/php${PHP_MAJOR_MINOR}-fpm.log
log_level = notice

; Include pool configurations
include=${INSTALL_PREFIX}/etc/fpm/pool.d/*.conf
FPMCONF

# Create www pool with version-specific socket
# Uses {{PHM_USER}} and {{PHM_GROUP}} placeholders - replaced during installation
cat > "${FPM_DIR}/pool.d/www.conf" << 'POOLCONF'
[www]
; Pool name - runs as installing user for easy development
; These values are replaced during 'phm install' with the actual user
user = {{PHM_USER}}
group = {{PHM_GROUP}}

; Socket - version specific to allow multiple PHP versions
POOLCONF

# Add non-placeholder parts
cat >> "${FPM_DIR}/pool.d/www.conf" << POOLCONF
listen = ${FPM_SOCKET}

; Socket ownership - user owns it, _www group can access (for Nginx)
POOLCONF

cat >> "${FPM_DIR}/pool.d/www.conf" << 'POOLCONF'
listen.owner = {{PHM_USER}}
listen.group = _www
listen.mode = 0660

; Process manager
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500

; Status and ping
pm.status_path = /fpm-status
ping.path = /fpm-ping

; Logging
POOLCONF

cat >> "${FPM_DIR}/pool.d/www.conf" << POOLCONF
access.log = /var/log/php${PHP_MAJOR_MINOR}-fpm-access.log
slowlog = /var/log/php${PHP_MAJOR_MINOR}-fpm-slow.log
request_slowlog_timeout = 5s

; Security
security.limit_extensions = .php
POOLCONF

# Remove old php-fpm.d if exists (we now use fpm/pool.d)
rm -rf "${STAGING_DIR}${INSTALL_PREFIX}/etc/php-fpm.d"
rm -f "${STAGING_DIR}${INSTALL_PREFIX}/etc/php-fpm.conf"

# Create LaunchDaemon plist for macOS
LAUNCHD_DIR="${STAGING_DIR}/Library/LaunchDaemons"
mkdir -p "$LAUNCHD_DIR"
cat > "${LAUNCHD_DIR}/com.phm.php${PHP_MAJOR_MINOR}-fpm.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.phm.php${PHP_MAJOR_MINOR}-fpm</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_PREFIX}/sbin/php-fpm</string>
        <string>--nodaemonize</string>
        <string>--fpm-config</string>
        <string>${INSTALL_PREFIX}/etc/fpm/php-fpm.conf</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <true/>
    <key>WorkingDirectory</key>
    <string>${INSTALL_PREFIX}</string>
    <key>StandardErrorPath</key>
    <string>/var/log/php${PHP_MAJOR_MINOR}-fpm-error.log</string>
    <key>StandardOutPath</key>
    <string>/var/log/php${PHP_MAJOR_MINOR}-fpm-out.log</string>
</dict>
</plist>
PLIST

# Now package everything into separate packages
log_info "Creating packages..."

source "${SCRIPT_DIR}/package.sh"

# =============================================================================
# Create packages using NEW naming convention: php{VERSION}-{type}_{platform}.tar.zst
# Example: php8.5.0-cli_darwin-arm64.tar.zst
# =============================================================================

# Package: php8.5.0-common (shared files)
create_php_core_package "common" "$PHP_VERSION" "$PLATFORM" \
    "${STAGING_DIR}${INSTALL_PREFIX}/etc" \
    --description "PHP ${PHP_VERSION} common files"

# Package: php8.5.0-cli
create_php_core_package "cli" "$PHP_VERSION" "$PLATFORM" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/php" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/phar" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/phar.phar" \
    --description "PHP ${PHP_VERSION} CLI interpreter" \
    --depends "php${PHP_VERSION}-common"

# Package: php8.5.0-fpm (includes LaunchDaemon)
create_php_core_package "fpm" "$PHP_VERSION" "$PLATFORM" \
    "${STAGING_DIR}${INSTALL_PREFIX}/sbin/php-fpm" \
    "${STAGING_DIR}/Library/LaunchDaemons/com.phm.php${PHP_MAJOR_MINOR}-fpm.plist" \
    --description "PHP ${PHP_VERSION} FPM (FastCGI Process Manager)" \
    --depends "php${PHP_VERSION}-common"

# Package: php8.5.0-cgi
create_php_core_package "cgi" "$PHP_VERSION" "$PLATFORM" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/php-cgi" \
    --description "PHP ${PHP_VERSION} CGI binary" \
    --depends "php${PHP_VERSION}-common"

# Package: php8.5.0-dev (headers, phpize, php-config)
create_php_core_package "dev" "$PHP_VERSION" "$PLATFORM" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/phpize" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/php-config" \
    "${STAGING_DIR}${INSTALL_PREFIX}/include" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/build" \
    --description "PHP ${PHP_VERSION} development files" \
    --depends "php${PHP_VERSION}-common"

# Note: OPcache is now built separately via build-opcache.yml workflow
# For PHP 8.5+, opcache is built into PHP

# Package: php8.5.0-pear (pecl)
create_php_core_package "pear" "$PHP_VERSION" "$PLATFORM" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/pecl" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/pear" \
    "${STAGING_DIR}${INSTALL_PREFIX}/bin/peardev" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/.registry" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/.channels" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/Archive" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/Console" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/OS" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/PEAR" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/PEAR.php" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/Structures" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/System.php" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/XML" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/peclcmd.php" \
    "${STAGING_DIR}${INSTALL_PREFIX}/lib/php/pearcmd.php" \
    --description "PHP ${PHP_VERSION} PEAR/PECL package manager" \
    --depends "php${PHP_VERSION}-cli"

# Built-in extensions packages (these are compiled into PHP but we can track them)
BUILTIN_EXTENSIONS=(
    "curl:cURL support"
    "gd:GD graphics library"
    "intl:Internationalization support"
    "mbstring:Multibyte string support"
    "mysql:MySQL support (mysqli, pdo_mysql)"
    "pgsql:PostgreSQL support"
    "sqlite3:SQLite3 support"
    "xml:XML support"
    "zip:ZIP support"
    "soap:SOAP support"
    "bcmath:BCMath arbitrary precision"
    "sockets:Socket support"
    "pcntl:Process control"
    "libedit:Libedit (readline alternative) support"
    "calendar:Calendar functions"
    "exif:EXIF metadata"
    "ftp:FTP support"
)

# Create meta-packages for built-in extensions (they just depend on common)
for ext_entry in "${BUILTIN_EXTENSIONS[@]}"; do
    ext_name="${ext_entry%%:*}"
    ext_desc="${ext_entry#*:}"

    # Create empty package that just marks the extension as installed
    create_meta_package "php${PHP_MAJOR_MINOR}-${ext_name}" "$PHP_VERSION" "1" "$PLATFORM" \
        --description "PHP ${PHP_MAJOR_MINOR} ${ext_desc}" \
        --depends "php${PHP_MAJOR_MINOR}-common (>= ${PHP_VERSION})" \
        --provides "php-${ext_name}"
done

# Meta-package: php8.5 (installs cli + common, like Debian)
create_meta_package "php${PHP_MAJOR_MINOR}" "$PHP_VERSION" "1" "$PLATFORM" \
    --description "PHP ${PHP_MAJOR_MINOR} meta-package (CLI + common)" \
    --depends "php${PHP_MAJOR_MINOR}-cli (>= ${PHP_VERSION}), php${PHP_MAJOR_MINOR}-common (>= ${PHP_VERSION})" \
    --provides "php"

log_info "=========================================="
log_info "  Build complete!"
log_info "  Packages created in: ${DIST_DIR}"
log_info "=========================================="
ls -la "${DIST_DIR}/"*.tar.zst 2>/dev/null || true

# =============================================================================
# Install PHP to /opt/php for extension building
# =============================================================================
log_info "Installing PHP to ${INSTALL_PREFIX} for extension building..."

# Extract core packages (new naming: php{VERSION}-{type}_{platform}.tar.zst)
for pkg in "${DIST_DIR}/php${PHP_VERSION}-common_"*.tar.zst \
           "${DIST_DIR}/php${PHP_VERSION}-cli_"*.tar.zst \
           "${DIST_DIR}/php${PHP_VERSION}-dev_"*.tar.zst \
           "${DIST_DIR}/php${PHP_VERSION}-pear_"*.tar.zst; do
    if [[ -f "$pkg" ]]; then
        log_info "  Extracting $(basename "$pkg")..."
        sudo mkdir -p "$INSTALL_PREFIX"
        zstd -dc "$pkg" | sudo tar -xf - -C / --strip-components=1 files/
    fi
done

# Verify installation
if [[ -x "${INSTALL_PREFIX}/bin/php" ]]; then
    log_info "PHP installed successfully:"
    "${INSTALL_PREFIX}/bin/php" -v
else
    log_error "PHP installation failed!"
    exit 1
fi

# =============================================================================
# Verify static linking - ensure no Homebrew dependencies
# =============================================================================
log_info "Verifying library dependencies..."

HOMEBREW_DEPS=$(otool -L "${INSTALL_PREFIX}/bin/php" 2>/dev/null | grep -E "/opt/homebrew|/usr/local/Cellar" || true)

if [[ -n "$HOMEBREW_DEPS" ]]; then
    log_warn "WARNING: PHP still links to Homebrew libraries:"
    echo "$HOMEBREW_DEPS"
    log_warn "This may cause issues on systems without Homebrew"
else
    log_info "SUCCESS: PHP has no Homebrew dependencies!"
fi

# Show all dynamic libraries for reference
log_info "Dynamic library dependencies:"
otool -L "${INSTALL_PREFIX}/bin/php" | head -20
