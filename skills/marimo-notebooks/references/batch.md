# Running a notebook from the command line

A marimo notebook is a script. `uv run notebook.py` installs what the header lists and runs
every cell once in dependency order; a cell that raises ends the run with a non-zero exit, so
it is safe in a schedule or a pipeline. Start from
[../assets/batch.py](../assets/batch.py): it passes the gate and shows everything below.

## One notebook, form in the editor, arguments on the command line

Ask which settings should be configurable before changing a notebook to this shape.

```python
@app.class_definition
class Params(BaseModel):                       # pydantic: one source of truth, with types
    rows: int = Field(default=200, description="Rows to generate.")
    rate: float = Field(default=0.5, description="Growth per step, in percent.")
    out: str = Field(default="", description="Where to write the result.")


@app.cell
def _():
    form = (
        mo.md("Generate {rows} rows growing at {rate} percent a step.")
        .batch(rows=mo.ui.slider(10, 1000, value=200, step=10),
               rate=mo.ui.number(0.0, 2.0, value=0.5, step=0.1))
        .form(submit_button_label="Run")
    )
    form
    return (form,)


@app.cell
def _(form):
    if mo.app_meta().mode == "script":
        params = Params(**{key.replace("-", "_"): value for key, value in mo.cli_args().items()})
    else:
        mo.stop(form.value is None, mo.md("Choose settings and press **Run**."))
        params = Params(**form.value)
    return (params,)
```

```bash
uv run notebook.py --rows 400 --rate 0.9 --out growth.parquet
```

- `mo.app_meta().mode` is `"script"` under `uv run` / `python`, `"edit"` in the editor,
  `"run"` as an app.
- `mo.cli_args()` is a dictionary of what followed the file name. The model turns the text
  into the right types and rejects a bad value with a clear message and a non-zero exit.
- Every later cell reads `params`, never the form or the arguments, so both ways of running
  share one path.
- Test with small settings first (`--rows 10`); a fast run that finishes proves the wiring
  before a long one is paid for.
- With `marimo run notebook.py -- --rows 400` or `marimo edit notebook.py -- --rows 400`,
  arguments go after `--`.

## Keys and secrets

Never write a key into a notebook. Read it from the environment, and give the reader a way
to supply it when it is missing:

```python
@app.cell
def _():
    keys = mo.ui.anywidget(EnvConfig(["OPENAI_API_KEY"]))     # from wigglystuff
    keys
    return (keys,)


@app.cell
def _(keys):
    keys.widget.require_valid()             # stops here until every key is present
    api_key = keys.widget.get("OPENAI_API_KEY")
    return (api_key,)
```

Put it at the top. In a batch run it reads the environment and passes straight through.
Pass a dictionary of name to checking function instead of a list to have each key tested as
it is entered.

## Output and logs

- Write results to a path taken from the arguments, and print one summary line at the end;
  a schedule's log should say what happened without opening the notebook.
- `print` and logging go to the terminal in script mode. Progress bars
  (`mo.status.progress_bar`) show as text.
- To keep a rendered copy of each run:
  `uvx marimo export html notebook.py -o runs/today.html --sandbox -- --rows 400`.
- For experiment tracking, log the whole `params` model at the start of the run.

## Layout to preserve

Large notebooks often use columns (`marimo.App(width="columns")`, `@app.cell(column=0)`).
Keep every cell in its column when converting to this shape.

## Sweeps

Keep the sweep outside the notebook: a small launcher script that builds the combinations,
prints them by default (a dry run), and starts one `uv run notebook.py --...` per
combination only when asked (`--launch`). Limit the number (`--count`) and fix the random
choice (`--seed`). The notebook stays a single run that can be tested alone; any service
that can run a uv script can run the sweep. Compare the results afterwards in a notebook
with wigglystuff's `ParallelCoordinates` ([wigglystuff.md](wigglystuff.md)).

## Schedules

Anything that can run a command can schedule a notebook: cron, a CI workflow, a job runner.
The command is `uv run /full/path/notebook.py --arg value`; the header pins what is
installed, so pin versions there (`polars==1.39.0`) when the run must be repeatable.
