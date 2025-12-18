#!/usr/bin/env bash
#
# Local testing script for php-packages builds
# Uses dockur/macos for macOS environment in Docker
#
# Prerequisites:
#   - Linux with KVM support (/dev/kvm)
#   - Docker installed
#   - 50GB+ free disk space
#   - 8GB+ RAM recommended
#
# Usage:
#   ./local-test.sh start              # Start macOS container
#   ./local-test.sh web                # Open web UI in browser
#   ./local-test.sh ssh                # SSH into macOS (after enabling SSH)
#   ./local-test.sh stop               # Stop container
#   ./local-test.sh clean              # Remove container and storage
#   ./local-test.sh status             # Show status
#
# First run setup:
#   1. ./local-test.sh start
#   2. ./local-test.sh web (or open http://localhost:8006)
#   3. Use Disk Utility to format the virtual disk
#   4. Install macOS (15-30 min)
#   5. Enable SSH: System Preferences > Sharing > Remote Login
#   6. ./local-test.sh ssh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
CONTAINER_NAME="php-packages-macos"
WEB_PORT="${WEB_PORT:-8006}"
VNC_PORT="${VNC_PORT:-5900}"
SSH_PORT="${SSH_PORT:-10022}"
MACOS_VERSION="${MACOS_VERSION:-15}"  # 11, 12, 13, 14, 15
STORAGE_VOLUME="php-packages_macos-storage"

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

# Check if running on macOS (no Docker needed!)
check_macos_host() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        log_error "You're already on macOS! No need for Docker."
        log_info ""
        log_info "Build natively instead:"
        log_info "  ./scripts/install-deps.sh"
        log_info "  ./scripts/build-php-core.sh 8.5.0"
        log_info "  ./scripts/build-all-extensions.sh 8.5.0"
        log_info ""
        exit 0
    fi
}

# Check KVM support (Linux only)
check_kvm() {
    if [[ ! -e /dev/kvm ]]; then
        log_error "KVM is not available (/dev/kvm not found)"
        log_error "Enable virtualization in BIOS or run on a Linux host with KVM support"
        exit 1
    fi
}

# Start container
cmd_start() {
    check_macos_host
    log_info "Starting macOS container..."
    check_docker
    check_kvm

    # Check if already running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Container already running"
        log_info "Web UI: http://localhost:${WEB_PORT}"
        log_info "VNC: localhost:${VNC_PORT}"
        return 0
    fi

    # Remove stopped container if exists
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log_info "Starting macOS ${MACOS_VERSION} container..."
    log_info "Web UI port: ${WEB_PORT}, VNC port: ${VNC_PORT}, SSH port: ${SSH_PORT}"

    docker run -d \
        --name "$CONTAINER_NAME" \
        --device /dev/kvm \
        --device /dev/net/tun \
        --cap-add NET_ADMIN \
        -p "${WEB_PORT}:8006" \
        -p "${VNC_PORT}:5900" \
        -p "${SSH_PORT}:22" \
        -v "${STORAGE_VOLUME}:/storage" \
        -v "${PROJECT_ROOT}:/mnt/php-packages:cached" \
        -e "VERSION=${MACOS_VERSION}" \
        -e "DISK_SIZE=64G" \
        -e "RAM_SIZE=8G" \
        -e "CPU_CORES=4" \
        --restart unless-stopped \
        --stop-timeout 120 \
        dockurr/macos

    log_success "Container started!"
    log_info ""
    log_info "============================================"
    log_info "  macOS is starting..."
    log_info "============================================"
    log_info ""
    log_info "Access:"
    log_info "  Web UI: http://localhost:${WEB_PORT}"
    log_info "  VNC:    localhost:${VNC_PORT}"
    log_info ""
    log_info "First run setup:"
    log_info "  1. Open http://localhost:${WEB_PORT}"
    log_info "  2. Use Disk Utility to format the virtual disk"
    log_info "  3. Install macOS (takes 15-30 minutes)"
    log_info "  4. After setup, enable SSH:"
    log_info "     System Preferences > Sharing > Remote Login"
    log_info ""
    log_info "Project mounted at: /mnt/php-packages"
    log_info ""
    log_info "To check progress: docker logs -f ${CONTAINER_NAME}"
}

# Open web UI
cmd_web() {
    local url="http://localhost:${WEB_PORT}"
    log_info "Opening web UI: ${url}"

    if command -v xdg-open &>/dev/null; then
        xdg-open "$url"
    elif command -v open &>/dev/null; then
        open "$url"
    else
        log_info "Open in browser: ${url}"
    fi
}

# SSH into container
cmd_ssh() {
    log_info "Connecting to macOS via SSH..."

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container not running. Start with: ./local-test.sh start"
        exit 1
    fi

    log_info "Connecting to localhost:${SSH_PORT}..."
    log_warn "Make sure SSH is enabled in macOS: System Preferences > Sharing > Remote Login"
    log_info ""

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -p "$SSH_PORT" \
        localhost
}

# Stop container
cmd_stop() {
    log_info "Stopping macOS container..."

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop -t 120 "$CONTAINER_NAME"
        log_success "Container stopped"
    else
        log_warn "Container not running"
    fi
}

# Clean up
cmd_clean() {
    log_info "Cleaning up macOS environment..."

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    log_info "Removing storage volume..."
    docker volume rm "$STORAGE_VOLUME" 2>/dev/null || true

    log_success "Cleanup complete"
    log_info ""
    log_info "Note: Docker image is still present. To remove it:"
    log_info "  docker rmi dockurr/macos"
}

# Show logs
cmd_logs() {
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container not found"
        exit 1
    fi

    docker logs -f "$CONTAINER_NAME"
}

# Show status
cmd_status() {
    log_info "macOS Container Status"
    log_info "======================"

    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_success "Container: Running"
        log_info "  Web UI: http://localhost:${WEB_PORT}"
        log_info "  VNC: localhost:${VNC_PORT}"
        log_info "  SSH: localhost:${SSH_PORT} (if enabled in macOS)"
    elif docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Container: Stopped"
        log_info "  Start with: ./local-test.sh start"
    else
        log_info "Container: Not created"
        log_info "  Create with: ./local-test.sh start"
    fi

    log_info ""
    log_info "Project: ${PROJECT_ROOT}"

    if docker volume ls -q | grep -q "^${STORAGE_VOLUME}$"; then
        log_info "Storage volume: exists"
    else
        log_info "Storage volume: not created"
    fi

    if [[ -d "${PROJECT_ROOT}/dist" ]]; then
        local count=$(ls "${PROJECT_ROOT}/dist/"*.tar.zst 2>/dev/null | wc -l || echo 0)
        log_info "Built packages: ${count}"
    fi
}

# Show help
cmd_help() {
    cat << 'EOF'
Local Testing with macOS in Docker
===================================

This script helps you test PHP builds locally using dockur/macos,
which runs macOS in a Docker container via QEMU/KVM.

Commands:
  start              Start macOS container
  web                Open web UI in browser
  ssh                SSH into macOS (after enabling SSH)
  logs               Show container logs
  stop               Stop container (graceful shutdown)
  clean              Remove container and storage volume
  status             Show current status
  help               Show this help

Environment Variables:
  WEB_PORT           Web UI port (default: 8006)
  VNC_PORT           VNC port (default: 5900)
  SSH_PORT           SSH port (default: 10022)
  MACOS_VERSION      macOS version: 11-15 (default: 15)

First Run Setup:
  1. ./local-test.sh start
  2. ./local-test.sh web (opens http://localhost:8006)
  3. In the web UI:
     - Open Disk Utility
     - Select the largest disk (VirtIO)
     - Click Erase, name it "Macintosh HD", format APFS
     - Close Disk Utility
     - Click "Reinstall macOS"
  4. Wait for installation (15-30 minutes)
  5. Complete macOS setup wizard
  6. Enable SSH:
     System Preferences > Sharing > Remote Login
  7. ./local-test.sh ssh

Building PHP:
  After SSH into macOS:

  cd /mnt/php-packages

  # Install Homebrew (if not installed)
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Install dependencies
  ./scripts/install-deps.sh

  # Build PHP
  ./scripts/build-php-core.sh 8.5.0
  ./scripts/build-all-extensions.sh 8.5.0

Requirements:
  - Linux with KVM support (/dev/kvm)
  - Docker
  - 50GB+ free disk space
  - 8GB+ RAM (16GB recommended)

Note: This does NOT work on macOS or Windows hosts.
      For macOS hosts, build natively instead.
EOF
}

# Main
main() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        start)  cmd_start "$@" ;;
        web)    cmd_web "$@" ;;
        ssh)    cmd_ssh "$@" ;;
        logs)   cmd_logs "$@" ;;
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
