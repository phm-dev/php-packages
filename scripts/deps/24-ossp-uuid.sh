#!/usr/bin/env bash
#
# Build OSSP UUID as static library
# http://www.ossp.org/pkg/lib/uuid/
# License: MIT
#
# Required by: PHP uuid extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="ossp-uuid"
VERSION="1.6.2"
# OSSP site is often down, use Debian mirror
URL="http://deb.debian.org/debian/pool/main/o/ossp-uuid/ossp-uuid_${VERSION}.orig.tar.gz"

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

# Fix for modern compilers - add missing includes
sed -i.bak 's/#include "config.h"/#include "config.h"\n#include <string.h>/' uuid.c 2>/dev/null || true

./configure \
    --prefix="$DEPS_PREFIX" \
    --enable-static \
    --disable-shared \
    --without-perl \
    --without-php \
    --without-pgsql \
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libuuid.so* "${DEPS_PREFIX}/lib"/libuuid.dylib* 2>/dev/null || true

# Create pkg-config file if not created
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"
if [[ ! -f "${DEPS_PREFIX}/lib/pkgconfig/ossp-uuid.pc" ]]; then
    cat > "${DEPS_PREFIX}/lib/pkgconfig/ossp-uuid.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: ossp-uuid
Description: OSSP UUID library
Version: ${VERSION}
Libs: -L\${libdir} -luuid
Cflags: -I\${includedir}
EOF
fi

# Save license
save_license "$NAME" "README"

# Mark as built
mark_built "$NAME" "$VERSION"
