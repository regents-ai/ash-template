# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "marimo[sql]>=0.25.2",
#     "polars>=1",
#     "pydantic>=2",
# ]
# ///

import marimo

__generated_with = "0.25.2"
app = marimo.App(width="medium")

with app.setup:
    import marimo as mo
    import polars as pl
    from pydantic import BaseModel, Field


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    # Growth table

    One notebook, two ways to run it. Opened in the editor, the settings come from the form
    below. Run from the command line, they come from arguments:
    `uv run batch.py --rows 400 --rate 0.9 --out growth.parquet`.
    """)
    return


@app.class_definition
class Params(BaseModel):
    rows: int = Field(default=200, description="Rows to generate.")
    rate: float = Field(default=0.5, description="Growth per step, in percent.")
    out: str = Field(default="", description="Where to write the result (a .parquet path).")


@app.cell
def _():
    form = (
        mo.md("Generate {rows} rows growing at {rate} percent a step.")
        .batch(
            rows=mo.ui.slider(10, 1000, value=200, step=10),
            rate=mo.ui.number(0.0, 2.0, value=0.5, step=0.1),
        )
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


@app.function
@mo.cache
def growth(rows: int, rate: float) -> pl.DataFrame:
    """A table of compounding growth."""
    return pl.DataFrame({"step": range(rows)}).with_columns(
        value=(1 + rate / 100) ** pl.col("step")
    )


@app.cell
def _(params):
    curve = growth(params.rows, params.rate)
    return (curve,)


@app.cell
def _(curve):
    doubled = mo.sql(
        f"""
        SELECT step, value FROM curve WHERE value >= 2
        """
    )
    return (doubled,)


@app.cell
def _(doubled, params):
    if params.out:
        doubled.write_parquet(params.out)
    print(f"rows={params.rows} rate={params.rate} doubled={len(doubled)} out={params.out or '-'}")
    return


@app.function
def test_growth_starts_at_one():
    assert growth(3, 10.0)["value"][0] == 1.0


@app.function
def test_growth_compounds():
    assert round(growth(3, 10.0)["value"][2], 6) == 1.21


if __name__ == "__main__":
    app.run()
