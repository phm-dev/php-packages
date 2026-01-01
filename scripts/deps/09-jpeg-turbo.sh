#!/usr/bin/env bash
#
# Build libjpeg-turbo as static library
# https://libjpeg-turbo.org/
# License: BSD 3-clause, IJG, zlib
#
# Cache ref: v2 - ensure pkgconfig is included in artifact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="jpeg-turbo"
VERSION="3.0.4"
URL="https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${VERSION}/libjpeg-turbo-${VERSION}.tar.gz"

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

# Build using CMake
cd "$BUILD_DIR"
mkdir -p build && cd build

cmake .. \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_STATIC=ON \
    -DENABLE_SHARED=OFF \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libjpeg.so* "${DEPS_PREFIX}/lib"/libjpeg.dylib* 2>/dev/null || true
rm -f "${DEPS_PREFIX}/lib"/libturbojpeg.so* "${DEPS_PREFIX}/lib"/libturbojpeg.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "../LICENSE.md"

# Mark as built
mark_built "$NAME" "$VERSION"
