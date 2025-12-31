#!/usr/bin/env bash
#
# Build GraphicsMagick as static library
# http://www.graphicsmagick.org/
# License: MIT
#
# Required by: PHP gmagick extension
#
# Depends on: zlib, libpng, libjpeg-turbo, freetype, libwebp
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="graphicsmagick"
VERSION="1.3.45"
URL="https://sourceforge.net/projects/graphicsmagick/files/graphicsmagick/${VERSION}/GraphicsMagick-${VERSION}.tar.xz/download"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
for dep in zlib libpng jpeg-turbo freetype webp; do
    if ! is_built "$dep"; then
        log_error "$dep must be built first"
        exit 1
    fi
done

log_info "=========================================="
log_info "Building $NAME $VERSION"
log_info "=========================================="

TARBALL="${DEPS_SRC}/${NAME}-${VERSION}.tar.xz"
BUILD_DIR="${DEPS_BUILD}/${NAME}-${VERSION}"

# Download
if [[ ! -f "$TARBALL" ]]; then
    log_info "Downloading $(basename "$TARBALL")..."
    mkdir -p "$(dirname "$TARBALL")"
    curl -fSL -o "$TARBALL" "$URL"
fi

# Clean and extract
clean_build "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
tar -xJf "$TARBALL" -C "$BUILD_DIR" --strip-components=1

# Build
cd "$BUILD_DIR"

./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-openmp \
    --without-perl \
    --without-x \
    --without-lcms2 \
    --without-lzma \
    --without-bzlib \
    --without-xml \
    --without-tiff \
    --without-jbig \
    --without-jp2 \
    --without-heif \
    --without-jxl \
    --with-zlib="${DEPS_PREFIX}" \
    --with-png="${DEPS_PREFIX}" \
    --with-jpeg="${DEPS_PREFIX}" \
    --with-freetype="${DEPS_PREFIX}" \
    --with-webp="${DEPS_PREFIX}" \
    CFLAGS="${CFLAGS}" \
    CPPFLAGS="-I${DEPS_PREFIX}/include" \
    LDFLAGS="${LDFLAGS} -L${DEPS_PREFIX}/lib" \
    PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libGraphicsMagick*.so* "${DEPS_PREFIX}/lib"/libGraphicsMagick*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "Copyright.txt"

# Mark as built
mark_built "$NAME" "$VERSION"
