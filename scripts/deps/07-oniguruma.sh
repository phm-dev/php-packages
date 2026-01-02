#!/usr/bin/env bash
#
# Build Oniguruma as static library (regex library for mbstring)
# https://github.com/kkos/oniguruma
# License: BSD 2-clause
#

# Cache ref: v2 - ensure pkgconfig is included in artifact
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="oniguruma"
VERSION="6.9.9"
URL="https://github.com/kkos/oniguruma/releases/download/v${VERSION}/onig-${VERSION}.tar.gz"

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
rm -f "${DEPS_PREFIX}/lib"/libonig.so* "${DEPS_PREFIX}/lib"/libonig.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "COPYING"

# Mark as built
mark_built "$NAME" "$VERSION"
