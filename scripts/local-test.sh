#!/usr/bin/env bash
#
# Local testing script for php-packages builds
# Uses Docker-OSX for macOS environment simulation
#
# Prerequisites:
#   - Docker with KVM support (Linux) or Docker Desktop (macOS)
#   - At least 50GB free disk space
#   - 8GB+ RAM recommended
#
# Usage:
#   ./local-test.sh setup              # First-time setup (downloads macOS image)
#   ./local-test.sh start              # Start Docker-OSX container
#   ./local-test.sh ssh                # SSH into running container
#   ./local-test.sh build <php_ver>    # Build PHP + extensions in container
#   ./local-test.sh stop               # Stop container
#   ./local-test.sh clean              # Remove container and volumes
#
# Examples:
#   ./local-test.sh setup
#   ./local-test.sh start
#   ./local-test.sh build 8.5.0
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
CONTAINER_NAME="php-packages-macos"
SSH_PORT="${SSH_PORT:-10022}"
VNC_PORT="${VNC_PORT:-5999}"
MACOS_VERSION="${MACOS_VERSION:-ventura}"  # sonoma, ventura, monterey
SSH_USER="user"
SSH_PASS="alpine"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Check if Docker is available
check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
}

# Check KVM support (Linux only)
check_kvm() {
    if [[ "$(uname -s)" == "Linux" ]]; then
        if [[ ! -e /dev/kvm ]]; then
            log_error "KVM is not available. Enable virtualization in BIOS."
            exit 1
        fi
    fi
}

# Setup - pull Docker-OSX image
cmd_setup() {
    log_info "Setting up Docker-OSX environment..."
    check_docker

    log_info "Pulling Docker-OSX image (sickcodes/docker-osx:${MACOS_VERSION})..."
    log_warn "This may take a while (image is ~15-20GB)"

    docker pull "sickcodes/docker-osx:${MACOS_VERSION}"

    log_success "Setup complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Run: ./local-test.sh start"
    log_info "  2. Wait for macOS to boot (5-10 minutes first time)"
    log_info "  3. Run: ./local-test.sh ssh"
    log_info "  4. In macOS: ./local-test.sh build 8.5.0"
}

# Start Docker-OSX container
cmd_start() {
    log_info "Starting Docker-OSX container..."
    check_docker

    # Check if already running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Container already running"
        log_info "SSH: ssh ${SSH_USER}@localhost -p ${SSH_PORT}"
        return 0
    fi

    # Remove stopped container if exists
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # Determine device options based on OS
    local device_opts=""
    if [[ "$(uname -s)" == "Linux" ]]; then
        check_kvm
        device_opts="--device /dev/kvm"
    fi

    log_info "Starting macOS ${MACOS_VERSION} container..."
    log_info "SSH port: ${SSH_PORT}, VNC port: ${VNC_PORT}"

    docker run -d \
        --name "$CONTAINER_NAME" \
        $device_opts \
        -p "${SSH_PORT}:10022" \
        -p "${VNC_PORT}:5999" \
        -v "${PROJECT_ROOT}:/mnt/php-packages:delegated" \
        -e "DISPLAY=${DISPLAY:-:0}" \
        -e "GENERATE_UNIQUE=true" \
        -e "CPU=Haswell-noTSX" \
        -e "CPUID_FLAGS=kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on" \
        -e "MASTER_PLIST_URL=https://raw.githubusercontent.com/sickcodes/osx-serial-generator/master/config-custom.plist" \
        "sickcodes/docker-osx:${MACOS_VERSION}"

    log_success "Container started!"
    log_info ""
    log_info "macOS is booting... This takes 5-10 minutes on first run."
    log_info ""
    log_info "Connect via:"
    log_info "  SSH: ssh ${SSH_USER}@localhost -p ${SSH_PORT}"
    log_info "       Password: ${SSH_PASS}"
    log_info "  VNC: localhost:${VNC_PORT}"
    log_info ""
    log_info "Project mounted at: /mnt/php-packages"
    log_info ""
    log_info "To check boot progress: docker logs -f ${CONTAINER_NAME}"
}

# SSH into container
cmd_ssh() {
    log_info "Connecting to macOS via SSH..."

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container not running. Start with: ./local-test.sh start"
        exit 1
    fi

    # Try to connect
    log_info "Connecting to ${SSH_USER}@localhost:${SSH_PORT}..."
    log_info "Password: ${SSH_PASS}"

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        "${SSH_USER}@localhost"
}

# Build PHP in container
cmd_build() {
    local php_version="${1:-}"

    if [[ -z "$php_version" ]]; then
        log_error "Usage: ./local-test.sh build <php_version>"
        log_info "Example: ./local-test.sh build 8.5.0"
        exit 1
    fi

    log_info "Building PHP ${php_version} in Docker-OSX..."

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container not running. Start with: ./local-test.sh start"
        exit 1
    fi

    # Execute build commands via SSH
    log_info "Executing build via SSH..."

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        "${SSH_USER}@localhost" << EOF
cd /mnt/php-packages

# Install Homebrew if not present
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "\$(/opt/homebrew/bin/brew shellenv)" || eval "\$(/usr/local/bin/brew shellenv)"
fi

# Install dependencies
echo "Installing build dependencies..."
brew install -q autoconf automake bison re2c pkg-config libtool cmake \\
    openssl@3 libzip icu4c readline libxml2 libxslt \\
    sqlite lz4 zstd oniguruma jpeg-turbo libpng freetype webp \\
    libpq bzip2 curl libiconv jq \\
    rabbitmq-c libmemcached imagemagick libmcrypt libev librdkafka mpdecimal

# Make scripts executable
chmod +x scripts/*.sh

# Build PHP
echo "Building PHP ${php_version}..."
./scripts/build-php-core.sh ${php_version}

# Build extensions
echo "Building extensions..."
./scripts/build-all-extensions.sh ${php_version} --continue-on-error

# List results
echo ""
echo "Build complete! Packages:"
ls -la dist/*.tar.zst 2>/dev/null || echo "No packages found"
EOF

    log_success "Build complete!"
    log_info "Packages are in: ${PROJECT_ROOT}/dist/"
}

# Copy files from container
cmd_copy() {
    log_info "Copying built packages from container..."

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container not running"
        exit 1
    fi

    # Files are already available via volume mount
    log_info "Packages are available at: ${PROJECT_ROOT}/dist/"
    ls -la "${PROJECT_ROOT}/dist/"*.tar.zst 2>/dev/null || log_warn "No packages found"
}

# Stop container
cmd_stop() {
    log_info "Stopping Docker-OSX container..."

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop "$CONTAINER_NAME"
        log_success "Container stopped"
    else
        log_warn "Container not running"
    fi
}

# Clean up
cmd_clean() {
    log_info "Cleaning up Docker-OSX environment..."

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log_success "Cleanup complete"
    log_info ""
    log_info "Note: Docker image is still present. To remove it:"
    log_info "  docker rmi sickcodes/docker-osx:${MACOS_VERSION}"
}

# Show status
cmd_status() {
    log_info "Docker-OSX Status"
    log_info "================="

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_success "Container: Running"
        log_info "  SSH: ssh ${SSH_USER}@localhost -p ${SSH_PORT}"
        log_info "  VNC: localhost:${VNC_PORT}"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Container: Stopped"
    else
        log_info "Container: Not created"
    fi

    log_info ""
    log_info "Project: ${PROJECT_ROOT}"

    if [[ -d "${PROJECT_ROOT}/dist" ]]; then
        local count=$(ls "${PROJECT_ROOT}/dist/"*.tar.zst 2>/dev/null | wc -l)
        log_info "Built packages: ${count}"
    fi
}

# Show help
cmd_help() {
    cat << 'EOF'
Local Testing with Docker-OSX
=============================

This script helps you test PHP builds locally using Docker-OSX,
which runs macOS in a Docker container.

Commands:
  setup              Download Docker-OSX image (~15-20GB)
  start              Start macOS container
  ssh                SSH into running container
  build <version>    Build PHP + extensions (e.g., build 8.5.0)
  copy               Show location of built packages
  stop               Stop container
  clean              Remove container
  status             Show current status
  help               Show this help

Environment Variables:
  SSH_PORT           SSH port (default: 10022)
  VNC_PORT           VNC port (default: 5999)
  MACOS_VERSION      macOS version: sonoma, ventura, monterey (default: ventura)

Examples:
  # First-time setup
  ./local-test.sh setup
  ./local-test.sh start

  # Wait for macOS to boot, then:
  ./local-test.sh build 8.5.0

  # Or manually:
  ./local-test.sh ssh
  # In macOS shell:
  cd /mnt/php-packages
  ./scripts/build-php-core.sh 8.5.0
  ./scripts/build-all-extensions.sh 8.5.0

Requirements:
  - Docker with KVM support (Linux) or Docker Desktop (macOS)
  - 50GB+ free disk space
  - 8GB+ RAM

Note: First boot takes 5-10 minutes. Subsequent boots are faster.
EOF
}

# Main
main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        setup)  cmd_setup "$@" ;;
        start)  cmd_start "$@" ;;
        ssh)    cmd_ssh "$@" ;;
        build)  cmd_build "$@" ;;
        copy)   cmd_copy "$@" ;;
        stop)   cmd_stop "$@" ;;
        clean)  cmd_clean "$@" ;;
        status) cmd_status "$@" ;;
        help|--help|-h) cmd_help ;;
        *)
            log_error "Unknown command: $cmd"
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
