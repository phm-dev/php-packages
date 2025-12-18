# PHP Packages for PHM

This repository contains build scripts and pre-built PHP binary packages for macOS.

**These packages are designed to be used with [PHM (PHP Manager)](https://github.com/phm-dev/phm).**

## What's Here

- Build scripts for compiling PHP and extensions
- Pre-built binary packages (in GitHub Releases)
- Package index for PHM (`index.json`)

## Package Naming Convention

### PHP Core Packages
```
php{VERSION}-{type}_{platform}.tar.zst
```
Examples:
- `php8.5.0-cli_darwin-arm64.tar.zst`
- `php8.4.7-fpm_darwin-amd64.tar.zst`

### Extension Packages
```
php{VERSION}-{ext}{extver}_{platform}.tar.zst
```
Examples:
- `php8.5.0-redis6.3.0_darwin-arm64.tar.zst`
- `php8.4.7-xdebug3.4.0_darwin-amd64.tar.zst`

## GitHub Releases

Packages are organized into separate releases:

- **PHP Releases**: `php-8.5.0`, `php-8.4.7`, etc.
  - Contains core packages: common, cli, fpm, cgi, dev, pear
- **Extension Releases**: `redis-6.3.0`, `xdebug-3.4.0`, etc.
  - Contains extension packages for all supported PHP versions

## Available Extensions

| Extension | Packagist |
|-----------|-----------|
| redis | phpredis/phpredis |
| igbinary | igbinary/igbinary |
| mongodb | mongodb/mongodb-extension |
| amqp | pdezwart/php-amqp |
| xdebug | xdebug/xdebug |
| swoole | swoole/swoole |
| pcov | pecl/pcov |
| apcu | apcu/apcu |
| decimal | php-decimal/ext-decimal |
| imagick | imagick/imagick |
| mcrypt | pecl/mcrypt |
| ev | osmanov/pecl-ev |
| opentelemetry | open-telemetry/ext-opentelemetry |
| memcached | php-memcached/php-memcached |
| rdkafka | rdkafka/rdkafka |
| relay | cachewerk/ext-relay |
| opcache | (built-in for PHP < 8.5) |

## Supported Platforms

| Platform | Architecture | Runner |
|----------|--------------|--------|
| macOS 13+ | arm64 (Apple Silicon) | macos-15 |
| macOS 13+ | amd64 (Intel) | macos-13 |

## Using These Packages

Install PHM and use it to install packages:

```bash
# Install PHM
curl -fsSL https://raw.githubusercontent.com/phm-dev/phm/main/scripts/install-phm.sh | bash

# Install PHP
phm update
phm install php8.5-cli php8.5-fpm php8.5-redis
```

## Building Packages Locally

```bash
# Install dependencies
make deps

# Build PHP core packages
make php VERSION=8.5.0

# Build extension (auto-detect version)
make ext EXT=redis VERSION=8.5.0

# Build extension with specific version
make ext EXT=redis EXT_VER=6.3.0 VERSION=8.5.0

# Check available PHP versions
make versions

# Check extension version
make ext-version EXT=redis
```

## GitHub Actions Workflows

### build-php.yml
- Runs daily at 2:00 UTC
- Builds new PHP versions when released
- Triggers extension builds via `repository_dispatch`

### build-{extension}.yml
- One workflow per extension
- Runs daily at 4:00 UTC
- Triggered by `repository_dispatch` when new PHP is built
- Uses PIE (PHP Installer for Extensions) with PECL fallback

### update-index.yml
- Triggered after any build workflow completes
- Regenerates `index.json` from all releases
- Commits and pushes to main branch

## Directory Structure

```
php-packages/
├── .github/
│   └── workflows/
│       ├── build-php.yml           # PHP core builds
│       ├── build-redis.yml         # Extension workflows
│       ├── build-xdebug.yml
│       ├── ...
│       └── update-index.yml        # Index regeneration
├── scripts/
│   ├── build-php-core.sh           # Build PHP from source
│   ├── build-extension.sh          # Build extension (PIE/PECL)
│   ├── package.sh                  # Packaging utilities
│   ├── get-php-versions.sh         # Fetch secure PHP versions
│   ├── get-extension-version.sh    # Fetch extension version from Packagist
│   ├── generate-index.sh           # Generate index.json from releases
│   ├── install-pie.sh              # Install PIE tool
│   └── install-deps.sh             # Install build dependencies
├── extensions/
│   └── config.json                 # Extension configuration
├── index.json                      # Package index (auto-generated)
├── Makefile
└── README.md
```

## Links

- **PHM CLI**: https://github.com/phm-dev/phm
- **PHP Packages**: https://github.com/phm-dev/php-packages
- **PIE**: https://github.com/php/pie
