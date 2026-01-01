#!/usr/bin/env bash
#
# Build SQLite as static library
# https://www.sqlite.org/
# License: Public Domain
#
# Depends on: none
#
# Cache ref: v2 - ensure pkgconfig is included in artifact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="sqlite"
VERSION="3.47.2"
# SQLite uses a different version format in URLs
VERSION_CODE="3470200"
URL="https://www.sqlite.org/2024/sqlite-autoconf-${VERSION_CODE}.tar.gz"

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
    --disable-tcl \
    --enable-threadsafe \
    --enable-fts5 \
    --enable-json1 \
    CFLAGS="-O2 -fPIC -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_JSON1 -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_RTREE"

make -j"$NPROC"
make install

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libsqlite*.so* "${DEPS_PREFIX}/lib"/libsqlite*.dylib* 2>/dev/null || true

# SQLite is public domain
echo "SQLite is in the public domain" > "${DEPS_PREFIX}/licenses/${NAME}.txt"

# Mark as built
mark_built "$NAME" "$VERSION"
