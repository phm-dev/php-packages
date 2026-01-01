#!/usr/bin/env bash
#
# Common functions for building static dependencies
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

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

PLATFORM="${PLATFORM:-$(detect_platform)}"
DEPS_PREFIX="${DEPS_PREFIX:-/opt/phm-deps/${PLATFORM}}"
DEPS_SRC="${DEPS_SRC:-/tmp/phm-deps-src}"
DEPS_BUILD="${DEPS_BUILD:-/tmp/phm-deps-build}"

# Number of parallel jobs
NPROC="${NPROC:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

# Compiler settings - explicitly avoid Homebrew paths
export CC="${CC:-clang}"
export CXX="${CXX:-clang++}"

# Target macOS 26 (matches macos-26 runner)
export MACOSX_DEPLOYMENT_TARGET="26.0"

export CFLAGS="-O2 -fPIC -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
export CXXFLAGS="-O2 -fPIC"
export LDFLAGS=""
# Clear any Homebrew pkg-config paths
export PKG_CONFIG_PATH=""
export PKG_CONFIG_LIBDIR=""

# ============================================================================
# Colors and logging
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ============================================================================
# Helper functions
# ============================================================================

# Check if dependency is already built
is_built() {
    local name="$1"
    local marker="${DEPS_PREFIX}/.built-${name}"
    [[ -f "$marker" ]]
}

# Mark dependency as built
mark_built() {
    local name="$1"
    local version="$2"
    echo "$version" > "${DEPS_PREFIX}/.built-${name}"
    log_success "$name $version installed to ${DEPS_PREFIX}"
}

# Download source tarball
download_source() {
    local url="$1"
    local output="$2"

    if [[ -f "$output" ]]; then
        log_info "Using cached $(basename "$output")"
        return 0
    fi

    log_info "Downloading $(basename "$output")..."
    mkdir -p "$(dirname "$output")"
    curl -fSL -o "$output" "$url"
}

# Extract tarball
extract_source() {
    local tarball="$1"
    local dest_dir="$2"

    log_info "Extracting $(basename "$tarball")..."
    mkdir -p "$dest_dir"

    case "$tarball" in
        *.tar.gz|*.tgz)
            tar -xzf "$tarball" -C "$dest_dir" --strip-components=1
            ;;
        *.tar.bz2)
            tar -xjf "$tarball" -C "$dest_dir" --strip-components=1
            ;;
        *.tar.xz)
            tar -xJf "$tarball" -C "$dest_dir" --strip-components=1
            ;;
        *.zip)
            unzip -q "$tarball" -d "$dest_dir"
            # Move contents if there's a single directory
            local contents=("$dest_dir"/*)
            if [[ ${#contents[@]} -eq 1 && -d "${contents[0]}" ]]; then
                mv "${contents[0]}"/* "$dest_dir/"
                rmdir "${contents[0]}"
            fi
            ;;
        *)
            log_error "Unknown archive format: $tarball"
            return 1
            ;;
    esac
}

# Run configure with static library flags
configure_static() {
    local extra_args=("$@")

    ./configure \
        --prefix="$DEPS_PREFIX" \
        --enable-static \
        --disable-shared \
        "${extra_args[@]}"
}

# Run make and make install
make_install() {
    make -j"$NPROC"
    make install
}

# Save license file
save_license() {
    local name="$1"
    local license_file="$2"

    local licenses_dir="${DEPS_PREFIX}/licenses"
    mkdir -p "$licenses_dir"

    if [[ -f "$license_file" ]]; then
        cp "$license_file" "${licenses_dir}/${name}.txt"
        log_info "Saved license for $name"
    else
        log_warn "License file not found: $license_file"
    fi
}

# Clean build directory
clean_build() {
    local build_dir="$1"
    if [[ -d "$build_dir" ]]; then
        rm -rf "$build_dir"
    fi
}

# Initialize deps directories
init_deps_dirs() {
    # Only use sudo if directory doesn't exist or isn't writable
    if [[ ! -d "$DEPS_PREFIX" ]]; then
        sudo mkdir -p "$DEPS_PREFIX"/{lib,include,bin,licenses}
        sudo chown -R "$(whoami)" "$DEPS_PREFIX"
    elif [[ ! -w "$DEPS_PREFIX" ]]; then
        sudo chown -R "$(whoami)" "$DEPS_PREFIX"
    fi
    mkdir -p "$DEPS_PREFIX"/{lib,include,bin,licenses}
    mkdir -p "$DEPS_SRC"
    mkdir -p "$DEPS_BUILD"
    mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"

    # Set PKG_CONFIG_PATH to ONLY our built libraries (no Homebrew)
    export PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig"
    export PKG_CONFIG_LIBDIR="${DEPS_PREFIX}/lib/pkgconfig"

    # Add our libs to compiler/linker paths (no Homebrew)
    export CFLAGS="-O2 -fPIC -I${DEPS_PREFIX}/include"
    export CXXFLAGS="-O2 -fPIC -I${DEPS_PREFIX}/include"
    export LDFLAGS="-L${DEPS_PREFIX}/lib"
    export CPPFLAGS="-I${DEPS_PREFIX}/include"

    log_info "Dependencies prefix: ${DEPS_PREFIX}"
    log_info "Platform: ${PLATFORM}"
    log_info "Parallel jobs: ${NPROC}"
}

# ============================================================================
# Dependency builder wrapper
# ============================================================================

# Build a dependency with standard workflow
# Usage: build_dep <name> <version> <url> <configure_args...>
build_dep() {
    local name="$1"
    local version="$2"
    local url="$3"
    shift 3
    local configure_args=("$@")

    if is_built "$name"; then
        log_info "$name already built, skipping"
        return 0
    fi

    log_info "=========================================="
    log_info "Building $name $version"
    log_info "=========================================="

    local tarball="${DEPS_SRC}/${name}-${version}.tar.gz"
    local build_dir="${DEPS_BUILD}/${name}-${version}"

    # Download
    download_source "$url" "$tarball"

    # Clean and extract
    clean_build "$build_dir"
    extract_source "$tarball" "$build_dir"

    # Build
    cd "$build_dir"
    configure_static "${configure_args[@]}"
    make_install

    # Save license if exists
    for license in LICENSE LICENSE.txt LICENSE.md COPYING COPYING.txt; do
        if [[ -f "$license" ]]; then
            save_license "$name" "$license"
            break
        fi
    done

    # Mark as built
    mark_built "$name" "$version"

    cd - > /dev/null
}

# ============================================================================
# Verification
# ============================================================================

# Verify a static library exists
verify_lib() {
    local lib="$1"
    local path="${DEPS_PREFIX}/lib/${lib}"

    if [[ -f "$path" ]]; then
        log_success "Found: $lib"
        return 0
    else
        log_error "Missing: $lib"
        return 1
    fi
}

# Verify all required static libraries
verify_all_deps() {
    log_info "Verifying built dependencies..."

    local libs=(
        "libz.a"
        "libbz2.a"
        "libedit.a"
        "libssl.a"
        "libcrypto.a"
        "libiconv.a"
        "libicuuc.a"
        "libicui18n.a"
        "libicudata.a"
        "libonig.a"
        "libpng.a"
        "libjpeg.a"
        "libwebp.a"
        "libfreetype.a"
        "libsodium.a"
        "libzip.a"
        "libpq.a"
        "libxml2.a"
        "libxslt.a"
        "libcurl.a"
        "libsqlite3.a"
    )

    local missing=0
    for lib in "${libs[@]}"; do
        if ! verify_lib "$lib"; then
            ((missing++))
        fi
    done

    if [[ $missing -gt 0 ]]; then
        log_error "$missing libraries missing!"
        return 1
    fi

    log_success "All dependencies verified!"
    return 0
}
