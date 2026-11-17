# wigglystuff

A library of anywidgets made for marimo notebooks. Checked against **wigglystuff 0.5.40**
(needs Python 3.11 or later). Working examples of the main shapes are in
[../assets/wigglystuff_patterns.py](../assets/wigglystuff_patterns.py).

## Before using a widget

The website (https://koaning.github.io/wigglystuff/) documents the development branch, which
is ahead of the published release. **Ask the installed release, not the website:**

```bash
uv run scripts/widget_api.py              # every name in the installed release
uv run scripts/widget_api.py ChartPuck    # constructor, traits you can read, methods, docstring
```

Documented on the website but **not in 0.5.40**: `FitProgress` (live progress for scikit-learn
searches), `PairPlot`, `shape_display`, `WidgetFlow`. Do not use them until `widget_api.py`
lists them. Two more to know:

- `ChartSelect` still ships, but marimo now has the same thing built in: prefer
  `mo.ui.matplotlib(ax)`.
- `WidgetDAG` is deprecated in favour of the unreleased `WidgetFlow`; avoid it in new work.

The website's machine-readable index is https://koaning.github.io/wigglystuff/llms.txt, with
one Markdown page per widget under `/reference/<name>.md`. Use it for ideas and examples,
then confirm the names with `widget_api.py`.

## The pattern

```python
with app.setup:
    import marimo as mo
    from wigglystuff import TangleSlider


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

1. Add `wigglystuff` to the header. Some widgets need more: `matplotlib` for the `Chart*`
   widgets, `scipy` for `TangleDistribution`, `wigglystuff[otel]` or `wigglystuff[weave]`
   for `TraceView` sources.
2. Wrap in `mo.ui.anywidget(...)`. Unwrapped, it displays but nothing re-runs.
3. Show it (last expression, inside `mo.md`, or in a stack) in the cell that creates it.
4. Read it in another cell, in one of three ways:
   - **a trait, on the wrapper**: `cups.amount`, `puck.x`, `order.value`
   - **all traits as a dictionary**: `cups.value["amount"]`
   - **a method or property, on `.widget`**: `bell.widget.ppf(0.9)`,
     `runs.widget.filtered_as_polars`

`Hint` and `FloatingPanel` are plain wrappers around something else and are not passed to
`mo.ui.anywidget`.

## Live values and committed values

Dragging sends a stream of values. Widgets built for dragging expose both:

| Widget | While dragging | After release |
|---|---|---|
| `TangleSlider` | `amount` | `committed_amount` |
| `TangleLatex`, `TangleFunction`, `FormulaDAG` | `values` | `committed_values` (`FormulaDAG` also `outputs` / `committed_outputs`) |
| `TangleDistribution` | `live_params` | `params` |

Read the live one for cheap things the reader should see move (a number in a sentence, a
small chart). Read the committed one for anything slow (a model fit, a query), so it runs
once when the reader lets go. All of them also have `dragging`.

## Catalog by job

What to read is a trait unless marked `.widget`.

### Numbers in prose and formulas

| Widget | For | Read |
|---|---|---|
| `TangleSlider(amount, min_value, max_value, step, prefix, suffix, digits)` | a draggable number inside a sentence | `amount`, `committed_amount` |
| `TangleChoice(choices)` / `TangleSelect(choices)` | a clickable word that cycles / a small menu | `choice` |
| `TangleDistribution(distribution, params, bounds, template)` | a number with its uncertainty, drawn as a curve; names follow scipy (`"norm"`, `"beta"`, ...) | `params`, `live_params`; `.widget.mean`, `.sd`, `.pdf(x)`, `.cdf(x)`, `.ppf(q)`, `.sample(n)` |
| `TangleLatex(latex, parameters, notes)` | a formula whose numbers drag, with notes pointing at each part | `values`, `committed_values`, `hovered` |
| `TangleFunction(fn, params)` | a Python function shown with draggable arguments | `values`, `committed_values` |
| `FormulaDAG(formulas, parameters, notes)` | several formulas that feed each other, with their results | `values`, `outputs`, `committed_outputs`, `selected`; `.widget.upstream(name)`, `.downstream(name)` |
| `FormulaAnimation(steps)` | a derivation revealed step by step | `step` |

### Points and regions on a chart

| Widget | For | Read |
|---|---|---|
| `ChartPuck(fig, x, y)` or `ChartPuck.from_callback(...)` | draggable points on a matplotlib figure | `x`, `y` (**lists**, one entry per puck: `puck.x[0]`) |
| `ChartMultiSelect(fig, n_classes)` | paint several labelled regions | `selections`; `.widget.get_labels(x, y)`, `.get_mask(...)` |
| `Slider2D(x, y, x_bounds, y_bounds)` | one point in a square | `x`, `y` |
| `HeatmapSelect(image, x_range, y_range)` | hover or pin a cell of a heatmap | `hover_cell`, `pinned_cell`; `.widget.selection` |
| `RidgelineChart(df)` | stacked distributions, click one | `selected_index`, `selected_row` |
| `CubeWidget(x_axis, y_axis, z_axis)` | pick a point, line or plane in three dimensions | `point`, `line`, `plane` |

`from_callback` takes a function that draws the figure from the current position, so the
picture follows the drag without a round trip through other cells.

### Editing structures

| Widget | For | Read |
|---|---|---|
| `Matrix(matrix or rows/cols, min_value, max_value, step, row_names, col_names, mirror, triangular)` | a small matrix of draggable numbers | `matrix` (list of lists; `np.array(m.matrix)`) |
| `SortableList(value, addable, removable, editable)` | reorder, add, rename items | `value` |
| `CurveEditor(points, curve)` / `BezierCurve(points)` | shape a curve by its control points | `points`, `samples`, `x`, `y`, `t` |
| `EdgeDraw(names, directed)` | draw links between named nodes | `links`; `.widget.get_adjacency_matrix()`, `.has_cycle()` |
| `GraphWidget(nodes, edges)` | a graph to select from and edit | `nodes`, `edges`, `selected_nodes`, `selected_edges` |
| `GridDraw(rows, cols)` | dots and lines on a grid | `dots`, `lines` |
| `ColorPicker(color)` | a colour | `color`; `.widget.rgb` |

### Drawing data

| Widget | For | Read |
|---|---|---|
| `ScatterWidget()` | paint points in classes to make a toy dataset | `.widget.data_as_polars`, `.data_as_pandas`, `.data_as_X_y` |
| `SplineDraw(spline_fn)` | paint points and see a fitted curve | `.widget.data_as_polars`, `.curve_as_numpy` |
| `Paint(height, width)` | freehand drawing | `.widget.get_pil()`, `.get_base64()` |
| `Excalidraw(scene)` | a whiteboard | `scene`; `.widget.get_pil()`, `.save(path)` |

### Sifting many rows or runs

| Widget | For | Read |
|---|---|---|
| `ParallelCoordinates(data, color_by, color_map, ignore)` | brush ranges on many columns at once (experiment results) | `filtered_uids`, `selected_uids`; `.widget.filtered_as_polars`, `.filtered_as_pandas`, `.selected_data` |
| `Treemap.from_dataframe(...)` / `from_records` / `from_paths` | nested sizes | `selected_path`, `clicked_path`, `hovered_path` |
| `NestedTable.from_dataframe(...)` / `from_records` / `from_paths` | a collapsible table with shares | `selected_path`, `expanded_paths` |
| `TextCompare(text_a, text_b)` | shared passages in two texts | `matches`, `selected_match` |
| `ScatterLog(...)` then `.widget.append(...)` | a scatter that grows as a loop runs | `.widget.data` |

### Watching code and systems run

| Widget | For | Read |
|---|---|---|
| `StateViewer(search_func, view_func, args=...)` | step through an algorithm's states (a search, a sort) with a picture per step | `step`; `.widget.n_steps`, `.current`, `.state` |
| `LiveEdit(code, args=...)` or `inspect_run(fn, *args)` | a function with each line's values shown beside it | `trace`, `code` |
| `AsyncFlow()` | a timeline of async tasks | `events`; `.widget.run(...)`, `.trace(...)` |
| `TraceView.from_otlp(...)` / `from_spans` / `from_weave` | an OpenTelemetry trace as a timeline (agent and API calls) | `selected_span_id`; `.widget.selected_span` |
| `ModuleTreeWidget(module)` | the layers and sizes of a PyTorch model | `.widget.total_param_count` |
| `ApiDoc(obj)` | an object's documentation as a panel | `.widget.to_markdown()` |

### Stepping and scrubbing

| Widget | For | Read |
|---|---|---|
| `PlaySlider(value, min_value, max_value, step, interval_ms, loop)` | a slider with a play button | `value`, `playing` |
| `HoverSlider(start, stop, step)` | a value that follows the pointer, and one that sticks on click | `hover_value`, `value`, `hovering` |
| `FramePlayer(frames)` | play a list of images or figures | `value` (the frame index); `.widget.n_frames` |
| `CircularSlider`, `CircularRangeSlider`, `Knob`, `Fader` | dials; `Knob`, `Fader` and `MidiButton` can be driven by a MIDI controller | `value` |

### Guiding the reader

| Widget | For |
|---|---|
| `Hint(target, note, side="right")` | a hand-drawn arrow and note beside a widget, saying what to try |
| `CellTour(steps)` / `DriverTour(steps)` | a guided walk through the notebook's cells |
| `FloatingPanel(child, corner=..., title=...)` / `Pip(child)` | keep a control or chart pinned on screen while scrolling |
| `CopyToClipboard(text_to_copy)` | a copy button |
| `ProgressBar(value, max_value)` | a bar you update from a loop |

### Bringing other things in

| Widget | For |
|---|---|
| `EnvConfig(["OPENAI_API_KEY"])` | ask for keys without putting them in the file; `.widget.require_valid()` stops until they are set, `.widget.get(name)` reads one. In a batch run it reads the environment. |
| `AltairWidget(chart)` | an Altair chart that updates in place instead of redrawing |
| `ObservablePlot(code, variables)`, `EsmWidget(code, data)`, `ManimWeb(code)` | Observable Plot, any small JavaScript module, or a Manim animation, inline |
| `ThreeWidget(data=...)` | a 3D scatter |
| `HoverZoom(image)` | a magnifier over an image |
| `Neo4jWidget(driver)` | browse a Neo4j graph |
| `WebcamCapture`, `WebkitSpeechToTextWidget`, `KeystrokeWidget`, `GamepadWidget`, `AnnotationWidget` | camera, speech, keys, a game controller, and fast labelling with any of them |
| `ImageRefreshWidget`, `HTMLRefreshWidget` | an image or HTML that a loop replaces in place |
| `forecast_chart(df, date_col, value_col)` | a ready-made trend and projection chart (a function, not a widget) |

## Traps

- **Reading in the cell that created it** never updates. Same rule as `mo.ui`.
- **`ChartPuck.x` and `.y` are lists** even with one puck.
- **Changing a trait from Python** (`w.widget.amount = 5`) moves the widget but does not
  re-run the cells that read it. In a live session use `ctx.set_ui_value`
  ([live-sessions.md](live-sessions.md)).
- **A matplotlib figure passed to a `Chart*` widget is drawn once** into a picture. To change
  the picture as the reader drags, use `from_callback`, or rebuild the widget in a cell that
  depends on the inputs.
- **Close figures you hand over** (`plt.close(fig)`) so they are not shown twice.
- **Browser notebooks**: most widgets work; those needing a server-side package that has no
  browser build (Neo4j, PyTorch) do not. Run the gate with `--wasm`.
- **Do not copy an example from the website without checking** its names against the
  installed release.

## Ideas that work well

Patterns from the library's own demonstrations:

- A sentence with draggable numbers above the chart they drive (`TangleSlider`).
- An estimate that carries its uncertainty: "delivery takes {`TangleDistribution`} days",
  then `.widget.ppf(0.9)` for the worst case.
- A formula with a note on each term, dragged to see the curve respond (`TangleLatex`);
  heavy work reads `committed_values`.
- Place the centres yourself: `ChartPuck` on a scatter, clustering re-run from the puck
  positions.
- Results of a sweep in `ParallelCoordinates`, brushed to the good runs, the survivors shown
  in a table from `.widget.filtered_as_polars`.
- An algorithm played like a film: `StateViewer` over a search, with a `view_func` that
  draws each state.
- A `Hint` on the first widget so the reader knows the page is interactive.
