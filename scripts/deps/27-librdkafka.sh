#!/usr/bin/env bash
#
# Build librdkafka as static library
# https://github.com/confluentinc/librdkafka
# License: BSD 2-Clause
#
# Required by: PHP rdkafka extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="librdkafka"
VERSION="2.6.1"
URL="https://github.com/confluentinc/librdkafka/archive/refs/tags/v${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
for dep in openssl zstd lz4; do
    if ! is_built "$dep"; then
        log_error "$dep must be built first"
        exit 1
    fi
done

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

# librdkafka's configure expects env vars, not command-line args for CFLAGS etc.
export CFLAGS="${CFLAGS}"
export CPPFLAGS="-I${DEPS_PREFIX}/include"
export LDFLAGS="${LDFLAGS} -L${DEPS_PREFIX}/lib"
export PKG_CONFIG_PATH="${DEPS_PREFIX}/lib/pkgconfig"

./configure \
    --prefix="$DEPS_PREFIX" \
    --disable-gssapi \
    --disable-lz4-ext \
    --enable-static \
    --enable-ssl \
    --enable-zstd

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/librdkafka*.so* "${DEPS_PREFIX}/lib"/librdkafka*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
