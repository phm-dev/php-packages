#!/usr/bin/env bash
#
# Build libxslt as static library
# https://gitlab.gnome.org/GNOME/libxslt
# License: MIT
#
# Depends on: libxml2
# Cache ref: v2 - ensure pkgconfig is included in artifact
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libxslt"
VERSION="1.1.42"
URL="https://download.gnome.org/sources/libxslt/1.1/libxslt-${VERSION}.tar.xz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
if ! is_built "libxml2"; then
    log_error "libxml2 must be built first"
    exit 1
fi

log_info "=========================================="
log_info "Building $NAME $VERSION"
log_info "=========================================="

TARBALL="${DEPS_SRC}/${NAME}-${VERSION}.tar.xz"
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
    --with-libxml-prefix="${DEPS_PREFIX}" \
    --without-python \
    --without-crypto

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libxslt.so* "${DEPS_PREFIX}/lib"/libxslt.dylib* 2>/dev/null || true
rm -f "${DEPS_PREFIX}/lib"/libexslt.so* "${DEPS_PREFIX}/lib"/libexslt.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "Copyright"

# Mark as built
mark_built "$NAME" "$VERSION"
