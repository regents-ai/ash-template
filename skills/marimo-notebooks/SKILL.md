---
name: marimo-notebooks
description: Create, edit, run, check and share marimo notebooks (reactive Python notebooks stored as plain .py files), including work inside a running notebook through marimo pair, interactive widgets from mo.ui and wigglystuff, batch runs from the command line, and publishing as an app, a static page, a browser (WebAssembly) notebook or to a hub. Use whenever a task touches a marimo notebook, a file containing `import marimo` and `app = marimo.App(`, the `marimo` or `mohub` commands, a notebook on Keyfleet or marimohub, or wigglystuff / anywidget widgets in a notebook; also when asked to explain something with an interactive notebook or to turn an analysis into one.
---

# marimo notebooks

A marimo notebook is a Python file. Each cell is a function; marimo reads which names a cell
uses and which it defines, and re-runs every cell that depends on a name whenever that name's
cell runs. There is no hidden state and no run order to remember, and the same file runs as a
notebook, a script, an app and a module to import from.

Written against **marimo 0.25.2** and **wigglystuff 0.5.40** (November 2026). Both move fast:
when a command or name here is refused, read `marimo <command> --help`, and for a widget run
`scripts/widget_api.py`, before guessing.

## 1. Pick the path first

| Situation | How to change the notebook |
|---|---|
| The notebook is a file and nobody has it open | Edit the `.py` file, then run the gate (section 4). |
| Someone has it open in `marimo edit`, or you were asked to work "in" the notebook | **Never edit the file.** Work through the running session with `marimo pair` ([live-sessions.md](references/live-sessions.md)). The kernel owns the file while it is open and will overwrite or fight your edit. |
| It lives on a hub (Keyfleet, marimohub) | Use that hub's own guide for getting it and saving it back; inside a hub session the rules are the same as a live session ([sharing.md](references/sharing.md)). |
| It is a Jupyter notebook, a Markdown file with `{python}` fences, or a `# %%` script | `uvx marimo convert <file> -o notebook.py`, then treat the result as a file, add the header, and run the gate. Conversion keeps Jupyter's habits (names defined twice, values changed across cells), so expect rule 1 and rule 5 fixes. |

Unsure whether it is open? `uvx marimo pair notebook list` prints every running notebook and
its session. A file edit is safe only when the notebook is not in that list.

## 2. The file

Start from [assets/template.py](assets/template.py). It passes the gate as it stands and shows
every part below.

```python
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "marimo>=0.25.2",
#     "polars>=1",
# ]
# ///

import marimo

__generated_with = "0.25.2"
app = marimo.App(width="medium")

with app.setup:
    import marimo as mo
    import polars as pl


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    # Title
    """)
    return


@app.cell
def _():
    rows = mo.ui.slider(10, 1000, step=10, value=100, label="rows")
    rows
    return (rows,)


@app.function
def squares(n: int) -> pl.DataFrame:
    """A table of the first n squares."""
    return pl.DataFrame({"n": range(n)}).with_columns(square=pl.col("n") ** 2)


@app.cell
def _(rows):
    table = squares(rows.value)
    table
    return (table,)


if __name__ == "__main__":
    app.run()
```

- **Header.** List every package the notebook imports in the `# /// script` block. It is what
  makes `uv run notebook.py`, `--sandbox`, hubs and browser notebooks install the right things.
  An import alone declares nothing.
- **`with app.setup:`** holds the imports, and only imports. It runs before every cell, so
  its names need no cell parameters, and marimo does not re-run the notebook when an
  import-only cell is edited. It cannot use a name from any cell.
- **A cell** is `@app.cell` on `def _(...)`. Its parameters are the names it reads from other
  cells; its `return` tuple is the names it gives them. Keep both true to the body: marimo
  rewrites them on save, and `marimo check --fix` rewrites them for you.
- **`@app.function` / `@app.class_definition`** is one function or class in a cell of its own
  that uses only setup names and other such definitions. It can be imported from the file
  (`from notebook import squares`) and tested with pytest. Put logic worth reusing here and
  keep wiring (widgets, layout, display) in ordinary cells.
- **Options** go on the decorator: `@app.cell(hide_code=True)` for prose and for plumbing a
  reader need not see, `disabled=True`, `column=1` (only with `width="columns"`; keep columns
  as you find them).
- **`marimo.App(...)`** takes `width` (`"compact"`, `"medium"`, `"full"`, `"columns"`),
  `app_title`, `css_file`, `html_head_file`, `layout_file`, `sql_output`.
- Leave `__generated_with` and the closing `if __name__ == "__main__": app.run()` alone.

## 3. The rules that break notebooks

These five cause nearly every failure. [reactivity.md](references/reactivity.md) has the rest,
with the lint code for each.

1. **One cell owns each name.** Defining `df` (or importing `pd`) in two cells is an error.
   Give the second result a new name (`clean = df.drop_nulls()`), or change the owning cell.
2. **Underscore names stay in their cell.** `_tmp` is invisible to other cells. Use it for a
   loop variable or a throwaway figure, not as a way out of rule 1: one or two per cell at
   most. A name another cell reads must not start with an underscore.
3. **Only the last expression shows.** An expression inside `if` or `for` shows nothing. Build
   the value, then end the cell with it: `mo.md("...") if ok else mo.callout("...", kind="warn")`.
   For several things, end with `mo.vstack([...])`.
4. **A widget's value is read in another cell.** Create and show the widget in one cell; use
   `.value` in a later one. Reading it in the cell that made it never updates.
5. **Change a value by making a new one.** marimo does not see `items.append(x)` or
   `obj.field = 1` from another cell. Mutate only inside the cell that created the object.

Do not guard cells with `if data is not None:`; a cell does not run until the names it needs
exist. Do not wrap code in `try/except` to hide errors. Do not reach for `mo.state` unless two
widgets must stay in sync or a callback must accumulate history.

## 4. The gate

Run this before handing any notebook back, and again after every fix:

```bash
scripts/verify.sh notebook.py            # lint, run top to bottom, run its tests
scripts/verify.sh notebook.py --wasm     # also the browser rules, if it will be shared that way
scripts/verify.sh notebook.py -- --n 10  # pass arguments to a batch notebook
```

It builds one throwaway environment from the notebook's own header, so a package the header
forgets fails here. By hand, the same three steps are:

```bash
uvx --with pytest marimo check --strict notebook.py   # add --fix to repair formatting and cell signatures
uv run notebook.py                                    # every cell, in order; a cell that raises exits non-zero
uv run --with pytest pytest notebook.py               # only when it has test_ functions
```

Passing the gate proves it runs, not that it reads well. Then **look at it**: with a live
session take a screenshot of the cell you changed ([live-sessions.md](references/live-sessions.md));
otherwise `uvx marimo export html notebook.py -o out.html --sandbox` and open the page. Check
that the widgets are where the prose says they are and the first screen makes sense on its own.

## 5. Writing a notebook worth reading

The best public notebooks (marimo's own `learn` collection and the ones behind its videos)
share a shape. Follow it unless the person asks otherwise.

- **Open with one hidden-code cell: an H1 title and two or three sentences** saying the
  question the notebook answers. Then alternate: a short prose cell, then the cell it
  introduces.
- **Put the control in the sentence.** `mo.md(f"Set the mean {mean} and the spread {sd}.")`
  reads better than a column of labelled sliders. wigglystuff's Tangle widgets are made for
  this.
- **Every widget changes something visible.** If moving it changes nothing on screen, remove
  it. Show the result directly under the control, or beside it with `mo.hstack`.
- **Hide plumbing, show the idea.** `hide_code=True` on prose, layout and chart-styling cells;
  leave the code visible where the code is the lesson.
- **Maths in `$...$` and `$$...$$`** inside `mo.md(r"""...""")`. Use a raw string whenever
  there is a backslash.
- **Gate slow work behind a button**: `mo.ui.run_button()` plus
  `mo.stop(not run.value, mo.md("Press **Run** to start."))`, and cache what is expensive
  ([reactivity.md](references/reactivity.md)).
- **Keep words plain and direct.** No comments inside Markdown or SQL cells.

## 6. Widgets

Reach for `mo.ui` first; it covers sliders, dropdowns, tables with selection, forms, file
upload, chat, and charts whose selections come back to Python (`mo.ui.altair_chart`,
`mo.ui.plotly`, `mo.ui.matplotlib`). The list and the layout helpers are in
[interface.md](references/interface.md).

Use **wigglystuff** when the idea is clearer with a richer control. Wrap it, show it, read it
in another cell:

```python
@app.cell
def _():
    cups = mo.ui.anywidget(TangleSlider(amount=3, min_value=0, max_value=12, step=1, digits=0, suffix=" cups"))
    mo.md(f"Each day I drink {cups}.")
    return (cups,)


@app.cell
def _(cups):
    mo.md(f"That is **{cups.amount * 365:,.0f}** a year.")
    return
```

| To let the reader... | Use |
|---|---|
| drag a number inside a sentence | `TangleSlider`, `TangleChoice`, `TangleSelect` |
| drag a number that carries its uncertainty | `TangleDistribution` |
| drag the numbers inside a formula, with notes pointing at each part | `TangleLatex`, `FormulaDAG`, `FormulaAnimation` |
| pick a point or region on a chart | `ChartPuck`, `ChartMultiSelect`, `Slider2D`, `HeatmapSelect` |
| edit a matrix, a curve, an order, a graph | `Matrix`, `CurveEditor`, `BezierCurve`, `SortableList`, `EdgeDraw` |
| draw data or a picture | `ScatterWidget`, `SplineDraw`, `Paint`, `Excalidraw` |
| sift many runs or rows | `ParallelCoordinates`, `Treemap`, `NestedTable` |
| watch code run | `StateViewer`, `LiveEdit`, `AsyncFlow`, `TraceView` |
| play through steps or frames | `PlaySlider`, `FramePlayer`, `HoverSlider` |
| be shown what is interactive | `Hint`, `CellTour`, `FloatingPanel` |
| supply keys safely | `EnvConfig` |

[wigglystuff.md](references/wigglystuff.md) has what each returns and the traps;
[assets/wigglystuff_patterns.py](assets/wigglystuff_patterns.py) is a notebook with one
working example of each shape. **The wigglystuff website documents unreleased widgets.**
Before using one you have not used in this session:

```bash
uv run scripts/widget_api.py              # every name in the installed release
uv run scripts/widget_api.py TangleLatex  # its constructor, the traits you can read, its docstring
```

## 7. Which reference to open

| Task | Read |
|---|---|
| Work inside a running notebook; screenshots; packages mid-session | [live-sessions.md](references/live-sessions.md) |
| An error about names, cycles or stale cells; slow notebooks; caching; state; lint codes | [reactivity.md](references/reactivity.md) |
| Choosing and laying out `mo.ui` elements, charts, tables, SQL cells | [interface.md](references/interface.md) |
| wigglystuff: every widget, what to read from it, traps | [wigglystuff.md](references/wigglystuff.md) |
| Run from the command line, with arguments, on a schedule, or as a sweep | [batch.md](references/batch.md) |
| Publish: app, static page, browser notebook, molab link, studio views, verified exports, hubs | [sharing.md](references/sharing.md) |
| Where these rules come from, what was left out, how to refresh this skill | [sources.md](references/sources.md) |

For the exact API of anything in marimo, ask the installed package rather than memory:

```bash
uv run --with marimo python -c "import marimo as mo; help(mo.ui.table)"
uvx marimo pair docs gotchas        # also: notebook-improvements, rich-representations
```
