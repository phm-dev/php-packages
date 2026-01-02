#!/usr/bin/env bash
#
# Build bzip2 as static library
# https://sourceware.org/bzip2/
# License: BSD-style
#

# Cache ref: v2 - ensure pkgconfig is included in artifact
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="bzip2"
VERSION="1.0.8"
# Mirror - sourceware.org is often unreliable
URL="https://gitlab.com/bzip2/bzip2/-/archive/bzip2-${VERSION}/bzip2-bzip2-${VERSION}.tar.gz"

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

# bzip2 doesn't use autoconf, just a Makefile
# We need to modify it for our prefix and static build
make -j"$NPROC" \
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    libbz2.a bzip2 bzip2recover

# Manual install
mkdir -p "${DEPS_PREFIX}/lib" "${DEPS_PREFIX}/include" "${DEPS_PREFIX}/bin"
cp libbz2.a "${DEPS_PREFIX}/lib/"
cp bzlib.h "${DEPS_PREFIX}/include/"
cp bzip2 bzip2recover "${DEPS_PREFIX}/bin/"

# Create pkgconfig file
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"
cat > "${DEPS_PREFIX}/lib/pkgconfig/bzip2.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: bzip2
Description: A file compression library
Version: ${VERSION}
Libs: -L\${libdir} -lbz2
Cflags: -I\${includedir}
EOF

# Save license
save_license "$NAME" "LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
