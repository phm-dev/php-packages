# PHP Packages for PHM

This repository contains build scripts and pre-built PHP binary packages for macOS.

**These packages are designed to be used with [PHM (PHP Manager)](https://github.com/phm-dev/phm).**

## What's Here

- Build scripts for compiling PHP and extensions
- Pre-built binary packages (in GitHub Releases)
- Package index for PHM

## Packages

Built packages include:

- **PHP Core**: `php8.x-cli`, `php8.x-fpm`, `php8.x-cgi`, `php8.x-common`
- **Extensions**: `php8.x-redis`, `php8.x-xdebug`, `php8.x-mongodb`, `php8.x-amqp`, and more

## Supported Platforms

| Platform | Architecture |
|----------|--------------|
| macOS 13+ | arm64 (Apple Silicon) |
| macOS 13+ | amd64 (Intel) |

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

# Build everything
make build-all

# Or build specific version
make php VERSION=8.5.0
make extensions VERSION=8.5.0
```

## Links

- **PHM CLI**: https://github.com/phm-dev/phm
- **PHP Packages**: https://github.com/phm-dev/php-packages
