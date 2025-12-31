#!/usr/bin/env bash
#
# Build libssh2 as static library
# https://www.libssh2.org/
# License: BSD 3-Clause
#
# Required by: PHP ssh2 extension
# Depends on: openssl
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libssh2"
VERSION="1.11.1"
URL="https://www.libssh2.org/download/libssh2-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
if ! is_built "openssl"; then
    log_error "openssl must be built first"
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

./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --with-crypto=openssl \
    --with-libssl-prefix="$DEPS_PREFIX" \
    CFLAGS="${CFLAGS}" \
    CPPFLAGS="-I${DEPS_PREFIX}/include" \
    LDFLAGS="${LDFLAGS} -L${DEPS_PREFIX}/lib"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libssh2*.so* "${DEPS_PREFIX}/lib"/libssh2*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "COPYING"

# Mark as built
mark_built "$NAME" "$VERSION"
