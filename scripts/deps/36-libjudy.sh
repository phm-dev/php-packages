#!/usr/bin/env bash
#
# Build Judy as static library
# http://judy.sourceforge.net/
# License: LGPL 2.1
#
# Required by: PHP memprof extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libjudy"
VERSION="1.0.5"
URL="https://downloads.sourceforge.net/project/judy/judy/Judy-${VERSION}/Judy-${VERSION}.tar.gz"

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

# _FORTIFY_SOURCE conflicts with Judy's own macro definitions on some toolchains
./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-dependency-tracking \
    CFLAGS="${CFLAGS} -D_FORTIFY_SOURCE=0"

# Judy's build is not safe for parallel make
make
make install

# Save license
save_license "$NAME" "COPYING"

# Mark as built
mark_built "$NAME" "$VERSION"
