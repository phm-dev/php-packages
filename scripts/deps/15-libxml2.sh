#!/usr/bin/env bash
#
# Build libxml2 as static library
# https://gitlab.gnome.org/GNOME/libxml2
# License: MIT
#
# Depends on: zlib, libiconv
# Pkgconfig: libxml-2.0.pc
#
# Cache ref: v2 - ensure pkgconfig is included in artifact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libxml2"
VERSION="2.12.9"
URL="https://download.gnome.org/sources/libxml2/2.12/libxml2-${VERSION}.tar.xz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
for dep in zlib libiconv; do
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
    --with-zlib="${DEPS_PREFIX}" \
    --with-iconv="${DEPS_PREFIX}" \
    --without-python \
    --without-lzma \
    --without-readline

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libxml2.so* "${DEPS_PREFIX}/lib"/libxml2.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "Copyright"

# Mark as built
mark_built "$NAME" "$VERSION"
