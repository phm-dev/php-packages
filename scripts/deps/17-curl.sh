#!/usr/bin/env bash
#
# Build libcurl as static library
# https://curl.se/
# License: curl license (MIT/X derivate)
#
# Depends on: openssl, zlib
#
# Cache ref: v2 - ensure pkgconfig is included in artifact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="curl"
VERSION="8.10.1"
URL="https://curl.se/download/curl-${VERSION}.tar.gz"

if is_built "$NAME"; then
    log_info "$NAME already built, skipping"
    exit 0
fi

# Check dependencies
for dep in openssl zlib; do
    if ! is_built "$dep"; then
        log_error "$dep must be built first"
        exit 1
    fi
done

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
    --with-openssl="${DEPS_PREFIX}" \
    --with-zlib="${DEPS_PREFIX}" \
    --without-libpsl \
    --without-brotli \
    --without-zstd \
    --without-libidn2 \
    --without-nghttp2 \
    --without-librtmp \
    --without-libssh2 \
    --disable-ldap \
    --disable-ldaps \
    --disable-rtsp \
    --disable-dict \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-imap \
    --disable-smb \
    --disable-smtp \
    --disable-gopher \
    --disable-mqtt \
    --disable-manual

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libcurl.so* "${DEPS_PREFIX}/lib"/libcurl.dylib* 2>/dev/null || true

# Fix pkg-config to include macOS frameworks (required for static linking)
# curl depends on CoreFoundation, CoreServices, and SystemConfiguration frameworks
if [[ "$(uname -s)" == "Darwin" ]]; then
    log_info "Fixing libcurl.pc for macOS frameworks..."
    sed -i '' 's|^Libs:.*|Libs: -L${libdir} -lcurl -lssl -lcrypto -lz -framework CoreFoundation -framework CoreServices -framework SystemConfiguration|' \
        "${DEPS_PREFIX}/lib/pkgconfig/libcurl.pc"
    sed -i '' 's|^Libs.private:.*|Libs.private: -lssl -lcrypto -lz -framework CoreFoundation -framework CoreServices -framework SystemConfiguration|' \
        "${DEPS_PREFIX}/lib/pkgconfig/libcurl.pc"
fi

# Save license
save_license "$NAME" "COPYING"

# Mark as built
mark_built "$NAME" "$VERSION"
