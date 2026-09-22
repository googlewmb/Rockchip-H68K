#!/usr/bin/env python3
"""Run OpenWrt stages without hiding errors or discarding their diagnostics."""
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ERROR = re.compile(r'ERROR: .*failed to build|build failed\.|\*\*\*.*Error [0-9]+')
CONFIG_ERROR = re.compile(r'recursive dependency detected|(?:^|[\s:])error:')


def exclude_unused_broken_feeds(root):
    """Keep known unused feed menus from breaking Kconfig on these profiles.

    Only unlink installed feed entries; retain upstream sources and any family
    selected as built-in, module, translation, or by an all-packages build.
    """
    config = (root / '.config').read_text(encoding='utf-8')
    selected = set(re.findall(r'^CONFIG_PACKAGE_([^=]+)=[ym]$', config, re.M))
    if re.search(r'^CONFIG_(?:ALL|ALL_KMODS|ALL_NONSHARED)=y$', config, re.M):
        return
    groups = (
        (r'(?:luci-app-fchomo|luci-i18n-fchomo-.+)', ('luci-app-fchomo',)),
        (r'(?:librespeed(?:-.+)?|luci-app-librespeed|luci-i18n-librespeed-.+)',
         ('luci-app-librespeed', 'librespeed-cli', 'librespeed-cli-rust', 'librespeed-common')),
        (r'(?:squeezelite(?:-.+)?|luci-app-squeezelite|luci-i18n-squeezelite-.+)',
         ('squeezelite',)),
    )
    for pattern, entries in groups:
        if any(re.fullmatch(pattern, name) for name in selected):
            continue
        for name in entries:
            for entry in (root / 'package/feeds').glob(f'*/{name}'):
                if not entry.is_symlink():
                    raise RuntimeError(f'Refusing to remove a non-symlink: {entry}')
                entry.unlink()
                print(f'Exclude unused feed menu with known Kconfig cycle: {entry}')


def run_logged(command, logfile, pattern=ERROR):
    logfile.parent.mkdir(parents=True, exist_ok=True)
    failed = False
    with logfile.open('w', encoding='utf-8') as log:
        with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, errors='replace') as process:
            for line in process.stdout:
                print(line, end='', flush=True)
                log.write(line)
                failed |= bool(pattern.search(line))
            code = process.wait()
    return code or int(failed)


def device_name(config):
    devices = sorted(set(re.findall(r'^CONFIG_TARGET_(.*_DEVICE_.*)=y$', config, re.M)))
    if len(devices) == 1:
        return devices[0]
    board = re.search(r'^CONFIG_TARGET_BOARD="([^"]+)"$', config, re.M)
    if not board:
        raise ValueError('No target board found in .config')
    return board[1] + ('_multi' if len(devices) > 1 else '_default')


def main(stage):
    workspace = Path(os.environ['GITHUB_WORKSPACE'])
    logs = workspace / 'build-logs'
    jobs = str(os.cpu_count() or 1)
    if stage == 'device':
        name = device_name(Path('.config').read_text())
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as env:
            env.write(f'DEVICE_NAME={name}\n')
        return 0
    if stage == 'defconfig':
        exclude_unused_broken_feeds(Path.cwd())
        return run_logged(['make', 'defconfig'], logs / 'defconfig.log', CONFIG_ERROR)
    if stage == 'compile':
        return run_logged(['make', f'-j{jobs}', 'V=s', 'BUILD_LOG=1'], logs / 'compile.log')
    if stage == 'download':
        for attempt in range(1, 4):
            code = run_logged(['make', 'download', f'-j{jobs}', 'V=s'], logs / f'download-{attempt}.log')
            if not code:
                return 0
            if attempt < 3:
                time.sleep(10)
        return code
    raise ValueError(f'Unknown stage: {stage}')


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
