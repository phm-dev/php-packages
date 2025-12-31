#!/usr/bin/env bash
#
# Build libmcrypt as static library
# https://sourceforge.net/projects/mcrypt/
# License: LGPL 2.1
#
# Required by: PHP mcrypt extension
#
# Note: libmcrypt is deprecated and unmaintained since 2007.
# The PHP mcrypt extension was removed from PHP 7.2+ core.
# Use sodium or openssl instead for new projects.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libmcrypt"
VERSION="2.5.8"
URL="https://downloads.sourceforge.net/project/mcrypt/Libmcrypt/${VERSION}/libmcrypt-${VERSION}.tar.gz"

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

# libmcrypt is old and may need some fixes for modern compilers
# Disable -Werror if present
./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-posix-threads \
    CFLAGS="${CFLAGS} -Wno-implicit-function-declaration" \
    LDFLAGS="${LDFLAGS}"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libmcrypt*.so* "${DEPS_PREFIX}/lib"/libmcrypt*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "COPYING.LIB"

# Mark as built
mark_built "$NAME" "$VERSION"
