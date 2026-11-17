# Sharing a notebook

Pick by who will read it and whether they need it to respond.

| The reader needs | Use | Python runs |
|---|---|---|
| A live app with the code hidden | `marimo run` | on your server |
| A page that responds, with no server | `marimo export html-wasm` | in the reader's browser |
| A fixed record of one run | `marimo export html` (or `pdf`) | once, when exported |
| To open it from a GitHub link | a molab link | on molab, or in the browser |
| A chosen set of outputs as a dashboard | marimo-studio | once, when built |
| A release that must be provably complete | marimo-export | once, when built |
| A team's shared, running notebooks | a hub (Keyfleet, marimohub) | on the hub |
| It in another format | `marimo export ipynb | md | script` | not at all |

Run the gate first, whatever the route. The commands marked "ran" were run against
marimo 0.25.2 on this skill's template; the rest are from each tool's own documentation.

## As an app

```bash
uvx marimo run notebook.py --sandbox --headless --port 8080 --host 0.0.0.0
```

Read-only; code is not sent to the browser unless `--include-code` is passed. Set a password
with `--token-password-file <path>` when it is reachable by others. Arguments for the
notebook go after `--`. Arrange the page with the layout helpers
([interface.md](interface.md)); `mo.sidebar` and `mo.routes` exist for apps.

## As a fixed page (ran)

```bash
uvx marimo export html notebook.py -o out.html --sandbox
```

Runs the notebook and writes one file with every output. Widgets are shown as they were;
they do not respond. This is also the quickest way to look at your own work without a live
session. `--no-include-code` hides the code.

PDF: `uvx marimo export pdf notebook.py -o out.pdf` needs `nbformat` and `nbconvert` and a
Chromium for the default route; `--as=slides` makes slides; `--no-include-inputs` leaves the
code out.

## In the reader's browser (ran)

```bash
scripts/verify.sh notebook.py --wasm
uvx marimo export html-wasm notebook.py -o site --mode run --sandbox   # a folder to host
uvx marimo export html-wasm notebook.py -o one.html --single-file      # one file, opened directly, needs internet
```

`--mode edit` lets the reader change the code. `--show-code` shows it in run mode. The folder
must be served over HTTP (any static host; `--include-cloudflare` adds the files for
Cloudflare). `--offline` bundles the Python runtime so nothing is fetched from elsewhere.

What changes in the browser:

- **Packages** come from the header, and each must have a pure-Python or browser build. The
  check `--select MW` (the gate's `--wasm`) reports imports, system calls and packages that
  cannot work. A warning that a package "is not bundled" (wigglystuff gets one) means it is
  installed when the page opens, not that it fails.
- **No real filesystem, no subprocesses, no environment variables.** Load data over HTTP
  from a host that allows it, or ship it beside the notebook and read it with
  `mo.notebook_location() / "public" / "data.csv"`.
- **About 2 GB of memory, one thread.** Threads and process pools run, but not in parallel.
- **Polars and DuckDB work; PyTorch, TensorFlow and most things with their own compiled
  code do not.**

When a package has no browser build, precompute:

```python
# /// script
# dependencies = [
#     "marimo",
#     "torch; sys_platform != 'emscripten'",
# ]
#
# [tool.marimo.runtime]
# cache_cells = true
# ///
```

```bash
uvx marimo export html-wasm notebook.py -o site --execute
```

The real computation runs once at export and its results travel with the page. For a small
fixed set of inputs (a dropdown, a stepped slider), put `@mo.persistent_cache(method="lazy")`
on the computation so each choice is stored. An input that cannot be listed in advance (a
continuous slider driving a model) cannot be precomputed: serve it as an app.

## molab links

molab opens any notebook in a public GitHub repository:

```
https://molab.marimo.io/github/{owner}/{repo}/blob/{branch}/{path/to/notebook.py}
```

Add `/wasm` to the end to run it in the reader's browser instead of on molab's machines; use
that when replacing an older `marimo.app` link. The badge:

```markdown
[![Open in molab](https://marimo.io/molab-shield.svg)](URL)
```

For a rendered preview before anything runs, commit a session snapshot beside the notebook
(ran):

```bash
uvx marimo export session notebook.py --sandbox      # writes __marimo__/session/notebook.py.json
uvx marimo export thumbnail notebook.py              # the picture used in link previews
```

Editing a README in someone's repository to add a badge is a change to their project: do it
when asked.

## Other formats (ran, except ipynb)

```bash
uvx marimo export md notebook.py -o notebook.md              # Markdown with code fences
uvx marimo export script notebook.py -o flat.py              # one plain script, cells in run order
uvx --with nbformat marimo export ipynb notebook.py -o notebook.ipynb   # needs nbformat
```

## marimo-studio: a view over a notebook

[marimo-studio](https://github.com/marimo-team/marimo-studio) (experimental) arranges chosen
outputs of a notebook into a page (a dashboard or a report) described in a small file, and
builds it to a static site.

```bash
uvx marimo-studio view create dashboard --target notebook.py
uvx marimo-studio view inspect dashboard --target notebook.py
uvx marimo-studio validate dashboard --target notebook.py
uvx marimo-studio view build dashboard --target notebook.py
uvx marimo-studio view export dashboard --target notebook.py --output dist/dashboard
```

The notebook stays the source; the view only names what to show. Give the cells you want to
show names (`@app.cell` on `def revenue_chart():` instead of `def _():`) so the view can
refer to them. Read `uvx marimo-studio --help` before relying on a command; it is changing.

## marimo-export: a release you can verify

[marimo-export](https://github.com/marimo-team/marimo-export) builds a notebook into a
folder from a written specification and can check afterwards that the folder is complete and
unchanged. Use it when the export is a deliverable.

```bash
uv add marimo-export
uv run marimo-export build report.py --spec report.export.yaml --output dist/report
uv run marimo-export verify dist/report
```

Version 0.2.2 pins marimo 0.25.2 exactly, so use it in a project of its own rather than
alongside a newer marimo.

## Hubs

A hub stores notebooks for a group and runs them on its own machines.

**Keyfleet.** Each project in a fleet has its own notebooks. The guide an agent follows is at
https://keyfleet.ai/skill/notebooks.md (list, create, add files, start a run and read its
result, how packages are installed, who may change what). Read it rather than guessing; it
is the source of truth and changes with the product. Two differences from a local notebook:
packages come from a `pyproject.toml` among the notebook's files, and a run is started and
then read back rather than watched.

**marimohub** ([repository](https://github.com/marimo-team/marimohub)), self-hosted:

```bash
mohub login                                        # or: mohub login --device-code, on a remote machine
mohub projects list --all
mohub notebooks list --pid <PROJECT_ID> --all
mohub notebooks deploy --dry-run                   # what would change, from the repository's files
mohub notebooks deploy --notebook revenue
mohub notebooks push --pid <PROJECT_ID> --nid <NOTEBOOK_ID> --root-path apps
```

`mohub notebooks --help` lists the rest; read it before a command you have not used.

It also offers an agent interface with tools to list, read, create, update and search
notebooks and to start, run code in and stop a session.

Rules that hold on any hub:

- **Packages come from the notebook's header**, and a session that is already running does
  not install what was added to the header afterwards. Start a new session.
- **A session waiting for a reader** (marimohub calls it `awaiting_client`) has no kernel to
  talk to until someone opens it in a browser, the same as a headless local server
  ([live-sessions.md](live-sessions.md)).
- **Inside a session the live-session rules apply**: change cells through the session, not
  by overwriting the stored file under it.
- **Saving back is a write to shared work.** Say what you changed, and do not overwrite
  someone else's newer version; get the current one first.
- **Keys and data stay on the hub.** Do not copy a hub's secrets or private data into a
  notebook file or a public export.
