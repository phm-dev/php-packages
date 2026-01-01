#!/usr/bin/env bash
#
# Build libpng as static library
# http://www.libpng.org/pub/png/libpng.html
# License: libpng license (permissive)
#
# Depends on: zlib
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libpng"
VERSION="1.6.43"
URL="https://downloads.sourceforge.net/libpng/libpng-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependency
if ! is_built "zlib"; then
    log_error "zlib must be built first"
    exit 1
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

# Build
cd "$BUILD_DIR"

# Explicitly set CPPFLAGS/LDFLAGS to use only our zlib, not Homebrew's
CPPFLAGS="-I${DEPS_PREFIX}/include" \
LDFLAGS="-L${DEPS_PREFIX}/lib" \
CFLAGS="-O2 -fPIC -I${DEPS_PREFIX}/include" \
./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --with-zlib-prefix="$DEPS_PREFIX" \
    ZLIB_CFLAGS="-I${DEPS_PREFIX}/include" \
    ZLIB_LIBS="-L${DEPS_PREFIX}/lib -lz"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libpng*.so* "${DEPS_PREFIX}/lib"/libpng*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
