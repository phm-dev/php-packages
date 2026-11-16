# Native dependency binary cache

## One runner per architecture

Dependencies are restored and, if necessary, built in a **single job**. The old
37-library matrix and separate merge job are no longer used. A cache hit must not
require a new macOS runner for every library.

The fast path restores the complete dependency bundle from Actions cache, then
from the `native-dependency-cache-v1` prerelease. One download supplies all 37
libraries, headers, and helper tools. The combined artifact name remains
`deps-{platform}`, so the PHP build consumes it as before.

If the complete bundle is unavailable, the same runner:

1. Restores existing individual Actions cache entries, preserving their original
   paths and cache identities for migration.
2. Falls back to exact individual release assets and verifies SHA-256, manifest,
   and required static archives/headers.
3. Merges restored files, relocates pkg-config/pg_config, and marks prerequisites.
4. Installs build tools once if anything is missing, then builds only missing
   libraries in dependency order from `scripts/dependency-libraries.json`.
5. Publishes individual restored/built libraries to Releases, then publishes the
   complete bundle to Releases and Actions cache.

Individual assets use `dep-{library}-{platform}-{recipe-hash}.tar.gz` with a
matching `.sha256`. The recipe hash covers all `scripts/deps/*.sh`, including
pinned versions, compiler/deployment settings and transitive dependency recipes.
The whole-bundle key also covers the library manifest and orchestration scripts.
ARM64 and AMD64 do not share assets. There is no latest-version fallback.

`force_rebuild_deps=true` bypasses both caches and rebuilds all dependencies.
A normal run retains and publishes valid cached binaries. Missing libraries are
built serially on the same runner, using parallel `make` within each library.
This trades cold-build matrix parallelism for eliminating runner queues and
repeated setup/transfer work on the normal cached path.

## One-time migration

The workflow accepts the exact old Actions cache key from the November 2026
refresh, only while the recipe hash matches the reviewed migration snapshot.
Dependency versions are identical; the only recipe change is the libmcrypt
bootstrap fix. libmcrypt is excluded from legacy restore. Changing any dependency
recipe disables this fallback automatically. The non-PHP prerelease tag is skipped
by the package index generator. Publication requires `contents: write`.

## Progress and logs

Normal output reports `RESTORE [12/37] libzip 1.12.1`, cache source, elapsed time,
cache/build totals, and `BUILD [n/37]` for missing libraries. A running compilation
emits a heartbeat every 20 seconds, with elapsed time and log size. Compiler
output is stored in `{library}-build.log`; cache operations have separate logs.
A failure prints the last 60 lines and records the failed library.

Set the manual workflow input `debug=true` to stream full output live as well as
save it. The `dependency-logs-{platform}` artifact is uploaded even after failures
and includes logs, `progress.json`, and `summary.md`. The job summary also shows a
version/result/time table. Logs are retained for 14 days.

Run offline integration checks with:

```bash
python3 -m unittest discover -s scripts/tests -v
```
