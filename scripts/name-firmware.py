#!/usr/bin/env python3
"""Prefix firmware images with the workflow filename, preserving image contents."""
import json
import os
from pathlib import Path
import re

IMAGE = re.compile(r'\.(?:img|bin|itb|ubi|ubifs|trx|chk|elf|vmdk|vdi|qcow2|iso)(?:\.(?:gz|xz|zst|bz2))?$')


def rename_images(directory, prefix):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', prefix):
        raise ValueError('Invalid workflow filename prefix')
    mapping = {p.name: prefix + '_' + p.name for p in directory.iterdir()
               if p.is_file() and IMAGE.search(p.name) and not p.name.startswith(prefix + '_')}
    for new in mapping.values():
        if (directory / new).exists():
            raise FileExistsError(directory / new)
    # Keep checksum entries and image metadata usable after renaming.
    updates = {}
    for name in ['sha256sums', 'md5sums', 'sha512sums']:
        path = directory / name
        if path.is_file():
            lines = []
            for line in path.read_text().splitlines(keepends=True):
                match = re.match(r'^(\S+\s+\*?)(.*?)(\r?\n)?$', line)
                if match:
                    line = match[1] + mapping.get(match[2], match[2]) + (match[3] or '')
                lines.append(line)
            updates[path] = ''.join(lines)
    profiles = directory / 'profiles.json'
    if profiles.is_file() and mapping:
        def replace(value):
            if isinstance(value, dict):
                return {k: replace(v) for k, v in value.items()}
            if isinstance(value, list):
                return [replace(v) for v in value]
            return mapping.get(value, value) if isinstance(value, str) else value
        updates[profiles] = json.dumps(replace(json.loads(profiles.read_text())), indent=2) + '\n'
    for old, new in mapping.items():
        (directory / old).rename(directory / new)
        print(f'{old} -> {new}')
    for path, text in updates.items():
        path.write_text(text)
    return mapping


if __name__ == '__main__':
    for directory in sorted(Path('openwrt/bin/targets').glob('*/*')):
        if directory.is_dir():
            rename_images(directory, os.environ['FIRMWARE_PREFIX'])
