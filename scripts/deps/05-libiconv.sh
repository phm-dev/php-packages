#!/usr/bin/env bash
#
# Build libiconv as static library
# https://www.gnu.org/software/libiconv/
# License: LGPL (static linking is OK for proprietary use with some conditions)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libiconv"
VERSION="1.17"
URL="https://ftp.gnu.org/pub/gnu/libiconv/libiconv-${VERSION}.tar.gz"

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

./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-nls

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libiconv.so* "${DEPS_PREFIX}/lib"/libiconv.dylib* 2>/dev/null || true
rm -f "${DEPS_PREFIX}/lib"/libcharset.so* "${DEPS_PREFIX}/lib"/libcharset.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "COPYING"

# Mark as built
mark_built "$NAME" "$VERSION"
