#!/usr/bin/env bash
#
# Build zstd as static library
# https://github.com/facebook/zstd
# License: BSD + GPLv2
#
# Required by: mongodb extension, redis extension (optional)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="zstd"
VERSION="1.5.6"
URL="https://github.com/facebook/zstd/releases/download/v${VERSION}/zstd-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

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

# Build using cmake for better control
mkdir -p "$BUILD_DIR/cmake-build"
cd "$BUILD_DIR/cmake-build"

cmake "$BUILD_DIR/build/cmake" \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_BUILD_PROGRAMS=OFF \
    -DZSTD_BUILD_TESTS=OFF \
    -DCMAKE_C_FLAGS="${CFLAGS}"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libzstd.so* "${DEPS_PREFIX}/lib"/libzstd.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "${BUILD_DIR}/LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
