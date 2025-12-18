# PHP Packages for PHM

Pre-built PHP binary packages for macOS.

**Designed for use with [PHM (PHP Manager)](https://github.com/phm-dev/phm).**

## Package Naming

**PHP Core:**
```
php{VERSION}-{type}_{platform}.tar.zst
```
- `php8.5.0-cli_darwin-arm64.tar.zst`
- `php8.4.7-fpm_darwin-amd64.tar.zst`

**Extensions:**
```
php{VERSION}-{ext}{extver}_{platform}.tar.zst
```
- `php8.5.0-redis6.3.0_darwin-arm64.tar.zst`
- `php8.4.7-xdebug3.4.0_darwin-amd64.tar.zst`

## GitHub Releases

One release per PHP version containing core + all extensions:

- `php-8.5.0` → ~40 packages (core + extensions for both platforms)
- `php-8.4.7`
- `php-8.3.15`

## Extensions

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

## Platforms

| Platform | Architecture | Runner |
|----------|--------------|--------|
| macOS 13+ | arm64 (Apple Silicon) | macos-26 |
| macOS 13+ | amd64 (Intel) | macos-15-intel |

## Usage

```bash
# Install PHM
curl -fsSL https://raw.githubusercontent.com/phm-dev/phm/main/scripts/install-phm.sh | bash

# Install PHP
phm update
phm install php8.5-cli php8.5-fpm php8.5-redis
```

## Build System

### Automated (GitHub Actions)

Single workflow (`build.yml`) runs daily:

1. Checks for PHP/extension updates vs `versions.json`
2. Smart triggering:
   - PHP changed → build only that version
   - Extension changed → build ALL PHP versions
3. Builds PHP + all extensions
4. Publishes to GitHub Releases

### Manual Trigger

```bash
gh workflow run build.yml -f php_version=8.5.0
gh workflow run build.yml -f force_build=true
```

## Version Tracking

`versions.json` tracks last built versions:

```json
{
  "php": { "8.3": "8.3.15", "8.4": "8.4.2", "8.5": "8.5.0" },
  "extensions": { "redis": "6.1.0", "xdebug": "3.4.0", ... }
}
```

## Links

- [PHM CLI](https://github.com/phm-dev/phm)
- [PIE](https://github.com/php/pie)
