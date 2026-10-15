#!/usr/bin/env python3
"""Compare shared locked packages without changing either checkout.

Usage: python3 scripts/check-dependency-parity.py TEMPLATE SITE [SITE ...]
Arguments are repository roots. Product-only packages remain site-owned.
"""

import argparse
import json
from pathlib import Path
import re
import sys


def mix_packages(root):
    packages = {}
    for line in (root / "platform/mix.lock").read_text().splitlines():
        if line.strip() in ("%{", "}", ""):
            continue
        entry = re.fullmatch(r'\s*"([^"]+)": (\{.*\}),?\s*', line)
        if not entry:
            raise ValueError(f"Unsupported Mix lock entry in {root}: {line}")
        name, value = entry.groups()
        # Compare the complete immutable lock entry, including source and checksum.
        packages[name] = value
    if not packages:
        raise ValueError(f"Empty Mix lock in {root}")
    return packages


def npm_packages(root):
    candidates = [root / "platform", root / "platform/assets"]
    directories = [p for p in candidates if (p / "package.json").exists()]
    if len(directories) != 1:
        raise ValueError(f"Expected one browser package.json in {root}")
    directory = directories[0]
    manifest = json.loads((directory / "package.json").read_text())
    lock = json.loads((directory / "package-lock.json").read_text())
    if lock.get("lockfileVersion") not in (2, 3):
        raise ValueError(f"Unsupported npm lock version in {directory}")
    locked = lock["packages"]
    packages = {}
    for section in ("dependencies", "devDependencies"):
        for name, declared in manifest.get(section, {}).items():
            if locked[""].get(section, {}).get(name) != declared:
                raise ValueError(f"Stale npm lock declaration: {directory}: {name}")
            resolved = locked.get(f"node_modules/{name}", {})
            version = resolved.get("version")
            if not version:
                raise ValueError(f"Missing locked npm version: {directory}: {name}")
            # Shared direct dependencies must use exact, reproducible declarations.
            packages[name] = (declared, version, resolved.get("integrity"))
    return packages


def compare(baseline, candidate, label):
    differences = []
    shared = sorted(baseline.keys() & candidate.keys())
    for name in shared:
        if baseline[name] != candidate[name]:
            differences.append(f"  {label} {name}: differs from template")
        elif label == "npm" and candidate[name][0] != candidate[name][1]:
            differences.append(f"  npm {name}: declaration must pin the locked version")
    return shared, differences


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=Path)
    parser.add_argument("sites", type=Path, nargs="+")
    args = parser.parse_args()
    try:
        baseline_mix = mix_packages(args.template)
        baseline_npm = npm_packages(args.template)
        failed = False
        for site in args.sites:
            common_mix, mix_diff = compare(baseline_mix, mix_packages(site), "Mix")
            common_npm, npm_diff = compare(baseline_npm, npm_packages(site), "npm")
            differences = mix_diff + npm_diff
            if not common_mix or not common_npm:
                differences.append("  No shared packages found; check the supplied roots")
            print(f"{site}: {len(common_mix)} shared Mix, {len(common_npm)} shared direct npm")
            print("\n".join(differences) if differences else "  Versions match template")
            failed |= bool(differences)
        return int(failed)
    except (OSError, ValueError, KeyError) as error:
        print(f"Cannot verify dependency parity: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
