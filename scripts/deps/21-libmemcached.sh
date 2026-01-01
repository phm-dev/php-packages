#!/usr/bin/env bash
#
# Build libmemcached as static library
# https://github.com/awesomized/libmemcached
# License: BSD-3-Clause
#
# Depends on: libevent
# Required by: PHP memcached extension
#
# Note: Using awesomized fork which is actively maintained
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libmemcached"
VERSION="1.1.4"
URL="https://github.com/awesomized/libmemcached/archive/refs/tags/${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
if ! is_built "libevent"; then
    log_error "libevent must be built first"
    exit 1
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

mkdir -p build
cd build

cmake .. \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_DOCS=OFF \
    -DENABLE_SASL=OFF \
    -DENABLE_DTRACE=OFF \
    -DENABLE_OPENSSL_CRYPTO=OFF \
    -DENABLE_MEMASLAP=OFF \
    -DLIBEVENT_ROOT="$DEPS_PREFIX" \
    -DCMAKE_C_FLAGS="${CFLAGS} -I${DEPS_PREFIX}/include" \
    -DCMAKE_CXX_FLAGS="${CFLAGS} -I${DEPS_PREFIX}/include" \
    -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libmemcached*.so* "${DEPS_PREFIX}/lib"/libmemcached*.dylib* 2>/dev/null || true
rm -f "${DEPS_PREFIX}/lib"/libhashkit*.so* "${DEPS_PREFIX}/lib"/libhashkit*.dylib* 2>/dev/null || true

# Create pkg-config file if not created
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"
if [[ ! -f "${DEPS_PREFIX}/lib/pkgconfig/libmemcached.pc" ]]; then
    cat > "${DEPS_PREFIX}/lib/pkgconfig/libmemcached.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libmemcached
Description: Memcached C client library
Version: ${VERSION}
Libs: -L\${libdir} -lmemcached -lmemcachedutil -lhashkit
Cflags: -I\${includedir}
EOF
fi

# Save license
save_license "$NAME" "${BUILD_DIR}/../LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
