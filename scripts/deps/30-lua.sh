#!/usr/bin/env bash
#
# Build Lua as static library
# https://www.lua.org/
# License: MIT
#
# Required by: PHP lua extension
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="lua"
VERSION="5.4.7"
URL="https://www.lua.org/ftp/lua-${VERSION}.tar.gz"

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

# Build - Lua uses simple Makefile
cd "$BUILD_DIR"

make -j"$NPROC" \
    PLAT=macosx \
    CC="${CC}" \
    MYCFLAGS="${CFLAGS}" \
    MYLDFLAGS="${LDFLAGS}"

make install INSTALL_TOP="$DEPS_PREFIX"

# Create pkg-config file
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"
cat > "${DEPS_PREFIX}/lib/pkgconfig/lua.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Lua
Description: Lua scripting language
Version: ${VERSION}
Libs: -L\${libdir} -llua -lm
Cflags: -I\${includedir}
EOF

# Save license
save_license "$NAME" "doc/readme.html"

# Mark as built
mark_built "$NAME" "$VERSION"
