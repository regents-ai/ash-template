"""Local acceptance runner using the existing Regents CLI and this source manifest.

This is not a released CLI. Pass the isolated local site's --base-url explicitly.
"""
import json
from pathlib import Path

from regents_cli.platforms import Platform
from regents_cli.runner import platform_group

if __name__ == "__main__":
    manifest = Path(__file__).resolve().parents[1] / "cli" / "commands.json"
    platform_group(Platform.parse(json.loads(manifest.read_text()))).main()
