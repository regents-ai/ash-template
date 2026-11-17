# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "marimo>=0.25.2",
#     "altair>=5",
#     "numpy>=2",
#     "polars>=1",
#     "pytest>=8",
#     "wigglystuff>=0.5.40",
# ]
# ///

import marimo

__generated_with = "0.25.2"
app = marimo.App(width="medium")

with app.setup:
    import altair as alt
    import marimo as mo
    import numpy as np
    import polars as pl
    from wigglystuff import TangleSlider


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    # A line through noise

    How well does a straight-line fit recover the slope it was drawn from,
    as the noise grows? Drag the numbers in the sentence below.
    """)
    return


@app.cell(hide_code=True)
def _():
    slope = mo.ui.anywidget(
        TangleSlider(amount=2.0, min_value=-5, max_value=5, step=0.1, digits=1)
    )
    noise = mo.ui.anywidget(
        TangleSlider(amount=0.5, min_value=0, max_value=3, step=0.1, digits=1)
    )
    points = mo.ui.slider(20, 500, step=20, value=200, label="points")
    mo.vstack(
        [
            mo.md(f"Draw a line with slope {slope} and add noise of {noise}."),
            points,
        ]
    )
    return noise, points, slope


@app.function
def make_points(slope: float, noise: float, n: int = 200, seed: int = 0) -> pl.DataFrame:
    """Points on y = slope * x, with normal noise added to y."""
    rng = np.random.default_rng(seed)
    x = rng.uniform(-1, 1, n)
    return pl.DataFrame({"x": x, "y": slope * x + rng.normal(0, noise, n)})


@app.function
def fitted_slope(df: pl.DataFrame) -> float:
    """Least-squares slope of y on x."""
    return float(np.polyfit(df["x"], df["y"], 1)[0])


@app.cell
def _(noise, points, slope):
    df = make_points(slope.amount, noise.amount, n=points.value)
    estimate = fitted_slope(df)
    return df, estimate


@app.cell(hide_code=True)
def _(df, estimate, slope):
    scatter = alt.Chart(df).mark_circle(opacity=0.5).encode(x="x", y="y")
    line = scatter.transform_regression("x", "y").mark_line(color="firebrick")
    mo.vstack(
        [
            scatter + line,
            mo.md(
                f"True slope **{slope.amount:.1f}**, fitted **{estimate:.2f}** "
                f"(off by {abs(estimate - slope.amount):.2f})."
            ),
        ]
    )
    return


@app.cell
def _():
    def test_noise_free_line_is_recovered():
        assert abs(fitted_slope(make_points(3.0, 0.0)) - 3.0) < 1e-9

    def test_same_seed_same_points():
        assert make_points(1.0, 1.0).equals(make_points(1.0, 1.0))

    return


if __name__ == "__main__":
    app.run()
