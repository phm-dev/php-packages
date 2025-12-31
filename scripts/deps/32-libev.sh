#!/usr/bin/env bash
#
# Build libev as static library
# http://software.schmorp.de/pkg/libev.html
# License: BSD 2-Clause
#
# Required by: PHP ev extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libev"
VERSION="4.33"
URL="http://dist.schmorp.de/libev/libev-${VERSION}.tar.gz"

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
rm -f "${DEPS_PREFIX}/lib"/libev.so* "${DEPS_PREFIX}/lib"/libev.dylib* 2>/dev/null || true

# Create pkg-config file
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"
cat > "${DEPS_PREFIX}/lib/pkgconfig/libev.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libev
Description: High-performance event loop
Version: ${VERSION}
Libs: -L\${libdir} -lev
Cflags: -I\${includedir}
EOF

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
