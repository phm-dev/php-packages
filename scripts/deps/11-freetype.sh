#!/usr/bin/env bash
#
# Build FreeType as static library
# https://freetype.org/
# License: FreeType License (BSD-style) or GPL2
#
# Depends on: zlib, bzip2, libpng
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="freetype"
VERSION="2.13.3"
URL="https://downloads.sourceforge.net/freetype/freetype-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
for dep in zlib bzip2 libpng; do
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
    --with-zlib=yes \
    --with-bzip2=yes \
    --with-png=yes \
    --with-harfbuzz=no \
    --with-brotli=no \
    ZLIB_CFLAGS="-I${DEPS_PREFIX}/include" \
    ZLIB_LIBS="-L${DEPS_PREFIX}/lib -lz" \
    BZIP2_CFLAGS="-I${DEPS_PREFIX}/include" \
    BZIP2_LIBS="-L${DEPS_PREFIX}/lib -lbz2" \
    LIBPNG_CFLAGS="-I${DEPS_PREFIX}/include" \
    LIBPNG_LIBS="-L${DEPS_PREFIX}/lib -lpng -lz"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libfreetype.so* "${DEPS_PREFIX}/lib"/libfreetype.dylib* 2>/dev/null || true

# Save license (FreeType uses its own license)
save_license "$NAME" "docs/FTL.TXT"

# Mark as built
mark_built "$NAME" "$VERSION"
