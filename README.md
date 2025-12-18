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

One release per PHP version containing **everything** (core + all extensions):

- **`php-8.5.0`** - PHP 8.5.0 core packages + all extensions
- **`php-8.4.7`** - PHP 8.4.7 core packages + all extensions
- **`php-8.3.15`** - PHP 8.3.15 core packages + all extensions

Each release contains ~40 packages (5 core × 2 platforms + ~15 extensions × 2 platforms).

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

## Supported Platforms

| Platform | Architecture | Runner |
|----------|--------------|--------|
| macOS 13+ | arm64 (Apple Silicon) | macos-26 |
| macOS 13+ | amd64 (Intel) | macos-15-intel |

## Using These Packages

Install PHM and use it to install packages:

```bash
# Install PHM
curl -fsSL https://raw.githubusercontent.com/phm-dev/phm/main/scripts/install-phm.sh | bash

# Install PHP
phm update
phm install php8.5-cli php8.5-fpm php8.5-redis
```

## Build System

### Automated Builds (GitHub Actions)

Single unified workflow (`build.yml`) runs daily and:

1. **Checks for updates** - compares PHP and extension versions with `versions.json`
2. **Smart triggering**:
   - PHP version changed → build only that PHP version
   - Extension changed → build ALL PHP versions
3. **Builds PHP + all extensions** for each version
4. **Publishes to GitHub Releases** with batched uploads

### Manual Trigger

```bash
# Via GitHub CLI
gh workflow run build.yml -f php_version=8.5.0
gh workflow run build.yml -f force_build=true
```

## Building Packages Locally

### Native macOS

```bash
# Install dependencies
./scripts/install-deps.sh

# Build PHP core
./scripts/build-php-core.sh 8.5.0

# Build all extensions
./scripts/build-all-extensions.sh 8.5.0

# Or use Makefile
make deps
make php VERSION=8.5.0
```

### Docker (Linux only)

For testing on Linux using [dockur/macos](https://github.com/dockur/macos):

```bash
# Start macOS container
./scripts/local-test.sh start

# Open web UI for initial setup
./scripts/local-test.sh web  # opens http://localhost:8006

# First run: format disk, install macOS, enable SSH
# Then connect via SSH
./scripts/local-test.sh ssh

# In macOS shell:
cd /mnt/php-packages
./scripts/install-deps.sh
./scripts/build-php-core.sh 8.5.0
./scripts/build-all-extensions.sh 8.5.0

# Stop when done
./scripts/local-test.sh stop
```

Or with docker-compose:

```bash
docker-compose up -d
# Open http://localhost:8006 for web UI
# After macOS setup, enable SSH and connect:
ssh your-user@localhost -p 10022
```

**Requirements:**
- Linux with KVM support (`/dev/kvm`)
- Docker
- 50GB+ disk space, 8GB+ RAM

**Note:** Does NOT work on macOS/Windows hosts. Use native build on macOS.

## Directory Structure

```
php-packages/
├── .github/
│   └── workflows/
│       ├── build.yml              # Unified build workflow
│       └── update-index.yml       # Index regeneration
├── scripts/
│   ├── build-php-core.sh          # Build PHP from source
│   ├── build-extension.sh         # Build single extension (PIE/PECL)
│   ├── build-all-extensions.sh    # Build all extensions for PHP version
│   ├── check-updates.sh           # Check for version updates
│   ├── local-test.sh              # Docker-OSX local testing
│   ├── package.sh                 # Packaging utilities
│   ├── get-php-versions.sh        # Fetch secure PHP versions
│   ├── get-extension-version.sh   # Fetch extension version
│   ├── generate-index.sh          # Generate index.json
│   └── install-deps.sh            # Install build dependencies
├── extensions/
│   └── config.json                # Extension configuration
├── versions.json                  # Current version tracking
├── index.json                     # Package index (auto-generated)
├── docker-compose.yml             # Docker-OSX config
├── Makefile
└── README.md
```

## Version Tracking

`versions.json` tracks the last built versions:

```json
{
  "last_check": "2024-12-18T02:00:00Z",
  "php": {
    "8.3": "8.3.15",
    "8.4": "8.4.2",
    "8.5": "8.5.0"
  },
  "extensions": {
    "redis": "6.1.0",
    "xdebug": "3.4.0",
    ...
  }
}
```

When a new version is detected:
- **PHP update** → rebuilds only that PHP version with all extensions
- **Extension update** → rebuilds all PHP versions with the new extension

## Links

- **PHM CLI**: https://github.com/phm-dev/phm
- **PHP Packages**: https://github.com/phm-dev/php-packages
- **dockur/macos**: https://github.com/dockur/macos
- **PIE**: https://github.com/php/pie
