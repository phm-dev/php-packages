# Native dependency binary cache

Each library job uses the following order:

1. Restore GitHub Actions cache and validate its required static archives/headers.
2. If unavailable, download the exact matching binary from the prerelease
   `native-dependency-cache-v1` and verify SHA-256, manifest, and required archives.
3. If unavailable or invalid, compile from source.
4. Publish valid binaries to the prerelease (including binaries restored from
   Actions), populate Actions cache, and upload the usual inter-job artifact.

Assets use `dep-{library}-{platform}-{recipe-hash}.tar.gz` with a matching
`.sha256`. The manifest repeats the identity and format version. The recipe hash
covers **all** `scripts/deps/*.sh`, including pinned versions, build switches,
shared compiler/deployment settings, and transitive dependency recipes. A change
invalidates the whole dependency set; ARM64 and AMD64 never share an asset.
Release binaries do not expire when Actions cache entries expire. No latest-release
fallback or broad version prefix is used.

`force_rebuild_deps=true` bypasses both caches and republishes rebuilt release
assets. Ordinary runs reuse existing complete assets.

## One-time migration

The workflow accepts the exact old Actions cache key from the November 2026
refresh, only while the current dependency recipe hash matches the reviewed
migration snapshot. Dependency versions are identical; the only recipe change is
the libmcrypt bootstrap fix. libmcrypt is excluded from legacy restore and builds
again. Valid restored libraries are published under the current key. Changing
any dependency recipe disables this compatibility fallback automatically.

The release is a prerelease with a non-PHP tag, so it is not an installable PHP
release and the package index generator skips it. Publication requires the
workflow token's `contents: write` permission.

Run offline integration checks with:

```bash
python3 -m unittest discover -s scripts/tests -v
```
