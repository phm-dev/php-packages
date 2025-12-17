#!/usr/bin/env bash
#
# Install build dependencies for PHP compilation on macOS
#

set -euo pipefail

log_info() { echo "[INFO] $*"; }
log_error() { echo "[ERROR] $*" >&2; }

# Check if running on macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "This script is for macOS only"
    exit 1
fi

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    log_error "Homebrew is required. Install it from https://brew.sh"
    exit 1
fi

log_info "Installing PHP build dependencies..."

# Core build tools
brew install \
    autoconf \
    automake \
    bison \
    cmake \
    re2c \
    pkg-config \
    libtool

# Libraries required by PHP
brew install \
    openssl@3 \
    libzip \
    icu4c \
    readline \
    libxml2 \
    libxslt \
    sqlite \
    lz4 \
    zstd \
    oniguruma \
    bzip2 \
    curl \
    libiconv

# GD dependencies
brew install \
    jpeg-turbo \
    libpng \
    freetype \
    webp

# Database client libraries
brew install \
    libpq

# Extension dependencies
brew install \
    rabbitmq-c \
    libssh2 \
    imagemagick

log_info "All dependencies installed!"
log_info ""
log_info "You may need to add these to your shell profile:"
log_info '  export PATH="$(brew --prefix bison)/bin:$PATH"'
