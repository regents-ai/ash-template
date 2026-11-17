# Inputs, layout, charts, tables and SQL

Everything here is in marimo itself (`import marimo as mo`). For the exact arguments of any
element, ask the installed package: `uv run --with marimo python -c "import marimo as mo; help(mo.ui.table)"`.

## Inputs (`mo.ui`)

Create and show the element in one cell; read `.value` in another.

| Job | Element |
|---|---|
| A number | `slider`, `range_slider`, `number` |
| A choice | `dropdown`, `radio`, `multiselect`, `checkbox`, `switch` |
| Text | `text`, `text_area`, `code_editor` |
| A date | `date`, `date_range`, `datetime` |
| A file | `file` (upload), `file_browser` (pick from disk) |
| An action | `button` (with `on_click`), `run_button` (true for one run after a press), `refresh` (a timer) |
| Rows | `table` (selection comes back), `dataframe` (reader builds filters and group-bys), `data_editor` (reader edits cells), `data_explorer` (reader builds a chart) |
| A chart selection | `altair_chart`, `plotly`, `matplotlib` |
| A conversation | `chat` |
| Sound | `microphone` |
| A matrix of numbers | `matrix` |
| Any anywidget | `anywidget(widget)` |
| Several at once | `array([...])`, `dictionary({...})`, `batch`, `form` |

```python
@app.cell
def _():
    species = mo.ui.dropdown(["Adelie", "Gentoo", "Chinstrap"], value="Adelie", label="Species")
    species
    return (species,)
```

**Several inputs, one submit.** `.form()` holds the values back until the reader presses
submit; `.batch()` places named inputs inside prose. Before the first submit the value is
`None`, so stop the reading cell until there is one:

```python
@app.cell
def _():
    settings = (
        mo.md("Train for {epochs} rounds at rate {rate}.")
        .batch(epochs=mo.ui.slider(1, 20, value=5), rate=mo.ui.number(0.001, 1.0, value=0.01))
        .form(submit_button_label="Train")
    )
    settings
    return (settings,)


@app.cell
def _(settings):
    mo.stop(settings.value is None, mo.md("Choose settings and press **Train**."))
    mo.md(f"Training for {settings.value['epochs']} rounds at {settings.value['rate']}.")
    return
```

**A list of inputs made in a loop** goes in `mo.ui.array` or `mo.ui.dictionary`; plain Python
lists of elements do not update.

## Words

```python
mo.md(rf"""
## Result

The slope is **{slope:.2f}** and the fit is $y = {slope:.2f}x$. Change it here: {control}.
""")
```

- f-strings place values and live elements inside the sentence.
- Use a raw string (`r` or `rf`) whenever the text has a backslash; LaTeX always does.
- `mo.callout(mo.md("..."), kind="info")` for a boxed note (`neutral`, `info`, `warn`,
  `success`, `danger`); `mo.stat(value, label=..., caption=...)` for a headline number;
  `mo.mermaid("graph LR; A-->B")` for a diagram; `mo.accordion({"Details": ...})` for
  optional depth; `mo.outline()` for a table of contents.

## Layout

| Helper | Use |
|---|---|
| `mo.hstack([a, b], widths=[1, 2], gap=1, align="center", justify="start")` | side by side |
| `mo.vstack([a, b], gap=1)` | stacked; also the way to show several things from one cell |
| `mo.ui.tabs({"Chart": chart, "Table": table})` | tabs (use `mo.lazy(...)` for a heavy tab) |
| `mo.accordion({...})` | collapsible sections |
| `mo.sidebar([...])` | a side panel when run as an app |
| `mo.carousel([...])` | slides |
| `mo.routes({...})` with `mo.nav_menu` | several pages in one app |

Control beside result is the commonest good layout:
`mo.hstack([mo.vstack([a, b]), chart], widths=[1, 3])`.

## Charts

End the cell with the chart. Never `plt.show()`.

| Library | Plain | With selection sent back to Python |
|---|---|---|
| Altair | the chart object | `mo.ui.altair_chart(chart)`; `.value` is the selected rows as a table |
| Plotly | the figure | `mo.ui.plotly(fig)`; `.value` is the selected points, `.ranges` the box |
| Matplotlib | the figure, the axes, or `plt.gca()` | `mo.ui.matplotlib(ax)`; `.value` is the box or lasso drawn; `mo.mpl.interactive(ax)` for pan and zoom only |

```python
@app.cell
def _(df):
    picker = mo.ui.altair_chart(
        alt.Chart(df).mark_circle().encode(x="x", y="y")
    )
    picker
    return (picker,)


@app.cell
def _(picker):
    mo.stop(len(picker.value) == 0, mo.md("Drag across the chart to select points."))
    picker.value
    return
```

Prefer Altair for anything a reader will select from; Polars and pandas tables both go
straight in. More than about 5,000 rows needs `alt.data_transformers.enable("vegafusion")`
(add `vegafusion` and `vl-convert-python` to the header) or an aggregate first.

## Tables

A dataframe as the last expression is already an interactive table (sort, filter, search,
page, column summaries). Use `mo.ui.table(df, selection="multi")` when later cells need the
selected rows (`.value` is a table of the same kind), with `page_size`, `pagination`,
`format_mapping`, `freeze_columns_left` as needed. GeoPandas tables show their geometry
column and can be downloaded as GeoJSON or GeoParquet.

## SQL

```python
@app.cell
def _(df, minimum):
    large = mo.sql(
        f"""
        SELECT x, y FROM df WHERE y > {minimum.value}
        """
    )
    return (large,)
```

- A SQL cell is a Python cell that calls `mo.sql` with an f-string. DuckDB runs it and can
  query any dataframe in the notebook by its Python name; the result is a table (Polars when
  it is installed, otherwise pandas). The header needs `marimo[sql]`, not plain `marimo`;
  without it the cell fails asking for `sqlglot`.
- A dataframe named after a SQL word (`table`, `order`, `group`) cannot be queried by that
  name. Rename the dataframe.
- Values from widgets go in with `{...}`. They are placed in the text, so only ever from
  widgets with fixed choices or numbers, never free text a stranger typed.
- Another database: create a connection in a cell (`engine = sqlalchemy.create_engine(...)`
  or `duckdb.connect(...)`) and pass `engine=engine`.
- `mo.sql(..., output=False)` hides the result table. No comments inside the query.

## Objects that show themselves

To make your own class display richly, give it `_display_()` returning any marimo or
displayable object (preferred), or `_repr_html_()` / `_mime_()`.
`uvx marimo pair docs rich-representations` has the full order of preference.

## Building a widget of your own

When neither `mo.ui` nor wigglystuff has it, write an anywidget: a Python class with synced
traits and a small JavaScript `render` function, wrapped in `mo.ui.anywidget`. Start from a
similar one in [marimo-team/anywidget-gallery](https://github.com/marimo-team/anywidget-gallery)
(each is one self-contained notebook), and keep the JavaScript in a string or a file beside
the notebook. Do this only when asked or when nothing existing fits.
