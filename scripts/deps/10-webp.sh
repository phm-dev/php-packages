#!/usr/bin/env bash
#
# Build libwebp as static library
# https://developers.google.com/speed/webp
# License: BSD 3-clause
#
# Depends on: libpng, jpeg-turbo
# Note: Also produces libsharpyuv.a, libwebpdemux.a, libwebpmux.a
# Pkgconfig: libwebp.pc, libwebpdemux.pc, libwebpmux.pc
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="webp"
VERSION="1.4.0"
URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
for dep in libpng jpeg-turbo; do
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

# Build
cd "$BUILD_DIR"

./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --enable-libwebpmux \
    --enable-libwebpdemux \
    --with-pngincludedir="${DEPS_PREFIX}/include" \
    --with-pnglibdir="${DEPS_PREFIX}/lib" \
    --with-jpegincludedir="${DEPS_PREFIX}/include" \
    --with-jpeglibdir="${DEPS_PREFIX}/lib"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libwebp*.so* "${DEPS_PREFIX}/lib"/libwebp*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "COPYING"

# Mark as built
mark_built "$NAME" "$VERSION"
