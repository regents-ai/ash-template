# Working inside a running notebook

`marimo pair` is built into marimo (0.25 and later). It runs Python inside the kernel of a
notebook someone has open, and its "code mode" is the only way to change that notebook's
cells. The flow below was run end to end against marimo 0.25.2.

`uvx marimo pair --help` prints the current rules and is the source of truth; read it once
per session. `uvx marimo pair docs <topic>` prints longer guidance for `gotchas`,
`notebook-improvements` and `rich-representations`.

## Rules

1. **Do not edit the notebook file while it is open.** Code mode is the only write path; the
   kernel saves the file itself after each change.
2. **Cells are the unit of work.** The scratchpad (the code you send) is temporary: names it
   defines are gone after the call. Only cells created or edited through code mode persist.
3. **A new or edited cell does not run by itself.** Call `run_cell` after `create_cell` or
   `edit_cell`.
4. **Use `async with cm.get_context() as ctx:`** and do not `await` the cell methods
   (`create_cell`, `edit_cell`, `run_cell`, `delete_cell`, `set_ui_value`) or call
   `asyncio.run`; the kernel already runs a loop. Only `ctx.screenshot` is awaited.
5. **Install packages with `ctx.packages.add("name")`**, not `pip` or `uv add`. It changes the
   person's project, so confirm first when they did not ask for it.
6. **Ask before `delete_cell`**; it drops that cell's variables. If an empty cell exists, edit
   it instead of creating another.
7. **`marimo._code_mode` is private and unversioned.** Never import it in a notebook cell. If
   a call fails, run `help(cm)` in the session and use what it prints.

## Find the session

```bash
uvx marimo pair notebook list                              # servers started with --no-token
uvx marimo pair notebook list --url http://127.0.0.1:2718  # a named server
```

It prints each notebook's path, server `url` and `session_id`. Keep the `session_id`: it does
not change when the page reloads or the notebook is renamed. If a later command reports an
unknown session, the notebook was closed or restarted: list again. If one notebook has several
sessions, ask which one. For a server that needs a token, pass `--token-file <path>` (the
path, never the token) to every command.

**No session listed?**

- No server: start one in the background, `uvx marimo edit notebook.py --no-token`, adding
  `--sandbox` when the file has a `# /// script` header so its packages are installed.
- A server but no session: **a headless server has no session until a browser opens the
  notebook.** Ask the person to open the URL, then list again.

## Read, then change

```bash
uvx marimo pair execute --url <URL> --session <SESSION> --code-file - <<'PY'
import marimo._code_mode as cm
async with cm.get_context() as ctx:
    for cell in ctx.cells:
        print(cell.id, cell.status, bool(cell.errors), cell.code[:60].replace("\n", " "))
PY
```

Cells can be `stale` right after a notebook opens; a stale cell has not run, so its variables
may not exist yet. Run what you need (`ctx.run_cell(cell_id)`), or run the cell you add: its
ancestors run first.

```bash
uvx marimo pair execute --url <URL> --session <SESSION> --code-file - <<'PY'
import marimo._code_mode as cm
async with cm.get_context() as ctx:
    cid = ctx.create_cell('residual = float((df["y"] - estimate * df["x"]).std())\nresidual')
    ctx.run_cell(cid)
    print(cid)
PY
```

Then confirm it, in a second call (the first must finish before the cell has a result):

```bash
uvx marimo pair execute --url <URL> --session <SESSION> --code-file - <<'PY'
import marimo._code_mode as cm
print(residual)                       # notebook variables are plain names in the scratchpad
async with cm.get_context() as ctx:
    cell = ctx.cells["<CELL_ID>"]
    print(cell.status, cell.errors, [o.data for o in cell.console_outputs])
PY
```

Done means `cell.status == "idle"` and `cell.errors == []`, and the value is what you expected.

## The interface

| Call | Does |
|---|---|
| `ctx.cells` | every cell: `.id`, `.code`, `.status`, `.errors`, `.console_outputs`; index by position, id or name |
| `ctx.create_cell(code, *, before=None, after=None, hide_code=True, name=None, column=None)` | adds a cell (at the end by default) and returns its id. **`hide_code` defaults to True**: pass `hide_code=False` for code the reader should see. |
| `ctx.edit_cell(target, code=None, *, hide_code=None, name=None, ...)` | changes a cell's code or options |
| `ctx.run_cell(target)` | runs it and what depends on it |
| `ctx.move_cell(target, before=..., after=...)` | reorders |
| `ctx.delete_cell(target)` | removes it and its variables |
| `ctx.packages.add("polars>=1")` | queues an install, applied when the block exits |
| `ctx.set_ui_value(element, value)` | sets a widget's value as if the reader had, so dependents re-run |
| `await ctx.screenshot(target, save_to="/tmp/cell.png")` | a picture of one cell's output, or of the notebook with no target (needs playwright; see below) |
| `ctx.graph` | the dependency graph; `ctx.graph.cells[cid].defs` is what a cell owns |

Setting a widget's attribute directly (`slope.widget.amount = -3`) changes the widget but does
**not** re-run the cells that read it. Use `ctx.set_ui_value`, or call the function under test
with the value you want.

## Seeing your work

After a change that affects what the reader sees, take a screenshot of that cell and look at
it before reporting. `screenshot` is the one `ctx` method that is awaited:

```python
async with cm.get_context() as ctx:
    await ctx.screenshot("<CELL_ID>", save_to="/tmp/cell.png")
```

- It needs `playwright` and its Chromium in the notebook's environment. Without them the call
  fails with the two install commands. Installing a browser into someone's project is their
  call: ask, or use the fallback.
- The file is written on the machine the kernel runs on; you can read it only if you share
  its filesystem.
- Fallback: `uvx marimo export html notebook.py -o /tmp/out.html --sandbox` renders the saved
  file (not the live widget state) to a page you can open.

## Things that go wrong

- **`Multiply-defined names`**: your new cell defines a name another cell owns, an import
  included. Use a new name, an underscore name for a throwaway, or edit the owning cell.
- **`NameError` on an underscore name**: it belongs to another cell. Rename it or merge the
  cells.
- **The setup cell** is named `"setup"`, runs first, and may not read any other cell's names.
  `create_cell(..., name="setup")` raises if one exists; `edit_cell("setup", code=...)`
  instead. Keep it to imports so that editing it does not re-run the whole notebook.
- **A package added mid-session is not seen**: some libraries cache what was installed when
  they were imported. Restarting the kernel is the person's call; say so.
- **`inspect.getsource()` on a method** keeps its indentation; `textwrap.dedent` it before
  `ast.parse`.

## Lens: the person points, you answer

[marimo-lens](https://github.com/marimo-team/marimo-lens) (a separate package, installed in
the notebook's environment) lets the person mark a point or region on a chart or table and
leave a note; the agent receives the mark, the note, an image and the code behind it, and
replies with a summary of what it changed. Use it when it is already in the notebook or the
person asks to "point at" things; its own skill ships in that repository
(`skills/marimo-lens/SKILL.md`). It needs the live session above.
