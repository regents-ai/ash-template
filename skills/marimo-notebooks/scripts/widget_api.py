# /// script
# requires-python = ">=3.11"
# dependencies = ["wigglystuff", "marimo"]
# ///
"""Prints what the installed wigglystuff really offers.

    uv run widget_api.py                 every exported name, one line each
    uv run widget_api.py TangleLatex     one widget: constructor, synced traits, methods, docstring
    uv run --with "wigglystuff==0.5.40" widget_api.py   a particular release

wigglystuff's website documents its main branch, which runs ahead of the
release on PyPI, so a widget on the site may not be installable yet. This
reads the installed package instead: if a name is not printed here, it cannot
be imported from that release.
"""

import importlib.metadata
import inspect
import sys

import wigglystuff


def synced_traits(cls) -> list[str]:
    if not hasattr(cls, "class_traits"):
        return []
    return sorted(
        f"{name}: {type(trait).__name__}"
        for name, trait in cls.class_traits().items()
        if trait.metadata.get("sync") and not name.startswith("_") and name not in {"layout", "tabbable", "tooltip"}
    )


def own_members(cls) -> list[str]:
    traits = set(cls.class_traits()) if hasattr(cls, "class_traits") else set()
    return [
        name
        for name, value in vars(cls).items()
        if not name.startswith("_") and name not in traits and (callable(value) or isinstance(value, (property, classmethod, staticmethod)))
    ]


def signature(obj) -> str:
    try:
        return str(inspect.signature(obj))
    except (TypeError, ValueError):
        return "(...)"


def main() -> None:
    names = sorted(
        name for name in dir(wigglystuff) if not name.startswith("_") and not inspect.ismodule(getattr(wigglystuff, name))
    )
    print(f"wigglystuff {importlib.metadata.version('wigglystuff')}: {len(names)} names")

    if len(sys.argv) == 1:
        for name in names:
            first = (inspect.getdoc(getattr(wigglystuff, name)) or "").split("\n")[0]
            print(f"  {name}: {first[:100]}")
        return

    for name in sys.argv[1:]:
        if name not in names:
            print(f"\n{name}: not in this release. Do not use it; pick another widget or ask before pinning a pre-release.")
            continue
        obj = getattr(wigglystuff, name)
        print(f"\n{name}{signature(obj)}")
        if inspect.isclass(obj):
            print("  synced traits (read these from the wrapped widget):")
            for trait in synced_traits(obj):
                print(f"    {trait}")
            members = own_members(obj)
            if members:
                print(f"  methods and properties (on `.widget`): {', '.join(members)}")
        print()
        print(inspect.getdoc(obj) or "(no docstring)")


if __name__ == "__main__":
    main()
