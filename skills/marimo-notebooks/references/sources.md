# Where this skill comes from

Built on 14 November 2026 from the sources below, read at their state on that day, and
checked by running against **marimo 0.25.2** and **wigglystuff 0.5.40**.

## Repositories used

All under https://github.com/marimo-team unless noted.

| Repository | What it gave this skill |
|---|---|
| `marimo` | The file format, the rules and lint codes, `marimo check`, `marimo pair` and code mode, exports, `mo.ui` and layout. The installed package and its `--help` were treated as the truth over any document. |
| `skills` (not on the original list) | marimo's own agent skills. The notebook rules, the batch pattern, the browser-compatibility check and the molab badge rules here follow them. |
| `marimo-pair` (not on the original list) | The earlier, separate form of live-session work; confirmed that it is now built into marimo itself. |
| `learn` | How good teaching notebooks are shaped: title cell, prose and code in turn, controls inside sentences, hidden plumbing. |
| `youtube-material` (not on the original list) | The notebooks behind the videos; the source of the wigglystuff ideas. |
| `anywidget-gallery` | Starting points for writing a widget of your own. |
| `marimo-lens` | Pointing at a chart or table and having the agent answer; referenced from live sessions. |
| `marimo-studio` | Views (dashboards, reports) over a notebook. |
| `marimo-export` | Exports that can be verified. |
| `marimohub` | The self-hosted hub: its commands, its agent interface, how sessions and packages behave. |
| `awesome-marimo` | A list of further tools; used only to check nothing important was missed. |
| `koaning/wigglystuff` (via its website and the published package) | Every widget in [wigglystuff.md](wigglystuff.md). The catalog was read from the installed 0.5.40, not the website. |

## Repositories set aside

| Repository | Why |
|---|---|
| `moku` | An experimental playground client, not part of making or changing notebooks. |
| `marimo-glance` | A browser extension for people reading notebooks on GitHub. |
| `jetbrains-marimo` | An editor plugin for people; nothing an agent uses. |
| `marimo-jupyter-extension` | Runs marimo inside JupyterLab for people; nothing an agent uses. |
| `marimo-operator` | Runs marimo on Kubernetes; an infrastructure matter, not a notebook one. |

## Videos used

The 20 most recent shorts from the marimo channel
(https://www.youtube.com/channel/UCKSXs4jiLetyWsW5Lba3ZjQ) as of 14 November 2026, read as
transcripts.

| Video | What it added |
|---|---|
| Super Better GridSearch | Live progress for scikit-learn searches (`FitProgress`). Found to be unreleased, which led to the rule to check the installed release. |
| Super Better Formulas | `TangleLatex`: a formula whose numbers drag, with a note on each term. |
| Stuff That Matters | A dragged widget now reports the value before the drag as well as the live one; the source of the live and committed rule. |
| Super Better Probabilities; Blue Highlights Indeed! | `TangleDistribution`: scipy naming, continuous and discrete distributions, reading percentiles. |
| Super Better PCoords | `ParallelCoordinates` colouring and reading the kept rows. |
| Chess Algo, Enhance! | `StateViewer` for stepping through a search. |
| Trace Trace Trace! | `TraceView` for OpenTelemetry traces. |
| An Embedding dtour | A widget that moves between chosen views of an embedding; the case for writing your own widget. |
| OpenCode v2 is Fun | An agent of any make answering questions about a running notebook through `marimo pair`. |
| Just One Line | A public site that is a marimo notebook, built with marimo-studio and running in the reader's browser. |
| Super Better Releases | Release notes written as notebooks: show the feature, do not list it. |
| Super Better Map Export; More Maps Stuff | GeoPandas tables, GeoJSON and GeoParquet download. |
| We Support Lazy Now | Python 3.15 lazy imports in notebooks. |
| Thumbnails, Yes Thumbnails; All Links All Notebooks | molab thumbnails, session snapshots, GitHub links with the browser or server choice. |
| Finetuning Trick; About That Empire ... | Two explanations built as notebooks (a matrix trick, a map of a network): one idea, one control, one picture that answers. |
| Pretty Darn Cool | Not about notebooks; not used. |

## What was run and what was not

Run and seen working: every code pattern in `SKILL.md` and the three notebooks in `assets/`
(through `scripts/verify.sh`), `marimo check` with and without `--fix`, `marimo convert`,
importing a function from a notebook, a live session end to end (`pair notebook list`,
reading cells, creating and running a cell, `set_ui_value` re-running dependents), dragging a
wigglystuff control in a real browser and seeing the dependent cell change, and the exports
to a page, a browser notebook (folder and single file), Markdown, a script, Jupyter and a
session snapshot.

Not run, taken from each tool's own documentation: a cell screenshot written to a file (the
call was reached and asked for playwright, which was not installed), PDF and thumbnail
export, every marimo-studio, marimo-export, marimo-lens and `mohub` command, and anything on
a hub. Read that tool's `--help` before relying on one of these.

## Refreshing this skill

marimo releases weekly and wigglystuff more often. When a command or name here is refused:

1. `uvx marimo --version`, then `uvx marimo <command> --help` for the command in question,
   and `uvx marimo pair --help` for live sessions.
2. `uv run scripts/widget_api.py` for the widget list of the installed wigglystuff.
3. Run `scripts/verify.sh` on each notebook in `assets/`. A failure is the first thing to
   fix; the references follow from what the notebooks prove.
4. Change the version line at the top of `SKILL.md` and the date at the top of this page.

## Related skills to install when needed

marimo's own skills cover narrower jobs this one only points at: converting Jupyter
notebooks and Streamlit apps, turning a paper into a notebook, and authoring anywidgets.
They are at https://github.com/marimo-team/skills. A copy of its `marimo-notebook` skill may
already be installed for the person; where the two disagree, the installed marimo's own
behaviour decides.
