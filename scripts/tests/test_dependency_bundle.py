"""Exercise migration and a partial cache miss on one runner, offline."""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

import unittest
import test_dependency_release_cache as cache_tests

SCRIPT = Path(__file__).resolve().parents[1] / 'dependency-bundle.py'


class BundleTests(unittest.TestCase):
    make_library = cache_tests.ReleaseCacheTests.make_library
    def setUp(self):
        cache_tests.ReleaseCacheTests.setUp(self)
        self.prefix = self.root / 'merged'
        self.individual = self.root / 'individual'
        self.recipes = self.root / 'recipes'
        self.recipes.mkdir()
        self.manifest = self.root / 'libraries.json'
        self.manifest.write_text(json.dumps([dict(name='zlib', script='01-zlib.sh', libs='libz.a')]))
        self.build_marker = self.root / 'compiled'
        self.recipe = self.recipes / '01-zlib.sh'
        self.recipe.write_text(f'''#!/bin/bash
set -euo pipefail
VERSION="1.4"
mkdir -p "$DEPS_PREFIX/lib" "$DEPS_PREFIX/include"
cp "{self.cache}/lib/libz.a" "$DEPS_PREFIX/lib/libz.a"
touch "{self.build_marker}"
''')
        self.env.update(DEPS_PREFIX=str(self.prefix), DEPS_CACHE_ROOT=str(self.individual),
                        RECIPE_HASH='recipe1', BUNDLE_KEY='deps-bundle-darwin-arm64-bundle1',
                        DEPENDENCY_MANIFEST=str(self.manifest), DEPENDENCY_SCRIPT_ROOT=str(self.recipes))

    def run_bundle(self, mode, **env):
        output = self.root / 'output'
        output.write_text('')
        result = subprocess.run(['python3', str(SCRIPT), mode], env=dict(self.env, **env),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return output.read_text()

    def test_individual_actions_hit_becomes_complete_release_bundle(self):
        shutil.copytree(self.cache, self.individual / 'zlib')
        self.assertIn('needs_build=false', self.run_bundle('prepare', MATCHED_ZLIB=self.env['CACHE_KEY']))
        self.assertFalse(self.build_marker.exists())
        self.assertEqual((self.prefix / '.built-zlib').read_text(), '1.4\n')
        self.run_bundle('save')
        shutil.rmtree(self.prefix)
        self.assertIn('source=release', self.run_bundle('restore'))
        self.assertTrue((self.prefix / 'lib/libz.a').exists())

    def test_only_missing_libraries_build_and_publish(self):
        self.assertIn('needs_build=true', self.run_bundle('prepare'))
        self.run_bundle('build')
        self.assertTrue(self.build_marker.exists())
        self.assertTrue((self.individual / 'zlib/lib/libz.a').exists())
        self.assertTrue((self.remote / (self.env['CACHE_KEY'] + '.tar.gz')).exists())

    def test_relocation_of_cached_pkgconfig_and_pg_config(self):
        spec = importlib.util.spec_from_file_location('bundle', SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        pc = self.prefix / 'lib/pkgconfig/libpq.pc'
        pc.parent.mkdir(parents=True)
        pc.write_text(f'prefix={self.individual}\nlibdir=${{prefix}}/lib\n')
        pg = self.prefix / 'bin/pg_config'
        pg.parent.mkdir()
        pg.write_text(f'#!/bin/bash\nPREFIX="{self.individual}"\n')
        module.relocate(self.prefix, self.individual)
        self.assertIn(f'prefix={self.prefix}', pc.read_text())
        self.assertIn(f'PREFIX="{self.prefix}"', pg.read_text())

    def test_compile_output_is_saved_and_progress_is_printed(self):
        self.recipe.write_text(self.recipe.read_text() + "echo compiler-detail-only-in-log\n")
        self.run_bundle('prepare')
        output = self.root / 'output'
        result = subprocess.run(['python3', str(SCRIPT), 'build'], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('BUILD [1/1] zlib 1.4', result.stdout)
        self.assertNotIn('compiler-detail-only-in-log', result.stdout)
        self.assertIn('compiler-detail-only-in-log', (self.individual / 'logs/zlib-build.log').read_text())

    def test_failure_prints_log_tail_and_records_failed_dependency(self):
        self.recipe.write_text('VERSION="1.4"\necho deliberate-compile-failure\nexit 7\n')
        self.run_bundle('prepare')
        result = subprocess.run(['python3', str(SCRIPT), 'build'], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 7)
        self.assertIn('deliberate-compile-failure', result.stdout)
        report = json.loads((self.individual / 'logs/progress.json').read_text())
        self.assertEqual(report['zlib']['state'], 'FAILED')

    def test_debug_streams_compile_output_and_keeps_log(self):
        self.recipe.write_text(self.recipe.read_text() + "echo debug-visible-detail\n")
        self.run_bundle('prepare')
        result = subprocess.run(['python3', str(SCRIPT), 'build'],
                                env=dict(self.env, DEPENDENCY_DEBUG='true'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn('| debug-visible-detail', result.stdout)
        self.assertIn('debug-visible-detail', (self.individual / 'logs/zlib-build.log').read_text())

    def test_relocation_rewrites_absolute_freetype_paths(self):
        pc = self.prefix / 'lib/pkgconfig/freetype2.pc'
        pc.parent.mkdir(parents=True)
        old_bundle = '/Users/runner/work/_temp/phm-deps-bundle/darwin-arm64'
        old_library = str(self.individual)
        pc.write_text(f'prefix={old_bundle}\nincludedir={old_library}/include/freetype2\nlibdir={old_bundle}/lib\nCflags: -I{old_library}/include/freetype2\nLibs: -L{old_bundle}/lib -lfreetype\n')
        result = subprocess.run(['python3', str(SCRIPT.parent / 'relocate-dependencies.py'),
                                 str(self.prefix), '--from-prefix', old_library],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = pc.read_text()
        self.assertNotIn(old_bundle, text)
        self.assertNotIn(old_library, text)
        self.assertIn(f'includedir={self.prefix}/include/freetype2', text)
        self.assertIn(f'Libs: -L{self.prefix}/lib -lfreetype', text)
