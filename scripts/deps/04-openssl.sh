#!/usr/bin/env bash
#
# Build OpenSSL as static library
# https://www.openssl.org/
# License: Apache 2.0
#
# Cache ref: v2 - ensure pkgconfig is included in artifact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="openssl"
VERSION="3.2.3"
URL="https://www.openssl.org/source/openssl-${VERSION}.tar.gz"

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

# Determine OpenSSL target based on platform
OPENSSL_TARGET=""
case "$PLATFORM" in
    darwin-arm64)
        OPENSSL_TARGET="darwin64-arm64-cc"
        ;;
    darwin-amd64)
        OPENSSL_TARGET="darwin64-x86_64-cc"
        ;;
    linux-arm64)
        OPENSSL_TARGET="linux-aarch64"
        ;;
    linux-amd64)
        OPENSSL_TARGET="linux-x86_64"
        ;;
    *)
        log_error "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

./Configure \
    "$OPENSSL_TARGET" \
    --prefix="$DEPS_PREFIX" \
    --openssldir="${DEPS_PREFIX}/ssl" \
    no-shared \
    no-tests \
    -fPIC

make -j"$NPROC"
make install_sw  # install_sw skips documentation

# Remove any shared libs just in case
rm -f "${DEPS_PREFIX}/lib"/libssl.so* "${DEPS_PREFIX}/lib"/libcrypto.so* 2>/dev/null || true
rm -f "${DEPS_PREFIX}/lib"/libssl.dylib* "${DEPS_PREFIX}/lib"/libcrypto.dylib* 2>/dev/null || true
# Also remove .lic files on macOS
rm -f "${DEPS_PREFIX}/lib"/*.dylib 2>/dev/null || true

# Save license
save_license "$NAME" "LICENSE.txt"

# Mark as built
mark_built "$NAME" "$VERSION"
