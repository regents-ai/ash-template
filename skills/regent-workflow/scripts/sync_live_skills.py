#!/usr/bin/env python3
"""Bring the skills every agent loads up to the template's origin/main.

Agents load the working files of the primary ash-template checkout. That checkout stays
behind main because it holds other sessions' work, so a pushed skill reaches nobody until
its file is written here. Run this after pushing a change under skills/ to main.

It fetches, then writes only working files under skills/, merging in any local edit. It
moves no branch and touches no other file. A file it cannot merge is named and left alone.
"""

import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
TARGET = "origin/main"


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, check=check)


def blob(rev: str, path: str) -> bytes | None:
    shown = git("show", f"{rev}:{path}", check=False)
    return shown.stdout if shown.returncode == 0 else None


def merge(ours: bytes, base: bytes, theirs: bytes) -> bytes | None:
    with tempfile.TemporaryDirectory() as folder:
        paths = []
        for name, text in (("ours", ours), ("base", base), ("theirs", theirs)):
            paths.append(Path(folder, name))
            paths[-1].write_bytes(text)
        merged = subprocess.run(["git", "merge-file", "-p", *map(str, paths)], capture_output=True)
    return merged.stdout if merged.returncode == 0 else None


def main() -> int:
    git("fetch", "-q", "origin", "main")
    tracked = git("ls-tree", "-r", "--name-only", TARGET, "--", "skills").stdout.decode().splitlines()
    written, unmerged = 0, []

    for path in tracked:
        live = REPO / path
        theirs = blob(TARGET, path)
        ours = live.read_bytes() if live.exists() else None
        if ours == theirs:
            continue
        base = blob("HEAD", path)
        text = theirs if ours is None or ours == base else merge(ours, base or b"", theirs)
        if text is None:
            unmerged.append(path)
            continue
        live.parent.mkdir(parents=True, exist_ok=True)
        live.write_bytes(text)
        written += 1

    print(f"{written} written, {len(unmerged)} left to merge by hand")
    for path in unmerged:
        print(f"  {path}")
    return 1 if unmerged else 0


if __name__ == "__main__":
    raise SystemExit(main())
