"""Offline integration checks for the dependency cache transport."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'dependency-release-cache.sh'


class ReleaseCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / 'cache'
        self.remote = self.root / 'release'
        self.remote.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        mock = self.bin / 'gh'
        mock.write_text('''#!/usr/bin/env python3
import os, pathlib, shutil, sys
root = pathlib.Path(os.environ['MOCK_RELEASE'])
a = sys.argv[1:]
if a[:2] == ['release', 'view']:
    print('\\n'.join(p.name for p in root.iterdir()))
elif a[:2] == ['release', 'upload']:
    for f in a[3:]:
        if pathlib.Path(f).is_file(): shutil.copyfile(f, root / pathlib.Path(f).name)
elif a[:2] == ['release', 'download']:
    dest = pathlib.Path(a[a.index('--dir') + 1])
    patterns = [a[i + 1] for i, v in enumerate(a) if v == '--pattern']
    if any(not (root / p).exists() for p in patterns): sys.exit(1)
    for p in patterns: shutil.copyfile(root / p, dest / p)
else: sys.exit(2)
''')
        mock.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        MOCK_RELEASE=str(self.remote), CACHE_KEY='dep-zlib-darwin-arm64-recipe1',
                        CACHE_DIR=str(self.cache), DEP_NAME='zlib', DEP_PLATFORM='darwin-arm64',
                        DEP_LIBS='libz.a', GITHUB_OUTPUT=str(self.root / 'output'))
        self.make_library()

    def make_library(self):
        (self.cache / 'lib').mkdir(parents=True, exist_ok=True)
        (self.cache / 'include').mkdir(exist_ok=True)
        source = self.root / 'test.c'
        source.write_text('int cache_test(void) { return 42; }\n')
        subprocess.run(['cc', '-c', str(source), '-o', str(self.root / 'test.o')], check=True)
        subprocess.run(['ar', 'rcs', str(self.cache / 'lib/libz.a'), str(self.root / 'test.o')], check=True)

    def run_cache(self, mode, **env):
        output = self.root / 'output'
        output.write_text('')
        result = subprocess.run(['bash', str(SCRIPT), mode], env=dict(self.env, **env),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output.read_text()

    def clear_cache(self):
        import shutil
        shutil.rmtree(self.cache, ignore_errors=True)

    def test_actions_hit_migrates_to_release_and_release_restores(self):
        self.assertIn('source=actions', self.run_cache('restore', MATCHED_KEY=self.env['CACHE_KEY']))
        self.run_cache('save')
        self.assertEqual(len(list(self.remote.iterdir())), 2)
        self.clear_cache()
        self.assertIn('source=release', self.run_cache('restore'))
        self.assertTrue((self.cache / 'lib/libz.a').exists())
        manifest = json.loads((self.cache / 'cache-manifest.json').read_text())
        self.assertEqual(manifest['key'], self.env['CACHE_KEY'])

    def test_miss_and_force_build(self):
        self.clear_cache()
        self.assertIn('hit=false', self.run_cache('restore'))
        self.make_library()
        self.run_cache('save')
        self.assertIn('hit=false', self.run_cache('restore', FORCE_REBUILD='true', MATCHED_KEY='existing'))
        self.assertFalse(self.cache.exists())

    def test_checksum_mismatch_falls_back_to_build(self):
        self.run_cache('save')
        archive = self.remote / (self.env['CACHE_KEY'] + '.tar.gz')
        archive.write_bytes(b'corrupt')
        self.clear_cache()
        self.assertIn('hit=false', self.run_cache('restore'))

    def test_other_version_is_not_used(self):
        self.run_cache('save')
        self.clear_cache()
        self.assertIn('hit=false', self.run_cache('restore', CACHE_KEY='dep-zlib-darwin-arm64-recipe2'))

    def test_wrong_platform_manifest_is_rejected(self):
        self.run_cache('save')
        self.clear_cache()
        self.assertIn('hit=false', self.run_cache('restore', DEP_PLATFORM='darwin-amd64'))

    def test_incomplete_actions_cache_falls_back_to_release(self):
        self.run_cache('save')
        (self.cache / 'lib/libz.a').unlink()
        self.assertIn('source=release', self.run_cache('restore', MATCHED_KEY=self.env['CACHE_KEY']))

    def test_tar_traversal_is_rejected(self):
        name = self.env['CACHE_KEY'] + '.tar.gz'
        archive = self.remote / name
        with tarfile.open(archive, 'w:gz') as tar:
            member = tarfile.TarInfo('../escape')
            member.size = 1
            tar.addfile(member, io.BytesIO(b'x'))
        (self.remote / (name + '.sha256')).write_text(hashlib.sha256(archive.read_bytes()).hexdigest())
        self.clear_cache()
        self.assertIn('hit=false', self.run_cache('restore'))
        self.assertFalse((self.root / 'escape').exists())

    def test_save_is_idempotent(self):
        self.run_cache('save')
        before = {p.name: p.read_bytes() for p in self.remote.iterdir()}
        self.run_cache('save')
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.remote.iterdir()})


if __name__ == '__main__':
    unittest.main()
