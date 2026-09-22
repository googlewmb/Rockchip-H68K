#!/usr/bin/env python3
"""Save one generated file, replaying only that file if another job pushes."""
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tempfile
import time


def save(source, destination, branch):
    target = PurePosixPath(destination)
    if target.is_absolute() or '..' in target.parts or str(target) == '.':
        raise ValueError('Destination must be a repository-relative file')
    data = Path(source).read_bytes()
    if not data:
        raise ValueError('Refusing to save an empty generated file')
    repo = Path(os.environ['GITHUB_WORKSPACE'])
    # checkout supplies authentication; do not embed a token in command arguments.
    def git(*args, **kwargs):
        return subprocess.run(['git', '-C', str(repo), *args], check=True, **kwargs)
    with tempfile.TemporaryDirectory(prefix='generated-', dir=os.environ.get('RUNNER_TEMP')) as temp:
        checkout = Path(temp) / 'checkout'
        for attempt in range(3):
            git('fetch', 'origin', branch)
            revision = git('rev-parse', 'FETCH_HEAD', capture_output=True, text=True).stdout.strip()
            if attempt == 0:
                git('worktree', 'add', '--detach', str(checkout), revision)
            else:
                git('-C', str(checkout), 'reset', '--hard', revision)
            output = checkout / target
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(data)
            git('-C', str(checkout), 'add', '--', str(target))
            diff = subprocess.run(['git', '-C', str(checkout), 'diff', '--cached', '--quiet'])
            if diff.returncode == 0:
                break
            if diff.returncode != 1:
                raise RuntimeError('Unable to inspect generated changes')
            git('-C', str(checkout), '-c', 'user.name=github-actions[bot]', '-c',
                'user.email=41898282+github-actions[bot]@users.noreply.github.com',
                'commit', '-m', f'chore: update {target}')
            pushed = subprocess.run(['git', '-C', str(checkout), 'push', 'origin', f'HEAD:refs/heads/{branch}'])
            if pushed.returncode == 0:
                break
            if attempt == 2:
                raise RuntimeError('Unable to push generated file after 3 attempts')
            time.sleep(2)
        git('worktree', 'remove', str(checkout))


if __name__ == '__main__':
    save(*sys.argv[1:])
