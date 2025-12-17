# PHM - PHP Manager Build System
#
# Usage:
#   make deps                     - Install build dependencies
#   make build-all                - Build ALL versions + ALL extensions (recommended)
#   make php VERSION=8.5.0        - Build PHP core packages for specific version
#   make ext EXT=redis VERSION=8.5.0 - Build single extension
#   make all VERSION=8.5.0        - Build PHP + all extensions for one version
#   make index                    - Generate index.json
#   make clean                    - Clean dist directory
#
# Options:
#   QUIET=1                       - Hide build output (show only errors)
#

SHELL := /bin/bash
.PHONY: all deps php ext index clean help build-all versions

# Default PHP version
VERSION ?= 8.5.0

# Extension to build (for ext target)
EXT ?= redis

# Quiet mode (QUIET=1 to enable)
QUIET ?= 0
QUIET_FLAG := $(if $(filter 1,$(QUIET)),--quiet,)

# All extensions to build
EXTENSIONS := redis igbinary mongodb amqp xdebug swoole ssh2 uuid mcrypt pcov apcu

# Scripts directory
SCRIPTS := scripts

# Distribution directory
DIST := dist

help:
	@echo "PHM Build System"
	@echo ""
	@echo "Main commands:"
	@echo "  make deps                       - Install build dependencies (macOS)"
	@echo "  make build-all                  - Build ALL PHP versions + ALL extensions"
	@echo "  make versions                   - Show latest available PHP versions"
	@echo ""
	@echo "Single version commands:"
	@echo "  make php VERSION=8.5.0          - Build PHP core packages"
	@echo "  make ext EXT=redis VERSION=8.5.0 - Build single extension"
	@echo "  make extensions VERSION=8.5.0   - Build all extensions for version"
	@echo "  make all VERSION=8.5.0          - Build PHP + all extensions for version"
	@echo ""
	@echo "Utility commands:"
	@echo "  make index                      - Generate index.json"
	@echo "  make list                       - List built packages"
	@echo "  make info                       - Show package details"
	@echo "  make clean                      - Clean dist directory"
	@echo "  make install-php VERSION=8.5.0  - Install PHP locally (for testing)"
	@echo ""
	@echo "Available extensions: $(EXTENSIONS)"

# =============================================================================
# MAIN TARGETS
# =============================================================================

# Build everything - all PHP versions, all extensions
build-all:
	@chmod +x $(SCRIPTS)/*.sh
	@$(SCRIPTS)/build-all.sh $(QUIET_FLAG)

# Build with specific versions (space-separated)
# Usage: make build-all VERSIONS="8.5.0 8.4.14"
build-versions:
	@chmod +x $(SCRIPTS)/*.sh
	@$(SCRIPTS)/build-all.sh --versions "$(VERSIONS)" $(QUIET_FLAG)

# Show available PHP versions
versions:
	@chmod +x $(SCRIPTS)/get-php-versions.sh
	@echo "Latest PHP versions:"
	@$(SCRIPTS)/get-php-versions.sh | while read ver; do echo "  - $$ver"; done

# =============================================================================
# SINGLE VERSION TARGETS
# =============================================================================

deps:
	@chmod +x $(SCRIPTS)/install-deps.sh
	@$(SCRIPTS)/install-deps.sh

php:
	@chmod +x $(SCRIPTS)/build-php-core.sh $(SCRIPTS)/package.sh
	@$(SCRIPTS)/build-php-core.sh $(VERSION) $(QUIET_FLAG)

ext:
	@chmod +x $(SCRIPTS)/build-extension.sh $(SCRIPTS)/package.sh
	@$(SCRIPTS)/build-extension.sh $(EXT) $(VERSION) $(QUIET_FLAG)

extensions: $(EXTENSIONS)

$(EXTENSIONS):
	@chmod +x $(SCRIPTS)/build-extension.sh $(SCRIPTS)/package.sh
	@$(SCRIPTS)/build-extension.sh $@ $(VERSION) $(QUIET_FLAG)

all: php extensions index

# =============================================================================
# UTILITY TARGETS
# =============================================================================

index:
	@chmod +x $(SCRIPTS)/generate-index.sh
	@$(SCRIPTS)/generate-index.sh

clean:
	rm -rf $(DIST)/*.tar.zst $(DIST)/*.sha256 $(DIST)/index.json

clean-all:
	rm -rf $(DIST)
	sudo rm -rf /opt/php

# Install PHP locally (for testing extensions)
install-php:
	@PHP_MAJOR_MINOR=$${VERSION%.*}; \
	sudo mkdir -p /opt/php/$$PHP_MAJOR_MINOR; \
	for pkg in $(DIST)/php$${PHP_MAJOR_MINOR}-{common,cli,dev,pear}_*.tar.zst; do \
		if [ -f "$$pkg" ]; then \
			echo "Installing $$pkg..."; \
			zstd -dc "$$pkg" | sudo tar -xf - -C / --strip-components=1 files/; \
		fi \
	done; \
	echo "PHP installed to /opt/php/$$PHP_MAJOR_MINOR"; \
	/opt/php/$$PHP_MAJOR_MINOR/bin/php -v

# Uninstall PHP version
uninstall-php:
	@PHP_MAJOR_MINOR=$${VERSION%.*}; \
	sudo rm -rf /opt/php/$$PHP_MAJOR_MINOR; \
	echo "Removed /opt/php/$$PHP_MAJOR_MINOR"

# List built packages
list:
	@echo "Built packages:"
	@ls -lh $(DIST)/*.tar.zst 2>/dev/null | awk '{print "  " $$9 " (" $$5 ")"}' || echo "  No packages built yet"
	@echo ""
	@echo "Total: $$(ls $(DIST)/*.tar.zst 2>/dev/null | wc -l | tr -d ' ') packages"

# Show package info
info:
	@for pkg in $(DIST)/*.tar.zst; do \
		if [ -f "$$pkg" ]; then \
			echo "=== $$(basename $$pkg) ==="; \
			zstd -dc "$$pkg" 2>/dev/null | tar -xf - -O pkginfo.json 2>/dev/null | jq -r '"  Name: \(.name)\n  Version: \(.version)\n  Size: \(.installed_size) bytes\n  Depends: \(.depends | join(", "))"' 2>/dev/null || true; \
			echo ""; \
		fi \
	done

# Count packages by type
stats:
	@echo "Package Statistics:"
	@echo "==================="
	@echo ""
	@echo "By PHP version:"
	@for ver in 8.3 8.4 8.5; do \
		count=$$(ls $(DIST)/php$$ver-*.tar.zst 2>/dev/null | wc -l | tr -d ' '); \
		echo "  PHP $$ver: $$count packages"; \
	done
	@echo ""
	@echo "By type:"
	@echo "  Core packages: $$(ls $(DIST)/php*-{common,cli,fpm,cgi,dev,pear}_*.tar.zst 2>/dev/null | wc -l | tr -d ' ')"
	@echo "  Extensions:    $$(ls $(DIST)/php*-{redis,mongodb,amqp,xdebug,swoole,ssh2,uuid,mcrypt,igbinary,pcov,apcu}_*.tar.zst 2>/dev/null | wc -l | tr -d ' ')"
	@echo ""
	@echo "Total size: $$(du -sh $(DIST) 2>/dev/null | cut -f1 || echo '0')"

# =============================================================================
# RELEASE TARGETS
# =============================================================================

# Create a release archive
release:
	@mkdir -p releases
	@DATE=$$(date +%Y%m%d); \
	tar -czf releases/phm-packages-$$DATE.tar.gz -C $(DIST) .
	@echo "Release created: releases/phm-packages-$$(date +%Y%m%d).tar.gz"

# Upload to GitHub (requires gh CLI)
gh-release:
	@if ! command -v gh &> /dev/null; then \
		echo "Error: gh CLI not installed"; \
		exit 1; \
	fi
	@TAG="v$$(date +%Y%m%d%H%M)"; \
	gh release create $$TAG $(DIST)/*.tar.zst $(DIST)/index.json \
		--title "PHP Packages $$TAG" \
		--notes "Automated build"
