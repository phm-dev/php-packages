#!/usr/bin/env bash
#
# Build libpq (PostgreSQL client library) as static library
# https://www.postgresql.org/
# License: PostgreSQL License (permissive, similar to MIT/BSD)
#
# Depends on: openssl
#
# Note: Creates a combined static library that includes libpq + libpgcommon +
# libpgport + explicit_bzero stub. This is required for static linking on macOS
# because libpq depends on these internal libraries, and macOS doesn't have
# explicit_bzero function.
#
# Cache ref: v2 - ensure pkgconfig is included in artifact

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NAME="libpq"
VERSION="16.4"
URL="https://ftp.postgresql.org/pub/source/v${VERSION}/postgresql-${VERSION}.tar.gz"

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

# Build - we only need libpq, not the full PostgreSQL server
cd "$BUILD_DIR"

./configure \
    --prefix="$DEPS_PREFIX" \
    --without-readline \
    --with-openssl \
    --without-icu \
    CFLAGS="${CFLAGS} -I${DEPS_PREFIX}/include" \
    LDFLAGS="${LDFLAGS} -L${DEPS_PREFIX}/lib"

# Build only the static library (skip dylib which has refs check)
cd src/interfaces/libpq
make -j"$NPROC" libpq.a
mkdir -p "${DEPS_PREFIX}/lib" "${DEPS_PREFIX}/include"
cp libpq.a "${DEPS_PREFIX}/lib/"
cp libpq-fe.h libpq-events.h "${DEPS_PREFIX}/include/"

# Build common and port libraries (required by libpq for static linking)
cd ../../common
make -j"$NPROC"
cp libpgcommon.a "${DEPS_PREFIX}/lib/"

cd ../port
make -j"$NPROC"
cp libpgport.a "${DEPS_PREFIX}/lib/"

# Install headers
cd ../..
mkdir -p "${DEPS_PREFIX}/include/postgresql/internal"
mkdir -p "${DEPS_PREFIX}/include/libpq"
cp src/include/postgres_ext.h "${DEPS_PREFIX}/include/"
cp src/include/pg_config.h "${DEPS_PREFIX}/include/"
cp src/include/pg_config_ext.h "${DEPS_PREFIX}/include/"
cp src/include/pg_config_manual.h "${DEPS_PREFIX}/include/"

# Copy libpq-fs.h (required by PHP's pgsql/pdo_pgsql for Large Object support)
cp src/include/libpq/libpq-fs.h "${DEPS_PREFIX}/include/libpq/"

# Create explicit_bzero stub (macOS doesn't have this function)
# libpq and libpgcommon use explicit_bzero for secure memory zeroing
log_info "Creating explicit_bzero compatibility stub..."
cat > "${BUILD_DIR}/explicit_bzero.c" << 'EOFSTUB'
#include <string.h>

/*
 * explicit_bzero() - secure memory zeroing
 * This is a compatibility shim for macOS which doesn't have explicit_bzero.
 * The function securely zeros memory, preventing compiler optimizations
 * from removing the operation.
 */
void explicit_bzero(void *buf, size_t len) {
    memset(buf, 0, len);
    /* Compiler barrier to prevent optimization */
    __asm__ __volatile__("" : : "r"(buf) : "memory");
}
EOFSTUB

clang -c -O2 "${BUILD_DIR}/explicit_bzero.c" -o "${BUILD_DIR}/explicit_bzero.o"
ar rcs "${DEPS_PREFIX}/lib/libexplicit_bzero.a" "${BUILD_DIR}/explicit_bzero.o"

# Create combined static library
# This merges libpq + libpgcommon + libpgport + explicit_bzero into one library
# so that PHP's configure check for PQencryptPasswordConn succeeds without
# exposing explicit_bzero as a detectable system function
log_info "Creating combined libpq static library..."
COMBINE_DIR="${BUILD_DIR}/combine"
mkdir -p "$COMBINE_DIR"
cd "$COMBINE_DIR"

# Extract all object files
ar -x "${DEPS_PREFIX}/lib/libpq.a"
ar -x "${DEPS_PREFIX}/lib/libpgcommon.a"
ar -x "${DEPS_PREFIX}/lib/libpgport.a"
ar -x "${DEPS_PREFIX}/lib/libexplicit_bzero.a"

# Backup original libpq.a and create combined version
mv "${DEPS_PREFIX}/lib/libpq.a" "${DEPS_PREFIX}/lib/libpq_original.a"
ar rcs "${DEPS_PREFIX}/lib/libpq.a" *.o

# Remove any shared libs
rm -f "${DEPS_PREFIX}/lib"/libpq.so* "${DEPS_PREFIX}/lib"/libpq.dylib* 2>/dev/null || true

# Create pkg-config file (using combined library - no need for pgcommon/pgport)
mkdir -p "${DEPS_PREFIX}/lib/pkgconfig"
cat > "${DEPS_PREFIX}/lib/pkgconfig/libpq.pc" << EOF
prefix=${DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: libpq
Description: PostgreSQL libpq library (combined static)
Version: ${VERSION}
Requires.private: openssl
Libs: -L\${libdir} -lpq
Libs.private: -lssl -lcrypto -lz
Cflags: -I\${includedir}
EOF

# Create pg_config wrapper script
log_info "Creating pg_config wrapper..."
cat > "${DEPS_PREFIX}/bin/pg_config" << EOFPGCONFIG
#!/bin/bash
# pg_config wrapper for static libpq build

PREFIX="${DEPS_PREFIX}"

case "\$1" in
    --bindir)
        echo "\${PREFIX}/bin"
        ;;
    --docdir)
        echo "\${PREFIX}/share/doc/postgresql"
        ;;
    --htmldir)
        echo "\${PREFIX}/share/doc/postgresql"
        ;;
    --includedir)
        echo "\${PREFIX}/include"
        ;;
    --pkgincludedir)
        echo "\${PREFIX}/include/postgresql"
        ;;
    --includedir-server)
        echo "\${PREFIX}/include/postgresql/server"
        ;;
    --libdir)
        echo "\${PREFIX}/lib"
        ;;
    --pkglibdir)
        echo "\${PREFIX}/lib/postgresql"
        ;;
    --localedir)
        echo "\${PREFIX}/share/locale"
        ;;
    --mandir)
        echo "\${PREFIX}/share/man"
        ;;
    --sharedir)
        echo "\${PREFIX}/share/postgresql"
        ;;
    --sysconfdir)
        echo "\${PREFIX}/etc/postgresql"
        ;;
    --pgxs)
        echo "\${PREFIX}/lib/postgresql/pgxs/src/makefiles/pgxs.mk"
        ;;
    --configure)
        echo "--prefix=\${PREFIX} --with-openssl --without-readline --without-icu"
        ;;
    --cc)
        echo "clang"
        ;;
    --cppflags)
        echo "-I\${PREFIX}/include"
        ;;
    --cflags)
        echo "-O2 -I\${PREFIX}/include"
        ;;
    --cflags_sl)
        echo ""
        ;;
    --ldflags)
        echo "-L\${PREFIX}/lib"
        ;;
    --ldflags_ex)
        echo ""
        ;;
    --ldflags_sl)
        echo ""
        ;;
    --libs)
        echo "-lpq -lssl -lcrypto -lz"
        ;;
    --version)
        echo "PostgreSQL ${VERSION}"
        ;;
    *)
        echo "Usage: pg_config [--bindir] [--docdir] [--includedir] [--libdir] [--pkglibdir]"
        echo "                 [--includedir-server] [--libs] [--ldflags] [--cppflags]"
        echo "                 [--cflags] [--cflags_sl] [--configure] [--cc] [--version]"
        ;;
esac
EOFPGCONFIG
chmod +x "${DEPS_PREFIX}/bin/pg_config"

# Save license
save_license "$NAME" "${BUILD_DIR}/COPYRIGHT"

# Mark as built
mark_built "$NAME" "$VERSION"
