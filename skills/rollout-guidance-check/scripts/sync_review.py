#!/usr/bin/env python3
"""Package the canonical rollout Skill and root review rules for explicit repositories."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

START = "<!-- BEGIN REGENT ROLLOUT REVIEW -->"
END = "<!-- END REGENT ROLLOUT REVIEW -->"
FILES = ("SKILL.md", "agents/openai.yaml",
         "references/surface-map.md", "references/impact-checklist.md",
         "references/openai-review.md")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def regular_path(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError(f"Refusing symlink in target path: {path}")


def rules(skill_path):
    return f"""{START}
## Code Review Rules

### Human and agent guidance drift

For every code review, read `{skill_path}/SKILL.md` and assess the diff's guidance
impact, even when no prose files changed. Trace affected behavior into public docs,
product/developer Skills, human-to-agent prompts, tooltips and other UI copy,
WebMCP/MCP schemas and descriptions, CLI help/errors/examples, OpenAPI, manifests
and generated or bundled copies. Shared behavior starts in ash-template and its
libraries; inspect affected consumers when available.

Report concrete mismatches introduced or made relevant by this change, with the
failing user/agent action and exact source locations. Distinguish source, packaged,
published and deployed versions; name missing cross-repository or live evidence.
Preserve dated history and avoid cosmetic findings. Do not inflate severity or
claim that no findings proves complete coverage. This is read-only review: never
sign, pay, activate earnings, publish or deploy to test an instruction.
{END}
"""


def sync(repo, source, check):
    repo = repo.absolute()
    regular_path(repo)
    top = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "--show-toplevel"], text=True).strip()
    if Path(top) != repo:
        raise ValueError(f"Not a repository root: {repo}")
    canonical = repo == source.parents[1]
    origin = subprocess.run(["git", "-C", str(repo), "remote", "get-url", "origin"],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout.strip()
    videocontrol = origin.removesuffix(".git").replace(":", "/").endswith("github.com/regents-ai/videocontrol")
    relative = "skills/rollout-guidance-check" if canonical else (
        "review/rollout-guidance-check" if videocontrol else
        ".agents/skills/rollout-guidance-check")
    planned = {}
    retired = []
    if not canonical:
        target = repo / relative
        regular_path(target)
        payload = {f: (source / f).read_bytes() for f in FILES}
        manifest = {"source_repository": "regents-ai/ash-template",
                    "source_path": "skills/rollout-guidance-check",
                    "files": {f: digest(data) for f, data in payload.items()}}
        if target.exists():
            regular_path(target / "SOURCE.json")
            previous = json.loads((target / "SOURCE.json").read_text())
            if previous.get("source_repository") != manifest["source_repository"]:
                raise ValueError(f"Unrecognized package at {target}")
            for path in target.rglob("*"):
                regular_path(path)
                if path.is_file() and path.name != "SOURCE.json":
                    rel = str(path.relative_to(target))
                    if rel not in previous["files"] or digest(path.read_bytes()) != previous["files"][rel]:
                        raise ValueError(f"Preserve independently edited package file: {path}")
                    if rel not in payload:
                        retired.append(path)
        planned.update({target / f: data for f, data in payload.items()})
        planned[target / "SOURCE.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    agents = repo / "AGENTS.md"
    regular_path(agents)
    old = agents.read_text() if agents.exists() else ""
    block = rules(relative)
    if START in old or END in old:
        if old.count(START) != 1 or old.count(END) != 1 or old.index(END) < old.index(START):
            raise ValueError(f"Malformed review block in {agents}")
        before, rest = old.split(START)
        _, after = rest.split(END)
        updated = before + block.rstrip("\n") + after
    else:
        updated = old + ("\n" if old.endswith("\n") else "\n\n" if old else "") + block
    planned[agents] = updated.encode()
    changed = [str(path.relative_to(repo)) for path in retired]
    for path, data in planned.items():
        regular_path(path)
        if not path.exists() or path.read_bytes() != data:
            changed.append(str(path.relative_to(repo)))
    if not check:
        # Recheck the shared instruction file before preserving its surrounding text.
        if (agents.read_text() if agents.exists() else "") != old:
            raise ValueError(f"Instructions changed during preparation: {agents}")
        for path, data in planned.items():
            if str(path.relative_to(repo)) in changed:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        for path in retired:
            path.unlink()
    print(json.dumps({"repo": str(repo), "mode": "check" if check else "sync",
                      "changed_or_stale": changed}))
    return bool(changed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, action="append", required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1]
    stale = [sync(repo, source, args.check) for repo in args.repo]
    raise SystemExit(1 if args.check and any(stale) else 0)


if __name__ == "__main__":
    main()
