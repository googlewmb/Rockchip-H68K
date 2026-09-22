#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


build = load('ci-build')
sources = load('check-sources')
save = load('ci-save-file')


class BuildTests(unittest.TestCase):
    def test_zero_exit_package_failure_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'download.log'
            code = build.run_logged([sys.executable, '-c', 'print("ERROR: package/tcping failed to build.")'], log)
            self.assertNotEqual(code, 0)
            self.assertIn('tcping', log.read_text())

    def test_real_exit_status_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(build.run_logged([sys.executable, '-c', 'raise SystemExit(7)'], Path(directory) / 'out'), 7)

    def test_config_error_with_success_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertNotEqual(build.run_logged([sys.executable, '-c', 'print("tmp/.config:1:error: recursive dependency detected!")'],
                                                Path(directory) / 'out', build.CONFIG_ERROR), 0)

    def test_expected_configure_probe_is_not_a_build_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(build.run_logged([sys.executable, '-c', 'print("configure probe error: unavailable optional feature")'], Path(directory) / 'out'), 0)

    def test_download_retries_and_stops(self):
        with patch.dict(os.environ, GITHUB_WORKSPACE=str(ROOT)), patch.object(build, 'run_logged', side_effect=[1, 0]) as run, patch.object(build.time, 'sleep'):
            self.assertEqual(build.main('download'), 0)
            self.assertEqual(run.call_count, 2)
        with patch.dict(os.environ, GITHUB_WORKSPACE=str(ROOT)), patch.object(build, 'run_logged', return_value=2) as run, patch.object(build.time, 'sleep'):
            self.assertEqual(build.main('download'), 2)
            self.assertEqual(run.call_count, 3)

    def test_multiple_devices_produce_one_env_value(self):
        config = 'CONFIG_TARGET_BOARD="rockchip"\nCONFIG_TARGET_rockchip_armv8_DEVICE_a=y\nCONFIG_TARGET_rockchip_armv8_DEVICE_b=y\n'
        self.assertEqual(build.device_name(config), 'rockchip_multi')
        self.assertEqual(build.device_name('CONFIG_TARGET_BOARD="rockchip"\n'), 'rockchip_default')


class SourceTests(unittest.TestCase):
    def test_success_is_saved_but_failure_is_retried(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / '.github/workflows'
            folder.mkdir(parents=True)
            content = 'on:\n  workflow_dispatch:\nenv:\n  REPO_URL: https://github.com/openwrt/openwrt\n  REPO_BRANCH: main\n'
            for name in ['a.yml', 'b.yaml']:
                (folder / name).write_text(content)
            state = root / 'state.json'
            calls = []
            fail_b = True
            def fake(args, **kwargs):
                calls.append(args)
                if args[0] == 'git':
                    return subprocess.CompletedProcess(args, 0, 'a' * 40 + '\trefs/heads/main\n')
                if args[3] == 'b.yaml' and fail_b:
                    raise subprocess.CalledProcessError(1, args)
                return subprocess.CompletedProcess(args, 0)
            self.assertEqual(sources.check(root, state, 'owner/repo', 'main', fake), 1)
            self.assertEqual(list(json.loads(state.read_text())), ['a.yml'])
            self.assertEqual(sum(c[0] == 'git' for c in calls), 1)
            calls.clear()
            fail_b = False
            self.assertEqual(sources.check(root, state, 'owner/repo', 'main', fake), 0)
            self.assertEqual([c[3] for c in calls if c[0] == 'gh'], ['b.yaml'])
            calls.clear()
            self.assertEqual(sources.check(root, state, 'owner/repo', 'main', fake), 0)
            self.assertFalse(any(c[0] == 'gh' for c in calls))


class WorkflowTests(unittest.TestCase):
    def test_profiles_and_input_paths(self):
        import re
        profiles = []
        for file in (ROOT / '.github/workflows').iterdir():
            text = file.read_text(encoding='utf-8')
            if 'REPO_URL:' not in text:
                continue
            profiles.append(re.search(r'^  BUILD_PROFILE: (.+)$', text, re.M)[1])
            for name in ['CONFIG_BUILD', 'DIY_P1_SH', 'DIY_P2_SH', 'PLATFORM_FILE', 'CONFIG_5G']:
                value = re.search(rf'^  {name}: (.+)$', text, re.M)
                if value:
                    self.assertTrue((ROOT / value[1]).is_file(), (file.name, value[1]))
            self.assertNotIn('staging_dir/host', text)
            self.assertNotIn('|| make -j1', text)
            self.assertNotIn('fix-kmods-feeds.sh', text)
            self.assertIn('scripts/ci-build.py" compile', text)
        self.assertEqual(len(profiles), len(set(profiles)))

    def test_full_profiles_use_full_inputs(self):
        for name in ['Openwrt_test-istoreALL-25.12.yaml', 'openwrt-test-istoreALL-24.10.yml']:
            text = (ROOT / '.github/workflows' / name).read_text(encoding='utf-8')
            self.assertIn('CONFIG_BUILD: test-istore/test-istore/', text)
            self.assertIn('DIY_P1_SH: test-istore/diy-part1.sh', text)

    def test_save_rejects_path_escape(self):
        with self.assertRaises(ValueError):
            save.save('unused', '../outside', 'main')


if __name__ == '__main__':
    unittest.main()
