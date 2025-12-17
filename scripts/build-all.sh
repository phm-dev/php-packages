#!/usr/bin/env bash
#
# Build all PHP versions with all extensions
# Usage: ./build-all.sh [--versions "8.5.0 8.4.14 8.3.15"] [--extensions "redis mongodb"] [--quiet]
#
# Compatible with Bash 3.2+ (macOS default)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_header() { echo -e "\n${BLUE}══════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}\n"; }

# Default extensions to build
DEFAULT_EXTENSIONS="redis igbinary mongodb amqp xdebug swoole ssh2 uuid mcrypt pcov apcu"

# Parse arguments
VERSIONS=""
EXTENSIONS="$DEFAULT_EXTENSIONS"
SKIP_CORE=false
SKIP_EXTENSIONS=false
QUIET=false
QUIET_FLAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --versions)
            VERSIONS="$2"
            shift 2
            ;;
        --extensions)
            EXTENSIONS="$2"
            shift 2
            ;;
        --skip-core)
            SKIP_CORE=true
            shift
            ;;
        --skip-extensions)
            SKIP_EXTENSIONS=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            QUIET_FLAG="--quiet"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Get versions if not specified
if [[ -z "$VERSIONS" ]]; then
    log_info "Fetching latest PHP versions..."
    chmod +x "${SCRIPT_DIR}/get-php-versions.sh"
    VERSIONS=$("${SCRIPT_DIR}/get-php-versions.sh" | tr '\n' ' ')
fi

if [[ -z "$VERSIONS" ]]; then
    log_error "No PHP versions found!"
    exit 1
fi

log_header "PHP Build Configuration"
echo "PHP Versions: ${VERSIONS}"
echo "Extensions:   ${EXTENSIONS}"
echo "Skip Core:    ${SKIP_CORE}"
echo "Skip Exts:    ${SKIP_EXTENSIONS}"
echo ""

# Track results using simple arrays (Bash 3.2 compatible)
RESULTS_OK=""
RESULTS_FAIL=""
FAILED=0
SUCCEEDED=0

add_result_ok() {
    RESULTS_OK="${RESULTS_OK} $1"
    SUCCEEDED=$((SUCCEEDED + 1))
}

add_result_fail() {
    RESULTS_FAIL="${RESULTS_FAIL} $1"
    FAILED=$((FAILED + 1))
}

# Build each PHP version
for VERSION in $VERSIONS; do
    PHP_MAJOR_MINOR="${VERSION%.*}"

    if [[ "$SKIP_CORE" != "true" ]]; then
        log_header "Building PHP ${VERSION} Core"

        if "${SCRIPT_DIR}/build-php-core.sh" "$VERSION" $QUIET_FLAG; then
            add_result_ok "php${PHP_MAJOR_MINOR}-core"

            # Install locally for extension building
            log_info "Installing PHP ${VERSION} locally for extension builds..."
            sudo mkdir -p "/opt/php/${PHP_MAJOR_MINOR}"

            for pkg in "${PROJECT_ROOT}/dist/php${PHP_MAJOR_MINOR}-common_"*.tar.gz \
                       "${PROJECT_ROOT}/dist/php${PHP_MAJOR_MINOR}-cli_"*.tar.gz \
                       "${PROJECT_ROOT}/dist/php${PHP_MAJOR_MINOR}-dev_"*.tar.gz \
                       "${PROJECT_ROOT}/dist/php${PHP_MAJOR_MINOR}-pear_"*.tar.gz; do
                if [[ -f "$pkg" ]]; then
                    sudo tar -xzf "$pkg" -C / --strip-components=1 files/ 2>/dev/null || true
                fi
            done

            # Verify PHP is working
            if "/opt/php/${PHP_MAJOR_MINOR}/bin/php" -v > /dev/null 2>&1; then
                log_info "PHP ${VERSION} installed successfully"
            else
                log_warn "PHP ${VERSION} installation may have issues"
            fi
        else
            add_result_fail "php${PHP_MAJOR_MINOR}-core"
            log_error "PHP ${VERSION} core build failed, skipping extensions"
            continue
        fi
    fi

    if [[ "$SKIP_EXTENSIONS" != "true" ]]; then
        # Build extensions for this PHP version
        for EXT in $EXTENSIONS; do
            log_header "Building ${EXT} for PHP ${VERSION}"

            if "${SCRIPT_DIR}/build-extension.sh" "$EXT" "$VERSION" $QUIET_FLAG; then
                add_result_ok "php${PHP_MAJOR_MINOR}-${EXT}"
            else
                add_result_fail "php${PHP_MAJOR_MINOR}-${EXT}"
                log_warn "Extension ${EXT} for PHP ${VERSION} failed"
            fi
        done
    fi
done

# Generate index
log_header "Generating Package Index"
"${SCRIPT_DIR}/generate-index.sh"

# Summary
log_header "Build Summary"

echo ""
echo "Succeeded:"
echo "----------"
for item in $RESULTS_OK; do
    echo -e "  ${GREEN}✓${NC} ${item}"
done

if [[ -n "$RESULTS_FAIL" ]]; then
    echo ""
    echo "Failed:"
    echo "-------"
    for item in $RESULTS_FAIL; do
        echo -e "  ${RED}✗${NC} ${item}"
    done
fi

echo ""
echo "----------"
echo -e "Succeeded: ${GREEN}${SUCCEEDED}${NC}"
echo -e "Failed:    ${RED}${FAILED}${NC}"
echo ""

# List packages
log_info "Built packages:"
ls -lh "${PROJECT_ROOT}/dist/"*.tar.gz 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}' || echo "  No packages"

echo ""
log_info "Index: ${PROJECT_ROOT}/dist/index.json"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
