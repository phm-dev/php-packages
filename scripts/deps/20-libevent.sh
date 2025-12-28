#!/usr/bin/env bash
#
# Build libevent as static library
# https://libevent.org/
# License: BSD-3-Clause
#
# Depends on: openssl
# Required by: libmemcached
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libevent"
VERSION="2.1.12"
URL="https://github.com/libevent/libevent/releases/download/release-${VERSION}-stable/libevent-${VERSION}-stable.tar.gz"

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
    --disable-samples \
    --disable-libevent-regress \
    CFLAGS="${CFLAGS}" \
    CPPFLAGS="-I${DEPS_PREFIX}/include" \
    LDFLAGS="${LDFLAGS} -L${DEPS_PREFIX}/lib" \
    LIBS="-lssl -lcrypto" \
    PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libevent*.so* "${DEPS_PREFIX}/lib"/libevent*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
