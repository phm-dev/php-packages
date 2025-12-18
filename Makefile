# PHM - PHP Manager Build System
#
# Usage:
#   make deps                          - Install build dependencies
#   make php VERSION=8.5.0             - Build PHP core packages
#   make ext EXT=redis EXT_VER=6.3.0 VERSION=8.5.0 - Build extension
#   make index                         - Generate index.json from releases
#   make clean                         - Clean dist directory
#
# Options:
#   QUIET=1                            - Hide build output (show only errors)
#

SHELL := /bin/bash
.PHONY: all deps php ext index clean help versions ext-version install-php uninstall-php list info stats

# Default versions
VERSION ?= 8.5.0
EXT ?= redis
EXT_VER ?=

# Quiet mode (QUIET=1 to enable)
QUIET ?= 0
QUIET_FLAG := $(if $(filter 1,$(QUIET)),--quiet,)

# All supported extensions
EXTENSIONS := redis igbinary mongodb amqp xdebug swoole pcov apcu decimal imagick mcrypt ev opentelemetry memcached rdkafka relay opcache

# Scripts directory
SCRIPTS := scripts

# Distribution directory
DIST := dist

help:
	@echo "PHM Build System"
	@echo ""
	@echo "Build commands:"
	@echo "  make deps                             - Install build dependencies (macOS)"
	@echo "  make php VERSION=8.5.0               - Build PHP core packages"
	@echo "  make ext EXT=redis VERSION=8.5.0     - Build extension (auto-detect version)"
	@echo "  make ext EXT=redis EXT_VER=6.3.0 VERSION=8.5.0 - Build specific version"
	@echo ""
	@echo "Version queries:"
	@echo "  make versions                        - Show latest PHP versions (from php.watch)"
	@echo "  make ext-version EXT=redis           - Show latest extension version"
	@echo ""
	@echo "Utility commands:"
	@echo "  make index                           - Generate index.json from GitHub releases"
	@echo "  make list                            - List built packages"
	@echo "  make info                            - Show package details"
	@echo "  make clean                           - Clean dist directory"
	@echo "  make install-php VERSION=8.5.0       - Install PHP locally (for testing)"
	@echo ""
	@echo "Available extensions: $(EXTENSIONS)"

# =============================================================================
# BUILD TARGETS
# =============================================================================

deps:
	@chmod +x $(SCRIPTS)/install-deps.sh
	@$(SCRIPTS)/install-deps.sh

php:
	@chmod +x $(SCRIPTS)/build-php-core.sh $(SCRIPTS)/package.sh
	@$(SCRIPTS)/build-php-core.sh $(VERSION) $(QUIET_FLAG)

# Build extension - auto-detect version if not specified
ext:
	@chmod +x $(SCRIPTS)/build-extension.sh $(SCRIPTS)/package.sh $(SCRIPTS)/get-extension-version.sh
	@if [ -z "$(EXT_VER)" ]; then \
		EXT_VERSION=$$($(SCRIPTS)/get-extension-version.sh $$(jq -r '.extensions["$(EXT)"].packagist' extensions/config.json)); \
		$(SCRIPTS)/build-extension.sh $(EXT) $$EXT_VERSION $(VERSION) $(QUIET_FLAG); \
	else \
		$(SCRIPTS)/build-extension.sh $(EXT) $(EXT_VER) $(VERSION) $(QUIET_FLAG); \
	fi

# =============================================================================
# VERSION QUERIES
# =============================================================================

versions:
	@chmod +x $(SCRIPTS)/get-php-versions.sh
	@echo "Latest secure PHP versions:"
	@$(SCRIPTS)/get-php-versions.sh | while read ver; do echo "  - $$ver"; done

ext-version:
	@chmod +x $(SCRIPTS)/get-extension-version.sh
	@PACKAGIST=$$(jq -r '.extensions["$(EXT)"].packagist // empty' extensions/config.json); \
	if [ -z "$$PACKAGIST" ]; then \
		echo "Error: Extension '$(EXT)' not found in extensions/config.json"; \
		exit 1; \
	fi; \
	VERSION=$$($(SCRIPTS)/get-extension-version.sh $$PACKAGIST); \
	echo "$(EXT): $$VERSION (from $$PACKAGIST)"

# =============================================================================
# INDEX GENERATION
# =============================================================================

index:
	@chmod +x $(SCRIPTS)/generate-index.sh
	@$(SCRIPTS)/generate-index.sh

# =============================================================================
# LOCAL INSTALLATION (for testing)
# =============================================================================

# Install PHP locally from dist/ packages
install-php:
	@PHP_MAJOR_MINOR=$${VERSION%.*}; \
	sudo mkdir -p /opt/php/$$PHP_MAJOR_MINOR; \
	for pkg in $(DIST)/php$(VERSION)-{common,cli,dev,pear}_*.tar.zst; do \
		if [ -f "$$pkg" ]; then \
			echo "Installing $$pkg..."; \
			zstd -dc "$$pkg" | sudo tar -xf - -C / --strip-components=1 files/; \
		fi \
	done; \
	echo "PHP installed to /opt/php/$$PHP_MAJOR_MINOR"; \
	/opt/php/$$PHP_MAJOR_MINOR/bin/php -v

uninstall-php:
	@PHP_MAJOR_MINOR=$${VERSION%.*}; \
	sudo rm -rf /opt/php/$$PHP_MAJOR_MINOR; \
	echo "Removed /opt/php/$$PHP_MAJOR_MINOR"

# =============================================================================
# UTILITY TARGETS
# =============================================================================

clean:
	rm -rf $(DIST)/*.tar.zst $(DIST)/*.sha256

clean-all:
	rm -rf $(DIST)
	sudo rm -rf /opt/php

list:
	@echo "Built packages:"
	@ls -lh $(DIST)/*.tar.zst 2>/dev/null | awk '{print "  " $$9 " (" $$5 ")"}' || echo "  No packages built yet"
	@echo ""
	@echo "Total: $$(ls $(DIST)/*.tar.zst 2>/dev/null | wc -l | tr -d ' ') packages"

info:
	@for pkg in $(DIST)/*.tar.zst; do \
		if [ -f "$$pkg" ]; then \
			echo "=== $$(basename $$pkg) ==="; \
			zstd -dc "$$pkg" 2>/dev/null | tar -xf - -O pkginfo.json 2>/dev/null | jq -r '"  Name: \(.name)\n  Version: \(.version)\n  Size: \(.installed_size) bytes\n  Depends: \(.depends | join(", "))"' 2>/dev/null || true; \
			echo ""; \
		fi \
	done

stats:
	@echo "Package Statistics:"
	@echo "==================="
	@echo ""
	@echo "By PHP version:"
	@for ver in 8.1 8.2 8.3 8.4 8.5; do \
		count=$$(ls $(DIST)/php$$ver.*-*.tar.zst 2>/dev/null | wc -l | tr -d ' '); \
		if [ "$$count" -gt 0 ]; then \
			echo "  PHP $$ver: $$count packages"; \
		fi \
	done
	@echo ""
	@echo "By type:"
	@core_count=$$(ls $(DIST)/php*-{common,cli,fpm,cgi,dev,pear}_*.tar.zst 2>/dev/null | wc -l | tr -d ' '); \
	ext_count=$$(ls $(DIST)/php*-*[0-9]_*.tar.zst 2>/dev/null | wc -l | tr -d ' '); \
	echo "  Core packages: $$core_count"; \
	echo "  Extensions:    $$ext_count"
	@echo ""
	@echo "Total size: $$(du -sh $(DIST) 2>/dev/null | cut -f1 || echo '0')"

# =============================================================================
# CI/CD HELPERS
# =============================================================================

# Used by GitHub Actions to determine what to build
.PHONY: ci-php-versions ci-ext-version

ci-php-versions:
	@chmod +x $(SCRIPTS)/get-php-versions.sh
	@$(SCRIPTS)/get-php-versions.sh --json

ci-ext-version:
	@chmod +x $(SCRIPTS)/get-extension-version.sh
	@PACKAGIST=$$(jq -r '.extensions["$(EXT)"].packagist' extensions/config.json); \
	$(SCRIPTS)/get-extension-version.sh $$PACKAGIST
