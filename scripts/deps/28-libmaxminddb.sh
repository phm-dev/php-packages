#!/usr/bin/env bash
#
# Build libmaxminddb as static library
# https://github.com/maxmind/libmaxminddb
# License: Apache-2.0
#
# Required by: PHP maxminddb extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libmaxminddb"
VERSION="1.11.0"
URL="https://github.com/maxmind/libmaxminddb/releases/download/${VERSION}/libmaxminddb-${VERSION}.tar.gz"

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
    --disable-tests \
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libmaxminddb*.so* "${DEPS_PREFIX}/lib"/libmaxminddb*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
