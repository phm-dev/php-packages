#!/usr/bin/env bash
#
# Build rabbitmq-c (RabbitMQ C client) as static library
# https://github.com/alanxz/rabbitmq-c
# License: MIT
#
# Depends on: openssl
# Required by: PHP amqp extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="rabbitmq-c"
VERSION="0.14.0"
URL="https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
if ! is_built "openssl"; then
    log_error "openssl must be built first"
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

# Use cmake for building
mkdir -p build
cd build

cmake .. \
    -DCMAKE_INSTALL_PREFIX="$DEPS_PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_TOOLS=OFF \
    -DBUILD_TESTS=OFF \
    -DENABLE_SSL_SUPPORT=ON \
    -DOPENSSL_ROOT_DIR="$DEPS_PREFIX" \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DCMAKE_C_FLAGS="${CFLAGS}" \
    -DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS}"

make -j"$NPROC"
make install

# Remove any shared libs that might have been created
rm -f "${DEPS_PREFIX}/lib"/librabbitmq.so* "${DEPS_PREFIX}/lib"/librabbitmq.dylib* 2>/dev/null || true

# Create pkg-config file if not created
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"
if [[ ! -f "${DEPS_PREFIX}/lib/pkgconfig/librabbitmq.pc" ]]; then
    cat > "${DEPS_PREFIX}/lib/pkgconfig/librabbitmq.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: librabbitmq
Description: RabbitMQ C client library
Version: ${VERSION}
Requires.private: openssl
Libs: -L\${libdir} -lrabbitmq
Libs.private: -lssl -lcrypto
Cflags: -I\${includedir}
EOF
fi

# Save license
save_license "$NAME" "${BUILD_DIR}/../LICENSE"

# Mark as built
mark_built "$NAME" "$VERSION"
