#!/usr/bin/env python3
"""Restore/build native dependencies on one runner, with a whole-set fast path."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = Path(os.environ.get('DEPENDENCY_MANIFEST', ROOT / 'scripts/dependency-libraries.json'))
RECIPES = Path(os.environ.get('DEPENDENCY_SCRIPT_ROOT', ROOT / 'scripts/deps'))
HELPER = ROOT / 'scripts/dependency-release-cache.sh'


def output(key, value):
    line = f'{key}={value}'
    print(line, flush=True)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as target:
            target.write(line + '\n')



def log_dir():
    directory = Path(os.environ.get('DEPENDENCY_LOG_DIR', Path(os.environ['DEPS_CACHE_ROOT']) / 'logs'))
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def run_logged(command, env, label, filename):
    logfile = log_dir() / filename
    started = time.monotonic()
    debug = os.environ.get('DEPENDENCY_DEBUG', 'false').lower() == 'true'
    print(f'{label} — running; log: {logfile.name}', flush=True)
    with logfile.open('w') as log:
        if debug:
            process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True, errors='replace')
            for line in process.stdout:
                log.write(line)
                log.flush()
                print('| ' + line.rstrip(), flush=True)
            code = process.wait()
        else:
            process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
            while True:
                try:
                    code = process.wait(timeout=float(os.environ.get('DEPENDENCY_HEARTBEAT_SECONDS', '20')))
                    break
                except subprocess.TimeoutExpired:
                    elapsed = time.monotonic() - started
                    print(f'{label} — still running ({elapsed:.0f}s, {logfile.stat().st_size // 1024} KiB logged)', flush=True)
    if code:
        print(f'::error::{label} failed (exit {code}); see {logfile.name}', flush=True)
        print(f'::group::Last 60 lines: {logfile.name}', flush=True)
        for line in logfile.read_text(errors='replace').splitlines()[-60:]:
            print('| ' + line, flush=True)
        print('::endgroup::', flush=True)
        raise subprocess.CalledProcessError(code, command)
    return time.monotonic() - started


def version(dep):
    text = (RECIPES / dep['script']).read_text()
    return re.search(r'^VERSION="([^"]+)"', text, re.M).group(1)


def record(dep, state, elapsed):
    path = log_dir() / 'progress.json'
    report = json.loads(path.read_text()) if path.exists() else {}
    report[dep['name']] = dict(version=version(dep), state=state, seconds=round(elapsed, 1))
    path.write_text(json.dumps(report, indent=2) + '\n')
    lines = ['## Native dependencies', '', '| Library | Version | Result | Time |',
             '| --- | --- | --- | --- |']
    for name, item in report.items():
        lines.append(f"| {name} | {item['version']} | {item['state']} | {item['seconds']}s |")
    summary = '\n'.join(lines) + '\n'
    (log_dir() / 'summary.md').write_text(summary)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        Path(os.environ['GITHUB_STEP_SUMMARY']).write_text(summary)


def cache(mode, name, libs, directory, key, matched=''):
    with tempfile.NamedTemporaryFile() as result:
        env = dict(os.environ, CACHE_KEY=key, CACHE_DIR=str(directory), DEP_NAME=name,
                   DEP_LIBS=libs, MATCHED_KEY=matched, GITHUB_OUTPUT=result.name)
        run_logged(['bash', str(HELPER), mode], env, f'{name}: cache {mode}', f'{name}-{mode}.log')
        result.seek(0)
        return dict(line.decode().strip().split('=', 1) for line in result if b'=' in line)


def merge(directory, prefix):
    for name in ('lib', 'include', 'bin', 'licenses'):
        source = directory / name
        if source.is_dir():
            shutil.copytree(source, prefix / name, dirs_exist_ok=True)


def relocate(prefix, cache_root):
    subprocess.run(['python3', str(ROOT / 'scripts/relocate-dependencies.py'),
                    str(prefix), '--from-prefix', str(cache_root)], check=True)


def marker(dep, prefix):
    (prefix / ('.built-' + dep['name'])).write_text(version(dep) + '\n')


def snapshot(dep, prefix, destination):
    shutil.rmtree(destination, ignore_errors=True)
    (destination / 'lib').mkdir(parents=True)
    for lib in dep['libs'].split():
        shutil.copy2(prefix / 'lib' / lib, destination / 'lib' / lib)
    for name in ('include', 'bin', 'licenses'):
        if (prefix / name).is_dir():
            shutil.copytree(prefix / name, destination / name)
    if (prefix / 'lib/pkgconfig').is_dir():
        shutil.copytree(prefix / 'lib/pkgconfig', destination / 'lib/pkgconfig')


def main(mode):
    deps = json.loads(MANIFEST.read_text())
    prefix = Path(os.environ['DEPS_PREFIX'])
    cache_root = Path(os.environ['DEPS_CACHE_ROOT'])
    recipe_hash = os.environ['RECIPE_HASH']
    platform = os.environ['DEP_PLATFORM']
    cache_root.mkdir(parents=True, exist_ok=True)
    all_libs = ' '.join(dict.fromkeys(lib for dep in deps for lib in dep['libs'].split()))
    bundle_key = os.environ['BUNDLE_KEY']
    if mode in ('restore', 'save'):
        result = cache(mode, 'bundle', all_libs, prefix, bundle_key,
                       os.environ.get('BUNDLE_MATCHED_KEY', ''))
        for key, value in result.items():
            output(key, value)
        if mode == 'restore' and result.get('hit') == 'true':
            for dep in deps:
                record(dep, 'bundle / ' + result.get('source', 'cache'), 0)
            print(f'READY: all {len(deps)} libraries restored in one bundle; no builds needed.', flush=True)
        return
    prefix.mkdir(parents=True, exist_ok=True)
    for name in ('lib/pkgconfig', 'include', 'bin', 'licenses'):
        (prefix / name).mkdir(parents=True, exist_ok=True)
    missing = []
    if mode == 'prepare':
        for position, dep in enumerate(deps, 1):
            name = dep['name']
            started = time.monotonic()
            label = f'RESTORE [{position}/{len(deps)}] {name} {version(dep)}'
            print(label, flush=True)
            key = f'dep-{name}-{platform}-{recipe_hash}'
            directory = cache_root / name
            env_key = 'MATCHED_' + name.replace('-', '_').upper()
            result = cache('restore', name, dep['libs'], directory, key, os.environ.get(env_key, ''))
            if result.get('hit') == 'true':
                merge(directory, prefix)
                marker(dep, prefix)
                # Migrate every restored Actions entry to Releases immediately.
                cache('save', name, dep['libs'], directory, key)
                state = result.get('source', 'cache')
            else:
                missing.append(name)
                state = 'build required'
            elapsed = time.monotonic() - started
            record(dep, state, elapsed)
            print(f'{label} — {state} ({elapsed:.1f}s)', flush=True)
        relocate(prefix, cache_root)
        (cache_root / 'missing.json').write_text(json.dumps(missing))
        print(f'RESTORE COMPLETE: {len(deps) - len(missing)}/{len(deps)} cached; {len(missing)} to build.', flush=True)
        output('needs_build', str(bool(missing)).lower())
        output('missing', ','.join(missing))
    elif mode == 'build':
        missing = json.loads((cache_root / 'missing.json').read_text())
        env = dict(os.environ, PATH=str(prefix / 'bin') + os.pathsep + os.environ['PATH'],
                   PLATFORM=platform)
        for position, dep in enumerate(deps, 1):
            if dep['name'] not in missing:
                continue
            label = f"BUILD [{position}/{len(deps)}] {dep['name']} {version(dep)}"
            started = time.monotonic()
            try:
                run_logged(['bash', str(RECIPES / dep['script'])], env, label, dep['name'] + '-build.log')
            except subprocess.CalledProcessError:
                record(dep, 'FAILED', time.monotonic() - started)
                raise
            directory = cache_root / dep['name']
            snapshot(dep, prefix, directory)
            key = f"dep-{dep['name']}-{platform}-{recipe_hash}"
            cache('save', dep['name'], dep['libs'], directory, key)
            relocate(prefix, cache_root)
            elapsed = time.monotonic() - started
            record(dep, 'built and published', elapsed)
            print(f'{label} — built and published ({elapsed:.1f}s)', flush=True)
        print(f'BUILD COMPLETE: {len(missing)} libraries built; all {len(deps)} ready.', flush=True)
    else:
        raise ValueError(f'Unknown mode: {mode}')


if __name__ == '__main__':
    try:
        main(sys.argv[1])
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
