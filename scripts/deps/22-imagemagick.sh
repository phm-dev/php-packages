#!/usr/bin/env bash
#
# Build ImageMagick as static library
# https://imagemagick.org/
# License: Apache-2.0 (ImageMagick License)
#
# Depends on: zlib, libpng, libjpeg-turbo, freetype, libwebp
# Required by: PHP imagick extension
#
# Note: Building minimal ImageMagick with only essential features
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="imagemagick"
VERSION="7.1.1-41"
URL="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/${VERSION}.tar.gz"

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

TARBALL="${DEPS_SRC}/${NAME}-${VERSION}.tar.gz"
BUILD_DIR="${DEPS_BUILD}/${NAME}-${VERSION}"

# Download
download_source "$URL" "$TARBALL"

# Clean and extract
clean_build "$BUILD_DIR"
extract_source "$TARBALL" "$BUILD_DIR"

# Build
cd "$BUILD_DIR"

# Configure with minimal features for PHP imagick extension
./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-openmp \
    --disable-opencl \
    --disable-deprecated \
    --disable-installed \
    --disable-docs \
    --without-modules \
    --without-perl \
    --without-magick-plus-plus \
    --without-utilities \
    --without-bzlib \
    --without-x \
    --without-xml \
    --without-fontconfig \
    --without-heic \
    --without-jxl \
    --without-lcms \
    --without-lzma \
    --without-openjp2 \
    --without-pango \
    --without-raw \
    --without-rsvg \
    --without-tiff \
    --without-wmf \
    --without-djvu \
    --without-dps \
    --without-fftw \
    --without-flif \
    --without-fpx \
    --without-gslib \
    --without-gvc \
    --without-jbig \
    --without-lqr \
    --without-openexr \
    --without-raqm \
    --without-zstd \
    --with-zlib="${DEPS_PREFIX}" \
    --with-png="${DEPS_PREFIX}" \
    --with-jpeg="${DEPS_PREFIX}" \
    --with-freetype="${DEPS_PREFIX}" \
    --with-webp="${DEPS_PREFIX}" \
    CFLAGS="${CFLAGS}" \
    CXXFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}" \
    PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libMagick*.so* "${DEPS_PREFIX}/lib"/libMagick*.dylib* 2>/dev/null || true

# Create pkg-config files if not created properly
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"

# The configure should create these, but let's verify
if [[ ! -f "${DEPS_PREFIX}/lib/pkgconfig/MagickWand.pc" ]]; then
    log_warn "MagickWand.pc not found, creating..."
    cat > "${DEPS_PREFIX}/lib/pkgconfig/MagickWand.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include/ImageMagick-7

Name: MagickWand
Description: ImageMagick MagickWand library
Version: ${VERSION%-*}
Requires: MagickCore
Libs: -L\${libdir} -lMagickWand-7.Q16HDRI
Cflags: -I\${includedir}
EOF
fi

if [[ ! -f "${DEPS_PREFIX}/lib/pkgconfig/MagickCore.pc" ]]; then
    log_warn "MagickCore.pc not found, creating..."
    cat > "${DEPS_PREFIX}/lib/pkgconfig/MagickCore.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include/ImageMagick-7

Name: MagickCore
Description: ImageMagick MagickCore library
Version: ${VERSION%-*}
Libs: -L\${libdir} -lMagickCore-7.Q16HDRI
Libs.private: -lpng -ljpeg -lfreetype -lwebp -lz
Cflags: -I\${includedir}
EOF
fi

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
