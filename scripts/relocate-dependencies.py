#!/usr/bin/env python3
"""Relocate native dependency metadata after restoring/copying a build prefix."""
import argparse
from pathlib import Path
import re


def relocate(prefix, previous):
    prefix = Path(prefix)
    files = list((prefix / 'lib/pkgconfig').glob('*.pc'))
    old = {str(p).rstrip('/') for p in previous if str(p).rstrip('/') != str(prefix)}
    # Gather before rewriting: some packages embed absolute paths independently
    # in includedir/libdir/Cflags instead of referencing ${prefix}.
    for file in files:
        match = re.search(r'^prefix\s*=\s*(/[^\n]+)', file.read_text(), re.M)
        if match and match.group(1).strip() != str(prefix):
            old.add(match.group(1).strip().rstrip('/'))
    for file in files:
        text = file.read_text()
        for value in sorted(old, key=len, reverse=True):
            text = text.replace(value + '/', str(prefix) + '/')
            text = re.sub(re.escape(value) + r'(?=[\s"\']|$)', lambda _: str(prefix), text)
        text = re.sub(r'^prefix\s*=.*$', f'prefix={prefix}', text, flags=re.M)
        file.write_text(text)
    for file in (prefix / 'bin').glob('*'):
        if file.is_file():
            file.chmod(file.stat().st_mode | 0o111)
    pg_config = prefix / 'bin/pg_config'
    if pg_config.exists() and pg_config.read_bytes().startswith(b'#!/bin/bash'):
        text = re.sub(r'^PREFIX=.*$', f'PREFIX="{prefix}"', pg_config.read_text(), flags=re.M)
        pg_config.write_text(text)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('prefix', type=Path)
    parser.add_argument('--from-prefix', action='append', default=[])
    args = parser.parse_args()
    relocate(args.prefix, args.from_prefix)
