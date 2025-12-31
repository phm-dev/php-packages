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

### Implemented

| Extension | Packagist | Static Deps |
|-----------|-----------|-------------|
| redis | phpredis/phpredis | - |
| igbinary | igbinary/igbinary | - |
| mongodb | mongodb/mongodb-extension | zstd |
| amqp | pdezwart/php-amqp | rabbitmq-c |
| xdebug | xdebug/xdebug | - |
| swoole | swoole/swoole | openssl, libpq |
| pcov | krakjoe/pcov | - |
| apcu | apcu/apcu | - |
| imagick | imagick/imagick | imagemagick |
| ev | osmanov/pecl-ev | libev |
| opentelemetry | open-telemetry/ext-opentelemetry | - |
| memcached | php-memcached/php-memcached | libmemcached, zlib |
| rdkafka | kwn/php-rdkafka | librdkafka |
| ssh2 | ext-ssh2/ext-ssh2 | libssh2, openssl |
| mcrypt | pecl/mcrypt | libmcrypt |
| uuid | pecl/uuid | ossp-uuid |
| zstd | kjdev/php-ext-zstd | zstd |
| yaml | pecl/yaml | libyaml |
| lz4 | kjdev/php-ext-lz4 | lz4 |
| maxminddb | maxmind-db/reader | libmaxminddb |
| gmagick | pecl/gmagick | graphicsmagick |
| gearman | pecl/gearman | libgearman, libevent |
| lua | pecl/lua | lua |
| mailparse | pecl/mailparse | - |
| msgpack | msgpack/msgpack | - |
| ast | nikic/php-ast | - |
| ds | php-ds/php-ds | - |
| excimer | wikimedia/excimer | - |
| uopz | krakjoe/uopz | - |
| uploadprogress | pecl/uploadprogress | - |
| protobuf | google/protobuf | - |
| oauth | pecl/oauth | - |
| stomp | pecl/stomp | - |
| inotify | pecl/inotify | - |
| dio | pecl/dio | - |
| decimal | php-decimal/php-decimal | - |
| solr | pecl/solr | - |
| pq | pecl/pq | libpq |
| relay | cachewerk/ext-relay | special build |
| opcache | php-src | built-in for PHP 8.5+ |

### TODO (Not Yet Implemented)

These extensions require additional work:

| Extension | Blocker | Notes |
|-----------|---------|-------|
| grpc | libgrpc build | Google's gRPC library is complex, requires protobuf, abseil, etc. |
| vips | libvips build | Image processing, requires ~20 dependencies (libjpeg, libpng, etc.) |
| smbclient | libsmbclient build | Requires Samba libraries |
| rrd | librrd build | RRDtool for round-robin databases |
| radius | - | Need to verify packagist source |
| yaz | libyaz build | Z39.50 protocol, requires yaz toolkit |

### Special Cases

| Extension | Status | Notes |
|-----------|--------|-------|
| pdo_sqlsrv | Linux/Windows only | Microsoft SQL Server driver |
| sqlsrv | Linux/Windows only | Microsoft SQL Server driver |
| oci8 | Proprietary | Requires Oracle Instant Client |
| pdo_oci | Proprietary | Requires Oracle Instant Client |

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
