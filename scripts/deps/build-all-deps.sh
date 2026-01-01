#!/usr/bin/env bash
#
# Build all static dependencies for PHP
# Usage: ./build-all-deps.sh [--clean] [--verify]
#
# This script builds all required dependencies as static libraries
# so PHP can be linked without requiring Homebrew on target systems.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Parse arguments
# ============================================================================

CLEAN=false
VERIFY_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --clean)
            CLEAN=true
            ;;
        --verify)
            VERIFY_ONLY=true
            ;;
        --help|-h)
            echo "Usage: $0 [--clean] [--verify]"
            echo ""
            echo "Options:"
            echo "  --clean    Remove all built dependencies and rebuild"
            echo "  --verify   Only verify dependencies, don't build"
            echo ""
            exit 0
            ;;
    esac
done

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "========================================"
    echo "  PHM Static Dependencies Builder"
    echo "========================================"
    echo ""

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        verify_all_deps
        exit $?
    fi

    if [[ "$CLEAN" == "true" ]]; then
        log_warn "Cleaning all dependencies..."
        rm -rf "$DEPS_PREFIX"
        rm -rf "$DEPS_BUILD"
    fi

    # Initialize directories
    init_deps_dirs

    # Record start time
    local start_time=$SECONDS

    # Build dependencies in order (respecting dependencies between them)

    # Phase 2: Basic dependencies (no deps on other libs)
    log_info ""
    log_info "=== Phase 2: Basic dependencies ==="
    "${SCRIPT_DIR}/01-zlib.sh"
    "${SCRIPT_DIR}/02-bzip2.sh"
    "${SCRIPT_DIR}/03-libedit.sh"
    "${SCRIPT_DIR}/04-openssl.sh"

    # Phase 3: Intl/Mbstring dependencies
    log_info ""
    log_info "=== Phase 3: Intl/Mbstring dependencies ==="
    "${SCRIPT_DIR}/05-libiconv.sh"
    "${SCRIPT_DIR}/06-icu4c.sh"
    "${SCRIPT_DIR}/07-oniguruma.sh"

    # Phase 4: GD dependencies (some depend on zlib, bzip2)
    log_info ""
    log_info "=== Phase 4: GD dependencies ==="
    "${SCRIPT_DIR}/08-libpng.sh"
    "${SCRIPT_DIR}/09-jpeg-turbo.sh"
    "${SCRIPT_DIR}/10-webp.sh"
    "${SCRIPT_DIR}/11-freetype.sh"

    # Phase 5: Remaining dependencies
    log_info ""
    log_info "=== Phase 5: Remaining dependencies ==="
    "${SCRIPT_DIR}/12-libsodium.sh"
    "${SCRIPT_DIR}/13-libzip.sh"
    "${SCRIPT_DIR}/14-libpq.sh"
    "${SCRIPT_DIR}/15-libxml2.sh"
    "${SCRIPT_DIR}/16-libxslt.sh"
    "${SCRIPT_DIR}/17-curl.sh"
    "${SCRIPT_DIR}/18-sqlite.sh"

    # Phase 6: Extension dependencies (for amqp, memcached, imagick, etc.)
    log_info ""
    log_info "=== Phase 6: Extension dependencies ==="
    "${SCRIPT_DIR}/19-rabbitmq-c.sh"    # For amqp extension
    "${SCRIPT_DIR}/20-libevent.sh"      # For libmemcached, libgearman
    "${SCRIPT_DIR}/21-libmemcached.sh"  # For memcached extension
    "${SCRIPT_DIR}/22-imagemagick.sh"   # For imagick extension
    "${SCRIPT_DIR}/23-zstd.sh"          # For mongodb, redis, zstd extension
    "${SCRIPT_DIR}/24-ossp-uuid.sh"     # For uuid extension
    "${SCRIPT_DIR}/25-libyaml.sh"       # For yaml extension
    "${SCRIPT_DIR}/26-lz4.sh"           # For lz4, redis extension
    "${SCRIPT_DIR}/27-librdkafka.sh"    # For rdkafka extension
    "${SCRIPT_DIR}/28-libmaxminddb.sh"  # For maxminddb extension
    "${SCRIPT_DIR}/29-graphicsmagick.sh" # For gmagick extension
    "${SCRIPT_DIR}/30-lua.sh"           # For lua extension
    "${SCRIPT_DIR}/31-libgearman.sh"    # For gearman extension
    "${SCRIPT_DIR}/32-libev.sh"         # For ev extension
    "${SCRIPT_DIR}/33-libssh2.sh"       # For ssh2 extension
    "${SCRIPT_DIR}/34-libmcrypt.sh"     # For mcrypt extension

    # Calculate elapsed time
    local elapsed=$((SECONDS - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    echo ""
    log_info "========================================"
    log_success "All dependencies built successfully!"
    log_info "========================================"
    log_info "Time elapsed: ${minutes}m ${seconds}s"
    log_info "Install prefix: ${DEPS_PREFIX}"
    echo ""

    # Verify all libraries
    verify_all_deps

    # Show disk usage
    log_info ""
    log_info "Disk usage:"
    du -sh "${DEPS_PREFIX}/lib" "${DEPS_PREFIX}/include" 2>/dev/null || true
}

main "$@"
