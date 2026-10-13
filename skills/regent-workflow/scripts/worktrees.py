#!/usr/bin/env python3
"""Foreground Regent worktree quota. Git remains the source of checkout state."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path('/Users/sean/Documents/regent')
STATE = ROOT / '.agent-worktrees.json'
LIMIT = 2


def git(repo, *args):
    return subprocess.run(['git', '-C', str(repo), *args], check=True,
                          capture_output=True, text=True).stdout


def registered(repo):
    return [Path(line[9:]) for line in git(repo, 'worktree', 'list', '--porcelain').splitlines()
            if line.startswith('worktree ')][1:]


def inventory(state):
    counts = {owner: [] for owner in state['owners']}
    unknown = []
    for repo in state['repos']:
        for path in registered(repo):
            owner = state['paths'].get(str(path))
            if owner in counts:
                counts[owner].append(str(path))
            else:
                unknown.append(str(path))
    return counts, unknown


def create(state, owner, repo, name, branch, ref, dry_run=False):
    repo = repo.resolve()
    if owner not in state['owners']:
        raise ValueError('Unknown owner. Sean must register a stable owner before creation.')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}', owner):
        raise ValueError('Owner ID must contain only letters, numbers, hyphens or underscores.')
    if str(repo) not in state['repos'] or str(repo) not in state['owners'][owner]['repos']:
        raise ValueError('Repository is not assigned to this owner.')
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}', name):
        raise ValueError('Use a short checkout name containing letters, numbers, hyphens or underscores.')
    counts, unknown = inventory(state)
    if unknown:
        raise ValueError('Unassigned Git registrations exist. Reconcile ownership before creating.')
    limit = state['owners'][owner].get('limit', LIMIT)
    if len(counts[owner]) >= limit:
        raise ValueError(f'{owner} already has {len(counts[owner])} worktrees; maximum is {limit}. '
                         'Preserve and retire an old checkout first, or reuse it.')
    path = ROOT / 'worktrees' / owner / name
    if not path.resolve().is_relative_to((ROOT / 'worktrees').resolve()):
        raise ValueError('Destination follows a link outside the worktree folder.')
    if path.exists() or path.is_symlink():
        raise ValueError('Destination already exists.')
    # Resolve and validate before allocating a checkout; failed Git creation consumes no slot.
    git(repo, 'rev-parse', '--verify', ref + '^{commit}')
    git(repo, 'check-ref-format', '--branch', branch)
    if dry_run:
        return {'would_create': str(path), 'owner': owner, 'count': len(counts[owner])}
    git(repo, 'worktree', 'add', '-b', branch, str(path), ref)
    state['paths'][str(path)] = owner
    save(state)
    return {'created': str(path), 'owner': owner}


def save(state):
    tmp = STATE.with_suffix('.json.tmp')
    tmp.write_text(json.dumps(state, indent=2) + '\n')
    tmp.chmod(0o600)
    tmp.replace(STATE)


def retire(state, path, dry_run=False):
    # Intentionally conservative. Ignored source/settings require the reviewed archive procedure.
    path = path.absolute()
    if str(path) not in state['paths'] or not path.is_relative_to(ROOT / 'worktrees'):
        raise ValueError('Only an owned secondary checkout under worktrees can be retired.')
    if not path.exists() or path.is_symlink():
        raise ValueError('Checkout missing or symlinked; reconcile its registration first.')
    if git(path, 'status', '--porcelain=v1', '--untracked-files=all', '--ignored=matching'):
        raise ValueError('Checkout contains changes or ignored files; preserve and inspect them first.')
    if any(p.is_relative_to(path) for repo in state['repos'] for p in registered(repo)
           if p != path):
        raise ValueError('Nested registered checkout; retire it separately first.')
    output = subprocess.run(['lsof', '-n', '-P', '-Fpn'], capture_output=True, text=True).stdout
    if any(line.startswith('n' + str(path) + '/') or line == 'n' + str(path)
           for line in output.splitlines()):
        raise ValueError('A process has files or its working directory in this checkout.')
    raw_admin = Path(git(path, 'rev-parse', '--git-dir').strip())
    admin = (raw_admin if raw_admin.is_absolute() else path / raw_admin).resolve()
    metadata = set()
    # Include build/dependency links: a running app can resolve them only on its next request.
    for repo in state['repos']:
        for other in [Path(repo), *registered(repo)]:
            if other == path or not other.exists():
                continue
            for base, dirs, files in os.walk(other, followlinks=False):
                parent = Path(base)
                if '.git' in dirs:
                    target = (parent / '.git').resolve()
                    metadata.add(target)
                    if target.is_relative_to(path) or target.is_relative_to(admin):
                        raise ValueError('Another checkout depends on this checkout\'s Git metadata.')
                dirs[:] = [d for d in dirs if d != '.git']
                for item in dirs + files:
                    link = Path(base) / item
                    if link.is_symlink() and (link.resolve().is_relative_to(path) or link.resolve().is_relative_to(admin)):
                        raise ValueError('Another checkout depends on a symlink into this checkout.')
                    if item == '.git' and link.is_file():
                        if link.is_symlink():
                            raise ValueError('Inspect a linked Git metadata pointer before retirement.')
                        marker = link.read_text().strip()
                        if not marker.startswith('gitdir: '):
                            raise ValueError('Inspect an unrecognized Git metadata pointer before retirement.')
                        raw = Path(marker[8:])
                        target = (raw if raw.is_absolute() else parent / raw).resolve()
                        metadata.add(target)
                        if target.is_relative_to(path) or target.is_relative_to(admin):
                            raise ValueError('Another checkout depends on this checkout\'s Git metadata.')
    for directory in metadata:
        for base, dirs, files in os.walk(directory, followlinks=False):
            parent = Path(base)
            if parent.name == 'objects':
                dirs[:] = [d for d in dirs if d == 'info']
            if parent.name != 'info' or parent.parent.name != 'objects' or 'alternates' not in files:
                continue
            alternate = parent / 'alternates'
            if alternate.is_symlink():
                raise ValueError('Inspect linked Git object references before retirement.')
            if alternate.is_relative_to(admin) or alternate.is_relative_to(path):
                continue
            for line in alternate.read_text().splitlines():
                raw = Path(line)
                target = (raw if raw.is_absolute() else parent.parent / raw).resolve()
                if target.is_relative_to(path) or target.is_relative_to(admin):
                    raise ValueError('Another checkout borrows Git objects from this checkout.')
    if dry_run:
        return {'would_retire': str(path)}
    # Include this checkout's HEAD explicitly, including a detached, unpublished tip.
    head = git(path, 'rev-parse', 'HEAD').strip()
    common = git(path, 'rev-parse', '--git-common-dir').strip()
    backup = ROOT / 'backups' / 'agent-worktrees'
    backup.mkdir(parents=True, exist_ok=True)
    backup.chmod(0o700)
    repo_name = Path(common).parent.name
    bundle = backup / (repo_name + '-' + head + '.bundle')
    if not bundle.exists():
        git(path, 'bundle', 'create', str(bundle), '--all', 'HEAD')
    git(path, 'bundle', 'verify', str(bundle))
    if head not in {line.split()[0] for line in git(path, 'bundle', 'list-heads', str(bundle)).splitlines()}:
        raise ValueError('Retirement backup does not contain this source tip.')
    git(path, 'worktree', 'remove', str(path))
    del state['paths'][str(path)]
    save(state)
    return {'retired': str(path), 'recovery_bundle': str(bundle)}


def hook(payload):
    name = payload.get('tool_name', '')
    short_name = name.rsplit('__', 1)[-1].rsplit('.', 1)[-1]
    # Source edits and reads can quote shell commands without executing them.
    if short_name in {'apply_patch', 'Edit', 'Write', 'Read', 'MultiEdit', 'Glob', 'Grep'}:
        return
    args = payload.get('tool_input', {})
    command = args.get('command', args.get('cmd', '')) if isinstance(args, dict) else ''
    if not isinstance(command, str):
        command = ''
    cwd = str(payload.get('cwd', ''))
    in_workspace = cwd == str(ROOT) or cwd.startswith(str(ROOT) + '/') or str(ROOT) in command
    if not in_workspace:
        return
    # Block normal raw creation routes. The foreground command performs the locked check.
    raw_add = bool(re.search(r'\bworktree\s+add\b|\b(?:git|gh)\b[^\n;]*\bclone\b', command))
    app_add = 'create_worktree' in name or 'restore_worktree' in name
    if isinstance(args, dict):
        target = args.get('target', {})
        target_environment = target.get('environment', {}) if isinstance(target, dict) else {}
        environment = args.get('environment', target_environment)
        app_add = app_add or (short_name in {'create_thread', 'fork_thread'} and
                             isinstance(environment, dict) and environment.get('type') == 'worktree')
        # A local handoff can allocate a fresh managed checkout without an owner ID.
        app_add = app_add or short_name == 'handoff_thread'
    guarded_add = 'worktrees.py' in command and bool(re.search(r'\badd\s', command))
    if guarded_add and not raw_add:
        session = payload.get('session_id')
        claimed = re.search(r'--owner(?:=|\s+)[\x22\x27]?([a-zA-Z0-9_-]+)', command)
        if session and claimed:
            with STATE.with_suffix('.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                state = json.loads(STATE.read_text())
                sessions = state.setdefault('sessions', {})
                owner = claimed.group(1)
                if owner in state['owners'] and sessions.get(session, owner) == owner:
                    if session not in sessions:
                        sessions[session] = owner
                        save(state)
                    return
        raw_add = True
    if not raw_add and not app_add:
        return
    reason = ('Regent limits each stable agent to two worktrees across repositories. '
              'Use ' + str(Path(__file__).resolve()) + ' add with your existing owner, '
              'or reuse/preserve and retire an old checkout. A session cannot change owners; '
              'raw creation and cloning are blocked.')
    if payload.get('hook_event_name') == 'pre_tool_call':
        print(json.dumps({'action': 'block', 'message': reason}))
    else:
        print(json.dumps({'hookSpecificOutput': {'hookEventName': 'PreToolUse',
                          'permissionDecision': 'deny', 'permissionDecisionReason': reason}}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('hook')
    sub.add_parser('list')
    add = sub.add_parser('add')
    add.add_argument('--owner', required=True)
    add.add_argument('--repo', required=True, type=Path)
    add.add_argument('--name', required=True)
    add.add_argument('--branch', required=True)
    add.add_argument('--ref', required=True)
    add.add_argument('--dry-run', action='store_true')
    remove = sub.add_parser('retire')
    remove.add_argument('path', type=Path)
    remove.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if args.action == 'hook':
        hook(json.load(sys.stdin))
        return
    if args.action == 'list' or args.dry_run:
        state = json.loads(STATE.read_text())
        if args.action == 'list':
            counts, unknown = inventory(state)
            print(json.dumps({'limit': LIMIT, 'owners': counts, 'unassigned': unknown}, indent=2))
        elif args.action == 'add':
            print(json.dumps(create(state, args.owner, args.repo, args.name, args.branch, args.ref, True)))
        else:
            print(json.dumps(retire(state, args.path, True)))
        return
    # One OS lock spans reconciliation, Git creation/removal and owner registration.
    with STATE.with_suffix('.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = json.loads(STATE.read_text())
        if args.action == 'add':
            result = create(state, args.owner, args.repo, args.name, args.branch, args.ref)
        else:
            result = retire(state, args.path)
        print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        if len(sys.argv) > 1 and sys.argv[1] == 'hook':
            print('Regent quota hook failed; repair it before creating checkouts.', file=sys.stderr)
            sys.exit(2)
        # Do not echo Git stderr, which can contain configured credential-bearing URLs.
        print(str(error) if isinstance(error, ValueError) else 'Worktree operation failed; no force used.',
              file=sys.stderr)
        sys.exit(1)
