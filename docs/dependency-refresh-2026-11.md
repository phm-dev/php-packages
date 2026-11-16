# Dependency refresh — 2026-11-16

One-time refresh of the pinned native dependencies. Versions remain explicit in
`scripts/deps/`; no automatic updater or dependency resolver is introduced.

OpenSSL uses the maintained 3.5 LTS branch. Other changed libraries use stable
upstream releases; libraries with no newer release retain their existing pins.

| Library | Previous | Updated |
| --- | --- | --- |
| zlib | 1.3.2 | 1.4 |
| bzip2 | 1.0.8 | 1.0.8 |
| libedit | 20240517-3.1 | 20260512-3.1 |
| openssl | 3.2.3 | 3.5.9 |
| libiconv | 1.17 | 1.19.1 |
| icu4c | 74-2 | 79.1 |
| oniguruma | 6.9.9 | 6.9.10 |
| libpng | 1.6.43 | 1.6.59 |
| jpeg-turbo | 3.0.4 | 3.2.1 |
| webp | 1.4.0 | 1.6.0 |
| freetype | 2.13.3 | 2.15.0 |
| libsodium | 1.0.20 | 1.0.22 |
| libzip | 1.10.1 | 1.12.1 |
| libpq | 16.4 | 18.7 |
| libxml2 | 2.12.9 | 2.15.4 |
| libxslt | 1.1.42 | 1.1.45 |
| curl | 8.10.1 | 8.23.0 |
| sqlite | 3.47.2 | 3.54.1 |
| rabbitmq-c | 0.14.0 | 0.18.1 |
| libevent | 2.1.12 | 2.1.13 |
| libmemcached | 1.1.4 | 1.1.4 |
| imagemagick | 7.1.1-41 | 7.1.2-35 |
| zstd | 1.5.6 | 1.5.7 |
| ossp-uuid | 1.6.2 | 1.6.2 |
| libyaml | 0.2.5 | 0.2.5 |
| lz4 | 1.10.0 | 1.11.1 |
| librdkafka | 2.6.1 | 2.16.0 |
| libmaxminddb | 1.11.0 | 1.14.1 |
| graphicsmagick | 1.3.45 | 1.3.49 |
| lua | 5.4.7 | 5.5.1 |
| libgearman | 1.1.21 | 2.2.0 |
| libev | 4.33 | 4.33 |
| libssh2 | 1.11.1 | 1.11.1 |
| libmcrypt | 2.5.8 | 2.5.8 |
| gmp | 6.3.0 | 6.3.0 |
| libjudy | 1.0.5 | 1.0.5 |
| libffi | 3.4.8 | 3.8.1 |

## Build adjustments

- Updated ICU archive naming, SQLite URL/year and configure switches, and libxml2 source path.
- PostgreSQL 18 uses modern Bison/Flex and no optional libcurl integration. Its combined static libpq archive uses the public-symbol variants of libpgcommon/libpgport; the removed pg_config_ext.h is no longer copied.
- Dependency cache keys hash all dependency scripts so unchanged consumers rebuild against refreshed libraries.

## Validation

- Downloaded and inspected all 37 source archives; PostgreSQL 18.7 and Lua 5.5.1 were additionally downloaded by their local builds.
- Local macOS ARM64 builds: zlib, OpenSSL, ICU, SQLite, libffi, Lua, and libpq.
- Runtime checks: zlib compression tests, SQLite JSON query, Lua interpreter, and libpq version/link check.
- Full PHP and extension validation runs in the PHP 8.5 ARM64 workflow.
- Known existing issue: PECL lua 2.0.7 fails to compile against PHP 8.5 because it uses removed PHP/Zend APIs. A native Lua update does not resolve that extension issue.
