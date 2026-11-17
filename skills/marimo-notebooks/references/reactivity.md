# Reactivity, errors and slow notebooks

## How a notebook runs

marimo reads each cell without running it and records two sets: the names it **defines** and
the names it **uses**. Those make a graph. When a cell runs, every cell that uses a name it
defines runs after it, in graph order. The order of cells in the file is for the reader only.

Consequences:

- Deleting a cell deletes its names; cells that used them show an error rather than a stale
  value.
- A cell that needs a name which has no value yet does not run. No guard is needed.
- Running as a script (`uv run notebook.py`) runs every cell once, in graph order.

## The rules, with the lint code that catches each

`marimo check` reports these. Breaking rules stop the notebook; fix them first.

| Code | Name | Meaning | Fix |
|---|---|---|---|
| MB001 | unparsable-cells | a cell is not valid as marimo saved it | repair the cell's Python |
| MB002 | multiple-definitions | a name is defined in two cells (imports count) | new name, an underscore name for a throwaway, or edit the owning cell |
| MB003 | cycle-dependencies | cell A needs B and B needs A | merge them, or split the shared part into a third cell |
| MB004 | setup-cell-dependencies | `with app.setup:` uses a name from a cell | setup may hold only self-contained code; move the line into a cell |
| MB005 | invalid-syntax | a syntax error | fix it |
| MR001 | self-import | the notebook imports itself | remove the import |
| MR002 | branch-expression | the value meant to show is inside `if`/`for`/`with` | assign it, end the cell with the name |
| MR003 | reusable-definition-order | an `@app.function` is used before the one it depends on | `marimo check --fix --unsafe-fixes` reorders |
| MR004 | private-import-alias | `import x as _x` hides a module other cells need | import it in setup under its normal name |
| MF001 | general-formatting | cell signatures or returns do not match the body | `marimo check --fix` |
| MF004 | empty-cells | a cell with nothing in it | delete it (`--fix --unsafe-fixes`) |
| MF005 | sql-parse-error | a SQL cell does not parse | fix the query |
| MF007 | markdown-indentation | a Markdown cell's text is indented wrongly | `marimo check --fix` |
| MF002/3/6 | captured output | the notebook printed or logged while being read | usually a missing package in the checking environment; run the check with the notebook's packages (the gate does) |
| MW001-003 | browser rules | an import, system call or package that cannot run in the browser | off by default; `--select MW`; see [sharing.md](sharing.md) |

`--strict` makes warnings fail. `--format json` gives machine-readable output.
`--select MB,MR001` and `--ignore MF004` choose rules.

## Mistakes worth recognising on sight

```python
# Wrong: df defined twice across cells
df = pl.read_csv("data.csv")         # cell A
df = df.drop_nulls()                 # cell B: multiple-definitions

# Right
raw = pl.read_csv("data.csv")        # cell A
df = raw.drop_nulls()                # cell B
```

```python
# Wrong: nothing shows
if ready:
    mo.md("Done")

# Right
mo.md("Done") if ready else mo.md("Waiting")
```

```python
# Wrong: read in the cell that made it; never updates
n = mo.ui.slider(1, 10)
mo.md(f"{n.value}")

# Right: two cells
n = mo.ui.slider(1, 10); n           # cell A, returns (n,)
mo.md(f"{n.value}")                  # cell B, takes n
```

```python
# Wrong: marimo cannot see this from another cell
results.append(score)

# Right
results = [*earlier, score]          # a new name in its own cell
```

```python
# Wrong: every local hidden behind an underscore to dodge rule 1
_df = load(); _clean = _df.drop_nulls(); _fig = plot(_clean); _fig

# Right: real names for what later cells or the reader will want; underscore only for throwaways
clean = load().drop_nulls()
_fig = plot(clean)
_fig
```

Other habits to drop from Jupyter: `plt.show()` (end the cell with the figure or `plt.gca()`),
`display(...)` (end the cell with the value), `global` (never), `from x import *` (never).

## State

Names flowing between cells are the state. `mo.state` is for three cases only: keeping a
history that a callback adds to, keeping two widgets in sync with each other, and a deliberate
loop. If you use it:

```python
get_count, set_count = mo.state(0)                       # one cell
button = mo.ui.button(on_click=lambda _: set_count(lambda n: n + 1))   # another
mo.md(f"Pressed {get_count()} times")                    # a third: re-runs when set_count is called
```

Calling the setter re-runs cells that call the getter, except the cell doing the calling.

## Slow or expensive notebooks

| Need | Use |
|---|---|
| Do nothing until asked | `run = mo.ui.run_button(label="Train")` in one cell; `mo.stop(not run.value, mo.md("Press **Train**."))` as the first line of the slow cell |
| Stop a cell when an input is not ready | `mo.stop(table.value.is_empty(), mo.md("Select rows first."))` |
| Do not repeat a pure computation in this session | `@mo.cache` on the function |
| Do not repeat it across restarts | `@mo.persistent_cache` on the function, or `with mo.persistent_cache("name"):` around a block |
| Show progress | `for x in mo.status.progress_bar(items):`, or `with mo.status.spinner("Loading"):` |
| Render something only when its tab or accordion opens | `mo.lazy(component)` |
| Update a widget continuously without re-running on every pixel | read the committed value, not the live one (wigglystuff exposes both) |
| Stop the whole notebook re-running on each change | runtime setting "on cell change: lazy" (cells are marked stale instead); the person's choice, not a default to set for them |
| Background work | `mo.Thread` (a thread that marimo can stop with its cell) |

`mo.stop(condition, output)` ends the cell there, shows `output`, and holds back every cell
that depends on it. It is the right way to say "not yet"; an `if` around the body is not.

Cache only pure functions: same arguments, same result, no side effects. A cached function
that reads a file or the network needs the thing that changes among its arguments.

## Tests and docs in a notebook

A cell containing only `test_` functions (or `Test` classes) is collected by pytest:
`pytest notebook.py`. With pytest in the environment, marimo also runs those cells in the
editor and shows the result. Test the `@app.function` cells; they import cleanly.

## Settings

Per-notebook settings live in the header:

```python
# /// script
# dependencies = ["marimo"]
#
# [tool.marimo.runtime]
# auto_instantiate = false
# ///
```

Project-wide settings live in `pyproject.toml` under `[tool.marimo]`; a person's own in
`marimo.toml`. `uvx marimo config show` prints what applies, `uvx marimo config describe`
lists every setting. Change a person's settings only when asked.
