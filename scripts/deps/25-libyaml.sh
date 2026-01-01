#!/usr/bin/env bash
#
# Build libyaml as static library
# https://github.com/yaml/libyaml
# License: MIT
#
# Required by: PHP yaml extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libyaml"
VERSION="0.2.5"
URL="https://github.com/yaml/libyaml/releases/download/${VERSION}/yaml-${VERSION}.tar.gz"

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
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libyaml*.so* "${DEPS_PREFIX}/lib"/libyaml*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "License"

# Mark as built
mark_built "$NAME" "$VERSION"
