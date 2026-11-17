# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "marimo>=0.25.2",
#     "matplotlib>=3.9",
#     "numpy>=2",
#     "polars>=1",
#     "wigglystuff>=0.5.40",
# ]
# ///

import marimo

__generated_with = "0.25.2"
app = marimo.App(width="medium")

with app.setup:
    import marimo as mo
    import matplotlib.pyplot as plt
    import numpy as np
    import polars as pl
    from wigglystuff import (
        ChartPuck,
        FormulaDAG,
        Hint,
        HoverSlider,
        Matrix,
        ParallelCoordinates,
        PlaySlider,
        SortableList,
        StateViewer,
        TangleDistribution,
        TangleLatex,
        TangleSlider,
    )


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    # Wigglystuff patterns

    One working example of each widget shape this skill recommends. Every
    widget is wrapped with `mo.ui.anywidget`, shown as the last expression of
    the cell that makes it, and read in a later cell.
    """)
    return


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## A number inside a sentence
    """)
    return


@app.cell
def _():
    cups = mo.ui.anywidget(
        TangleSlider(amount=3, min_value=0, max_value=12, step=1, digits=0, suffix=" cups")
    )
    price = mo.ui.anywidget(
        TangleSlider(amount=4.5, min_value=1, max_value=9, step=0.5, digits=2, prefix="$")
    )
    mo.md(f"Each day I drink {cups} at {price} each.")
    return cups, price


@app.cell
def _(cups, price):
    mo.md(f"That is **${cups.amount * price.amount * 365:,.0f}** a year.")
    return


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## A number with its uncertainty
    """)
    return


@app.cell
def _():
    delivery = mo.ui.anywidget(
        TangleDistribution(
            "lognorm",
            params={"scale": 25, "s": 0.3},
            template="{mean:.0f} ± {sd:.0f} minutes",
        )
    )
    mo.md(f"A delivery takes {delivery}.")
    return (delivery,)


@app.cell
def _(delivery):
    _ = delivery.params
    late = delivery.widget.ppf(0.9)
    mo.md(f"Nine in ten arrive within **{late:.0f} minutes**.")
    return (late,)


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## A formula you can drag
    """)
    return


@app.cell
def _():
    bell = mo.ui.anywidget(
        TangleLatex(
            latex=r"p(x) = \frac{1}{\tangle{sigma}\sqrt{2\pi}}"
            r"\exp\left(-\frac{(x-\note{center}{\tangle{mu}})^2}{2\note{width}{\tangle{sigma}}^2}\right)",
            parameters={"mu": {"value": 0}, "sigma": {"value": 1, "min_value": 0.1}},
            notes={
                "center": "**mean**: where the bell is centred",
                "width": "**standard deviation**: how wide the bell is",
            },
        )
    )
    bell
    return (bell,)


@app.cell
def _(bell):
    _xs = np.linspace(-6, 6, 300)
    _fig, _ax = plt.subplots(figsize=(6, 2.5))
    for _values, _style in ((bell.committed_values, "--"), (bell.values, "-")):
        _mu, _sigma = _values["mu"], _values["sigma"]
        _ax.plot(_xs, np.exp(-((_xs - _mu) ** 2) / (2 * _sigma**2)) / (_sigma * np.sqrt(2 * np.pi)), _style)
    _ax
    return


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## Formulas wired together
    """)
    return


@app.cell
def _():
    band = mo.ui.anywidget(
        FormulaDAG(
            {
                "mu": r"\mu = \frac{1}{n}\sum_i x_i",
                "var": r"\sigma^2 = \frac{1}{n}\sum_i (x_i - \use{mu})^2",
                "sigma": r"\sigma = \sqrt{\use{var}}",
                "band": r"b = \use{mu} \pm \tangle{k}\,\use{sigma}",
            },
            parameters={"k": {"value": 2, "min_value": 0, "max_value": 4, "step": 0.5}},
        )
    )
    band
    return (band,)


@app.cell
def _(band):
    k = band.values["k"]
    return (k,)


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## A chart as an input
    """)
    return


@app.cell
def _():
    _rng = np.random.default_rng(0)
    cloud = _rng.normal(size=(300, 2))
    _fig, _ax = plt.subplots(figsize=(5, 4))
    _ax.scatter(cloud[:, 0], cloud[:, 1], s=8, alpha=0.5)
    puck = mo.ui.anywidget(ChartPuck(_fig, x=0.0, y=0.0))
    plt.close(_fig)
    Hint(puck, "drag the dot to choose a **centre**")
    return cloud, puck


@app.cell
def _(cloud, puck):
    centre = np.array([puck.x[0], puck.y[0]])
    near = int((np.linalg.norm(cloud - centre, axis=1) < 1).sum())
    mo.md(f"**{near}** points lie within 1 of ({centre[0]:.2f}, {centre[1]:.2f}).")
    return centre, near


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## A matrix, an order, a playhead, a preview
    """)
    return


@app.cell
def _():
    transform = mo.ui.anywidget(Matrix(matrix=[[1.0, 0.0], [0.0, 1.0]], step=0.1, digits=1))
    order = mo.ui.anywidget(SortableList(["load", "clean", "fit", "report"]))
    frame = mo.ui.anywidget(PlaySlider(value=0, min_value=0, max_value=20, step=1, interval_ms=150))
    cutoff = mo.ui.anywidget(HoverSlider(start=0, stop=1, step=0.05, value=0.5, label="cutoff"))
    mo.hstack([transform, order, mo.vstack([frame, cutoff])], justify="start", gap=2)
    return cutoff, frame, order, transform


@app.cell
def _(cutoff, frame, order, transform):
    moved = np.array([[1.0, 1.0]]) @ np.array(transform.matrix)
    summary = {
        "moved": moved.round(2).tolist(),
        "order": list(order.value["value"]),
        "frame": frame.value["value"],
        "cutoff": cutoff.value["value"],
        "preview": cutoff.hover_value,
    }
    summary
    return moved, summary


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## Many runs at once
    """)
    return


@app.cell
def _():
    _rng = np.random.default_rng(1)
    runs = pl.DataFrame(
        {
            "lr": 10 ** _rng.uniform(-4, -1, 60),
            "depth": _rng.integers(2, 9, 60),
            "dropout": _rng.uniform(0, 0.5, 60),
        }
    ).with_columns(
        (0.9 - (pl.col("lr").log10() + 2.5).abs() * 0.1 - pl.col("dropout") * 0.2).alias("score"),
        pl.when(pl.col("depth") > 5).then(pl.lit("deep")).otherwise(pl.lit("shallow")).alias("kind"),
    )
    coords = mo.ui.anywidget(ParallelCoordinates(runs, color_by="kind"))
    coords
    return coords, runs


@app.cell
def _(coords):
    kept = coords.widget.filtered_as_polars
    mo.md(f"**{len(kept)}** runs pass the brushes.")
    return (kept,)


@app.cell(hide_code=True)
def _():
    mo.md(r"""
    ## An algorithm, step by step
    """)
    return


@app.function
def solve(board, row, n):
    """Backtracking search for N queens."""
    if row == n:
        return True
    for col in range(n):
        if all(c != col and abs(c - col) != row - r for r, c in enumerate(board)):
            board.append(col)
            if solve(board, row + 1, n):
                return True
            board.pop()
    return False


@app.function
def view(board, n):
    """The board as text, one row a line."""
    rows = ["." * c + "Q" + "." * (n - c - 1) for c in board]
    return "<pre>" + "\n".join(rows) + "</pre>"


@app.cell
def _():
    queens = mo.ui.anywidget(StateViewer(solve, view, args=([], 0, 6), variables=["board", "row"]))
    queens
    return (queens,)


@app.cell
def _(queens):
    mo.md(f"The search took **{queens.widget.n_steps}** steps.")
    return


if __name__ == "__main__":
    app.run()
