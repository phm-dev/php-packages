#!/usr/bin/env bash
#
# Build libgearman as static library
# https://github.com/gearman/gearmand
# License: BSD 3-Clause
#
# Required by: PHP gearman extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libgearman"
VERSION="1.1.21"
URL="https://github.com/gearman/gearmand/releases/download/${VERSION}/gearmand-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
if ! is_built "libevent"; then
    log_error "libevent must be built first"
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
    --disable-libdrizzle \
    --disable-libmemcached \
    --disable-libpq \
    --disable-hiredis \
    --disable-tokyocabinet \
    --without-mysql \
    --without-postgresql \
    --with-boost=no \
    CFLAGS="${CFLAGS}" \
    CXXFLAGS="${CFLAGS}" \
    CPPFLAGS="-I${DEPS_PREFIX}/include" \
    LDFLAGS="${LDFLAGS} -L${DEPS_PREFIX}/lib" \
    LIBEVENT_CFLAGS="-I${DEPS_PREFIX}/include" \
    LIBEVENT_LIBS="-L${DEPS_PREFIX}/lib -levent"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libgearman*.so* "${DEPS_PREFIX}/lib"/libgearman*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "COPYING"

# Mark as built
mark_built "$NAME" "$VERSION"
