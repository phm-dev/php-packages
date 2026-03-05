#!/usr/bin/env bash
#
# Build GMP as static library
# https://gmplib.org/
# License: LGPL-3.0+ / GPL-2.0+
# Required by: PHP gmp extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="gmp"
VERSION="6.3.0"
URL="https://ftp.gnu.org/gnu/gmp/gmp-${VERSION}.tar.xz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
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
    --disable-shared

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libgmp.so* "${DEPS_PREFIX}/lib"/libgmp.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "COPYING.LESSERv3"

# Mark as built
mark_built "$NAME" "$VERSION"
