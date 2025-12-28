#!/usr/bin/env bash
#
# Build libzip as static library
# https://libzip.org/
# License: BSD 3-clause
#
# Depends on: zlib, bzip2, openssl
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libzip"
VERSION="1.10.1"
URL="https://libzip.org/download/libzip-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
for dep in zlib bzip2 openssl; do
    if ! is_built "$dep"; then
        log_error "$dep must be built first"
        exit 1
    fi
done

log_info "=========================================="
log_info "Building $NAME $VERSION"
log_info "=========================================="

TARBALL="${DEPS_SRC}/${NAME}-${VERSION}.tar.gz"
BUILD_DIR="${DEPS_BUILD}/${NAME}-${VERSION}"

# Download
download_source "$URL" "$TARBALL"

# Clean and extract
clean_build "$BUILD_DIR"
extract_source "$TARBALL" "$BUILD_DIR"

# Build using CMake
cd "$BUILD_DIR"
mkdir -p build && cd build

cmake .. \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TOOLS=OFF \
    -DBUILD_REGRESS=OFF \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_DOC=OFF \
    -DENABLE_ZSTD=OFF \
    -DENABLE_LZMA=OFF \
    -DZLIB_LIBRARY="${DEPS_PREFIX}/lib/libz.a" \
    -DZLIB_INCLUDE_DIR="${DEPS_PREFIX}/include" \
    -DBZIP2_LIBRARY="${DEPS_PREFIX}/lib/libbz2.a" \
    -DBZIP2_INCLUDE_DIR="${DEPS_PREFIX}/include" \
    -DOPENSSL_ROOT_DIR="${DEPS_PREFIX}" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libzip.so* "${DEPS_PREFIX}/lib"/libzip.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "../LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
