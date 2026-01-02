#!/usr/bin/env bash
#
# Build zlib as static library
# https://zlib.net/
# License: zlib (permissive)
#

# Cache ref: v2 - ensure pkgconfig is included in artifact
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="zlib"
VERSION="1.3.1"
URL="https://zlib.net/zlib-${VERSION}.tar.gz"

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

# Build
cd "$BUILD_DIR"

# zlib uses a custom configure script
./configure \
    --prefix="$DEPS_PREFIX" \
    --static

make -j"$NPROC"
make install

# Remove shared libs if any were created
rm -f "${DEPS_PREFIX}/lib"/libz.so* "${DEPS_PREFIX}/lib"/libz.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
