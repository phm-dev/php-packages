#!/usr/bin/env bash
#
# Build lz4 as static library
# https://github.com/lz4/lz4
# License: BSD 2-Clause
#
# Required by: PHP lz4 extension, redis (optional)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="lz4"
VERSION="1.10.0"
URL="https://github.com/lz4/lz4/releases/download/v${VERSION}/lz4-${VERSION}.tar.gz"

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

# Build - lz4 uses Makefile, not autotools
cd "$BUILD_DIR"

make -j"$NPROC" \
    PREFIX="$DEPS_PREFIX" \
    BUILD_SHARED=no \
    CFLAGS="${CFLAGS}" \
    lib

make PREFIX="$DEPS_PREFIX" BUILD_SHARED=no install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/liblz4.so* "${DEPS_PREFIX}/lib"/liblz4.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
