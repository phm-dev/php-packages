# PHP Packages for PHM

Precompiled PHP binary packages for macOS, built automatically on GitHub Actions.

**Designed for use with [PHM (PHP Manager)](https://github.com/phm-dev/phm).**

## How It Works

1. GitHub Actions workflows check [php.net](https://www.php.net/) and [Packagist](https://packagist.org/) daily for new releases
2. PHP and extensions are compiled on macOS runners (Apple Silicon and Intel)
3. Packages are uploaded as GitHub Release assets
4. `index.json` is regenerated and committed to this repository
5. PHM CLI downloads packages directly from GitHub Releases

No separate package server — everything is hosted on GitHub.

## Supported PHP Versions

| Version | Status |
|---------|--------|
| PHP 8.5 | Current |
| PHP 8.4 | Supported |
| PHP 8.3 | Supported |
| PHP 8.2 | Supported |
| PHP 8.1 | Supported |

## Platforms

| Platform | Architecture | Runner |
|----------|--------------|--------|
| macOS 13+ | arm64 (Apple Silicon) | `macos-latest` |
| macOS 13+ | amd64 (Intel) | `macos-15-intel` |

## Extensions

Over 40 extensions, precompiled with static dependencies:

| Extension | Static Deps | Extension | Static Deps |
|-----------|-------------|-----------|-------------|
| redis | — | imagick | imagemagick |
| xdebug | — | mongodb | zstd |
| igbinary | — | amqp | rabbitmq-c |
| pcov | — | memcached | libmemcached, zlib |
| apcu | — | rdkafka | librdkafka |
| msgpack | — | ssh2 | libssh2, openssl |
| ast | — | ev | libev |
| ds | — | mcrypt | libmcrypt |
| excimer | — | yaml | libyaml |
| protobuf | — | zstd | zstd |
| oauth | — | lz4 | lz4 |
| mailparse | — | maxminddb | libmaxminddb |
| uploadprogress | — | gmagick | graphicsmagick |
| opentelemetry | — | gearman | libgearman, libevent |
| swoole | openssl, libpq | lua | lua |
| stomp | — | relay | special build |
| dio | — | pq | libpq |
| uopz | — | uuid | ossp-uuid |
| decimal | — | solr | — |
| inotify | — | opcache | built-in (PHP 8.5+) |

Full list with PHP version availability: **[phm-dev.github.io/packages](https://phm-dev.github.io/packages/)**

## Package Format

Packages are zstd-compressed tar archives:

```
php8.5.4-redis6.3.0_darwin-arm64.tar.zst
├── pkginfo.json    # Metadata (name, version, depends)
└── files/
    └── opt/php/8.5/...
```

## Usage

```bash
# Install PHM
curl -fsSL https://raw.githubusercontent.com/phm-dev/phm/main/scripts/install-phm.sh | bash

# Install PHP with extensions
phm install php8.5-cli php8.5-fpm php8.5-redis php8.5-xdebug
```

## Missing an Extension?

[Open an issue](https://github.com/phm-dev/php-packages/issues) to request a new extension.

## Documentation

- [How Packages Are Built](https://phm-dev.github.io/how-packages-are-built/) — build pipeline details
- [Available Packages](https://phm-dev.github.io/packages/) — full package list with versions
- [PHM CLI](https://github.com/phm-dev/phm) — the package manager

## Links

- [PHM CLI](https://github.com/phm-dev/phm)
- [Documentation](https://phm-dev.github.io)
