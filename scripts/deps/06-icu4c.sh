#!/usr/bin/env bash
#
# Build ICU4C as static library
# https://icu.unicode.org/
# License: ICU License (permissive, similar to MIT)
#
# Cache ref: v2 - ensure all static libraries (libicudata 30MB+) are included
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="icu4c"
VERSION="74-2"
VERSION_UNDERSCORE="${VERSION//-/_}"
URL="https://github.com/unicode-org/icu/releases/download/release-${VERSION}/icu4c-${VERSION_UNDERSCORE}-src.tgz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

log_info "=========================================="
log_info "Building $NAME $VERSION"
log_info "=========================================="

TARBALL="${DEPS_SRC}/${NAME}-${VERSION}.tgz"
BUILD_DIR="${DEPS_BUILD}/${NAME}-${VERSION}"

# Download
download_source "$URL" "$TARBALL"

# Clean and extract
clean_build "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ICU has a different structure - source is in icu/source
log_info "Extracting $(basename "$TARBALL")..."
tar -xzf "$TARBALL" -C "$BUILD_DIR"

# Build
cd "${BUILD_DIR}/icu/source"

./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-samples \
    --disable-tests \
    --disable-extras \
    --with-data-packaging=static

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libicu*.so* "${DEPS_PREFIX}/lib"/libicu*.dylib* 2>/dev/null || true

# Save license
save_license "$NAME" "${BUILD_DIR}/icu/LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
