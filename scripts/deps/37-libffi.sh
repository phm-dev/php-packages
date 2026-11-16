#!/usr/bin/env bash
#
# Build libffi as static library
# https://github.com/libffi/libffi
# License: MIT
# Required by: PHP FFI extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libffi"
VERSION="3.4.8"
URL="https://github.com/libffi/libffi/releases/download/v${VERSION}/libffi-${VERSION}.tar.gz"

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
    --disable-shared

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libffi.so* "${DEPS_PREFIX}/lib"/libffi.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
