#!/usr/bin/env python3
"""Persist a source revision only after its workflow dispatch succeeds."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def workflows(directory):
    for path in sorted(directory.iterdir()):
        if path.suffix not in ('.yml', '.yaml'):
            continue
        text = path.read_text(encoding='utf-8')
        url = re.search(r'^  REPO_URL: (https://github.com/[\w.-]+/[\w.-]+)\s*$', text, re.M)
        branch = re.search(r'^  REPO_BRANCH: ([\w./-]+)\s*$', text, re.M)
        if url and branch and re.search(r'^  workflow_dispatch:', text, re.M):
            yield path.name, url[1].removesuffix('.git'), branch[1]


def check(root, state_path, repository, ref, run=subprocess.run):
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    revisions = {}
    failed = False
    for filename, url, branch in workflows(root / '.github/workflows'):
        key = f'{url}@{branch}'
        try:
            if key not in revisions:
                result = run(['git', 'ls-remote', '--exit-code', url, f'refs/heads/{branch}'],
                             check=True, capture_output=True, text=True, timeout=120)
                revisions[key] = result.stdout.split()[0]
                if not re.fullmatch(r'[0-9a-f]{40}', revisions[key]):
                    raise ValueError('Invalid upstream commit')
            revision = revisions[key]
            current = {'source': key, 'revision': revision}
            if state.get(filename) == current:
                continue
            run(['gh', 'workflow', 'run', filename, '--repo', repository, '--ref', ref],
                check=True, timeout=120)
            state[filename] = current
            print(f'Dispatched {filename}: {revision}')
        except (subprocess.SubprocessError, ValueError, IndexError) as error:
            print(f'::error::{filename}: {error}')
            failed = True
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(json.dumps(state, indent=2, sort_keys=True) + '\n')
    return int(failed)


if __name__ == '__main__':
    root = Path(os.environ['GITHUB_WORKSPACE'])
    sys.exit(check(root, root / '.github/source-state/dispatched.json',
                   os.environ['GITHUB_REPOSITORY'], os.environ['DEFAULT_BRANCH']))
