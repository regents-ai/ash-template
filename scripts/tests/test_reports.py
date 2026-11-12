"""Run the template's reports (harvest, drift, pins and stale pull requests) and its
rename (init) on fixture repositories.

Each test builds git repositories in a fresh temporary folder: a template checkout
holding copies of the scripts, site clones with their own origins, and library
histories. GitHub is a stand-in `gh` that serves files from a folder, and the live
homepages a stand-in `curl`. The fixtures stay in the system's temporary folder,
which the system clears; the tests delete nothing.
"""

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
COPIED = ["drift.sh", "pins.sh", "harvest.sh", "github.sh", "shared-files.sh", "stale-prs.sh"]
DAY = 86400
START = 1_790_000_000

GIT_ENV = {
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
    "GIT_AUTHOR_NAME": "Fixture",
    "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
    "GIT_COMMITTER_NAME": "Fixture",
    "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
}

FAKE_GH = r"""#!/usr/bin/env bash
# gh api [-H <header>] <endpoint> [--jq <filter>], served from $FAKE_GH:
# <repo>/main holds main's commit, <repo>/<commit>/<path> a file, and
# <repo>/<commit>/<path>.error a failure other than 404. With --jq .sha a file
# answers its git blob id. gh pr list --repo <repo> ... answers <repo>/pulls.json.
set -euo pipefail
if [[ "$1 $2" == "pr list" ]]; then
  cat "$FAKE_GH/$4/pulls.json"
  exit
fi
[[ "$1" == api ]] || exit 2
shift
endpoint=""
jq=""
while (($#)); do
  case "$1" in
    -H) shift 2 ;;
    --jq) jq="$2"; shift 2 ;;
    *) endpoint="$1"; shift ;;
  esac
done
rest="${endpoint#repos/}"
case "$rest" in
  */commits/main) cat "$FAKE_GH/${rest%/commits/main}/main" ;;
  */contents/*)
    repo="${rest%%/contents/*}"
    path="${rest#*/contents/}"
    ref="${path##*\?ref=}"
    path="${path%%\?ref=*}"
    file="$FAKE_GH/$repo/$ref/$path"
    if [[ -f "$file.error" ]]; then
      echo "HTTP 502: Bad Gateway" >&2
      exit 1
    elif [[ -f "$file" && "$jq" == .sha ]]; then
      git hash-object "$file"
    elif [[ -f "$file" ]]; then
      cat "$file"
    else
      echo "gh: Not Found (HTTP 404)" >&2
      exit 1
    fi
    ;;
  *) exit 2 ;;
esac
"""

FAKE_CURL = r"""#!/usr/bin/env bash
# curl ... <url>/, served from $FAKE_CURL/<host>.html.
set -euo pipefail
url="${*: -1}"
host="${url#https://}"
cat "$FAKE_CURL/${host%/}.html"
"""


MAKEFILE_TEMPLATE = "TEMPLATE := repos/regents-ai/ash-template"


def mix_exs(app, module, deps="[]"):
    return (
        f"defmodule {module}.MixProject do\n"
        "  use Mix.Project\n\n"
        "  def project do\n"
        "    [\n"
        f"      app: :{app},\n"
        f"      deps: {deps}\n"
        "    ]\n"
        "  end\n\n"
        "  defp aliases do\n"
        "    [setup: [\"deps.get\"]]\n"
        "  end\n"
        "end\n"
    )


class Fixture(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="regent-reports-"))
        self.bin = self.base / "bin"
        self.bin.mkdir()
        for name, body in [("gh", FAKE_GH), ("curl", FAKE_CURL)]:
            (self.bin / name).write_text(body)
            (self.bin / name).chmod(0o755)
        self.env = {
            **os.environ,
            **GIT_ENV,
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "FAKE_GH": str(self.base / "github"),
            "FAKE_CURL": str(self.base / "live"),
        }
        self.clock = START

    def git(self, directory, *args, days=0):
        self.clock += days * DAY
        stamp = f"@{self.clock} +0000"
        env = {**self.env, "GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp}
        return subprocess.run(
            ["git", "-C", str(directory), *args], env=env, check=True,
            capture_output=True, text=True,
        ).stdout.strip()

    def write(self, root, files):
        for path, body in files.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(body)

    def commit(self, root, message, files=None, days=1):
        self.write(root, files or {})
        self.git(root, "add", "-A")
        self.git(root, "commit", "-q", "--allow-empty", "-m", message, days=days)
        return self.git(root, "rev-parse", "HEAD")

    def repo(self, path):
        path.mkdir(parents=True)
        self.git(path, "init", "-q", "-b", "main")
        return path

    def template(self, files):
        root = self.repo(self.base / "ash-template")
        (root / "scripts").mkdir()
        for name in COPIED:
            shutil.copy2(SCRIPTS / name, root / "scripts" / name)
        self.commit(root, "template", files)
        return root

    def listed(self):
        """Every path in scripts/shared-files.sh's shared, build and homepage lists."""
        script = 'source scripts/shared-files.sh; printf "%s\\n" "${shared[@]}" "${build[@]}" "${homepage[@]}"'
        return subprocess.run(
            ["bash", "-c", script], cwd=SCRIPTS.parent, check=True, capture_output=True, text=True,
        ).stdout.split()

    def run_script(self, root, name, *args):
        return subprocess.run(
            [str(root / "scripts" / name), *args], env=self.env, capture_output=True, text=True,
        )

    def report(self, root, name, *args):
        done = self.run_script(root, name, *args)
        self.assertEqual(done.returncode, 0, done.stderr)
        return json.loads(done.stdout)

    def serve(self, repo, commit, files):
        site = self.base / "github" / repo
        self.write(site / commit, files)
        (site / "main").write_text(commit + "\n")


class Harvest(Fixture):
    def setUp(self):
        super().setUp()
        self.root = self.template({
            "platform/lib/ash_template/repo.ex": "defmodule AshTemplate.Repo do\nend\n",
            "platform/lib/ash_template_web/onchain_steps.ex": "defmodule AshTemplateWeb.OnchainSteps do\nend\n",
            "platform/lib/mix/tasks/ash_template.route_handoff.ex": "defmodule Mix.Tasks.AshTemplate.RouteHandoff do\nend\n",
            "platform/Dockerfile": "FROM elixir\n",
            "platform/assets/css/pages/home.css": "body {}\n",
            "docs/ash-template-guide.md": "# Guide\n",
            "README.md": "# Ash Template\n",
        })
        self.repos = self.base / "repos"

    def site(self, name, module):
        origin = self.base / "origins" / f"{name}.git"
        origin.parent.mkdir(parents=True, exist_ok=True)
        self.git(self.base, "init", "-q", "--bare", "-b", "main", str(origin))
        work = self.repo(self.base / "work" / name)
        self.git(work, "remote", "add", "origin", str(origin))
        base = self.commit(work, "base", {
            "platform/mix.exs": mix_exs(name, module),
            f"platform/lib/{name}/repo.ex": f"defmodule {module}.Repo do\nend\n",
            f"docs/{name}-guide.md": "# Guide\n",
        })
        self.git(work, "push", "-q", "origin", "main")
        self.repos.mkdir(exist_ok=True)
        self.git(self.base, "clone", "-q", str(origin), str(self.repos / name))
        return work, base

    def ledger(self, rows):
        path = self.base / "ledger.md"
        # A row naming a site outside "Last read" is never read as its last commit.
        lines = ["# Harvest ledger", "", "## Mode", "", "| Job | Mode |", "| --- | --- |",
                 "| Harvest | dry run |", "| keyfleet | " + "0" * 40 + " |", "",
                 "## Last read", "", "| Site | Commit | Read |", "| --- | --- | --- |"]
        lines += [f"| {site} | {commit} | 2026-11-11T07:00Z |" for site, commit in rows.items()]
        lines += ["", "## Verdicts", "", "| Date | Site | Commit | Verdict | Topic | Pull request | Note |",
                  "| --- | --- | --- | --- | --- | --- | --- |"]
        path.write_text("\n".join(lines) + "\n")
        return path

    def test_lists_new_commits_under_the_template_names_with_shared_ones_flagged(self):
        work, base = self.site("keyfleet", "Keyfleet")
        shared = self.commit(work, "Repo: one pool", {"platform/lib/keyfleet/repo.ex": "changed\n"})
        moved = self.commit(work, "Wallet steps at their own path", {
            "platform/lib/keyfleet_web/wallet/onchain_steps.ex": "steps\n",
            "platform/lib/keyfleet/fleet.ex": "fleet\n",
        })
        self.git(work, "mv", "docs/keyfleet-guide.md", "docs/keyfleet-notes.md")
        renamed = self.commit(work, "Guide renamed, task added", {
            "platform/lib/mix/tasks/keyfleet.route_handoff.ex": "task\n",
            "platform/Dockerfile": "FROM elixir:1.19\n",
        })
        self.git(work, "checkout", "-q", "-b", "side", base)
        side = self.commit(work, "Side branch", {"side.md": "side\n"})
        self.git(work, "checkout", "-q", "main")
        self.git(work, "merge", "-q", "--no-ff", "-m", "Merge side", "side", days=1)
        merge = self.git(work, "rev-parse", "HEAD")
        self.git(work, "push", "-q", "origin", "main")

        out = self.report(self.root, "harvest.sh", str(self.ledger({"keyfleet": base})), str(self.repos), "keyfleet")

        self.assertEqual(out["template"], self.git(self.root, "rev-parse", "HEAD"))
        [site] = out["sites"]
        self.assertEqual((site["site"], site["app"], site["module"]), ("keyfleet", "keyfleet", "Keyfleet"))
        self.assertEqual((site["since"], site["head"]), (base, merge))
        commits = {c["commit"]: c for c in site["commits"]}
        self.assertEqual([c["commit"] for c in site["commits"]], [shared, moved, renamed, side, merge])

        self.assertTrue(commits[shared]["shared"])
        self.assertEqual(commits[shared]["files"], [{
            "status": "M", "path": "platform/lib/keyfleet/repo.ex",
            "template_path": "platform/lib/ash_template/repo.ex", "list": "shared",
        }])
        self.assertEqual(commits[shared]["subject"], "Repo: one pool")
        self.assertRegex(commits[shared]["date"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")

        self.assertTrue(commits[moved]["shared"])
        self.assertEqual(
            {f["path"]: (f["template_path"], f["list"]) for f in commits[moved]["files"]},
            {"platform/lib/keyfleet_web/wallet/onchain_steps.ex": ("platform/lib/ash_template_web/onchain_steps.ex", "shared"),
             "platform/lib/keyfleet/fleet.ex": (None, None)},
        )

        self.assertFalse(commits[renamed]["shared"])
        self.assertEqual(
            {(f["status"], f["path"]): (f["template_path"], f["list"]) for f in commits[renamed]["files"]},
            {("D", "docs/keyfleet-guide.md"): ("docs/ash-template-guide.md", None),
             ("A", "docs/keyfleet-notes.md"): (None, None),
             ("A", "platform/lib/mix/tasks/keyfleet.route_handoff.ex"): ("platform/lib/mix/tasks/ash_template.route_handoff.ex", None),
             ("A", "platform/Dockerfile"): ("platform/Dockerfile", "build")},
        )

        self.assertFalse(commits[side]["merge"])
        self.assertTrue(commits[merge]["merge"])
        self.assertEqual(commits[merge]["files"], [])

    def test_a_site_already_read_has_no_commits_and_homepage_files_count_for_regents_alone(self):
        keyfleet, keyfleet_base = self.site("keyfleet", "Keyfleet")
        regents, regents_base = self.site("regents", "Regents")
        self.commit(regents, "Home", {"platform/assets/css/pages/home.css": "body { margin: 0 }\n"})
        self.git(regents, "push", "-q", "origin", "main")
        ledger = self.ledger({"keyfleet": keyfleet_base, "regents": regents_base})

        out = self.report(self.root, "harvest.sh", str(ledger), str(self.repos), "keyfleet", "regents")

        keyfleet_read, regents_read = out["sites"]
        self.assertEqual((keyfleet_read["since"], keyfleet_read["head"], keyfleet_read["commits"]),
                         (keyfleet_base, keyfleet_base, []))
        [home] = regents_read["commits"]
        self.assertEqual(home["files"][0]["list"], "homepage")
        self.assertFalse(home["shared"])

    def test_a_site_missing_from_the_ledger_stops_the_run(self):
        _, base = self.site("keyfleet", "Keyfleet")
        self.site("regents", "Regents")
        done = self.run_script(self.root, "harvest.sh", str(self.ledger({"keyfleet": base})),
                               str(self.repos), "keyfleet", "regents")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("no full last-read commit for regents", done.stderr)
        self.assertEqual(done.stdout, "")

    def test_a_clone_without_the_last_commit_read_stops_the_run(self):
        self.site("keyfleet", "Keyfleet")
        done = self.run_script(self.root, "harvest.sh", str(self.ledger({"keyfleet": "a" * 40})),
                               str(self.repos), "keyfleet")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("fetch its full history", done.stderr)


class Drift(Fixture):
    PICTURE = "platform/priv/static/images/animations/datascape.webp"

    def setUp(self):
        super().setUp()
        self.paths = self.listed()
        files = {path: f"{path}\nAshTemplate ash_template ash-template\n" for path in self.paths}
        files["platform/mix.exs"] = mix_exs("ash_template", "AshTemplate")
        # A picture is never renamed: the site holds the same bytes.
        files[self.PICTURE] = "picture\n"
        # The template's repository, which every site's Makefile names as it is, and the
        # template's own targets, which scripts/init.sh drops from a site's Makefile.
        files["Makefile"] += (MAKEFILE_TEMPLATE + "\n"
                              "# template-only\ncheck-scripts:\n\ttrue\n# /template-only\n")
        self.root = self.template(files)

    def site_copy(self, app, module, path):
        """The site's copy of a template file, renamed the way scripts/init.sh renames it."""
        site_path = path.replace("ash_template", app)
        if path == "Makefile":
            return site_path, f"Makefile\n{module} {app} ash-template\n{MAKEFILE_TEMPLATE}\n"
        return site_path, f"{site_path}\n{module} {app} {app.replace('_', '-')}\n"

    def serve_site(self, site, module, commit, change=None, absent=(), elsewhere=None):
        files = dict(self.site_copy(site, module, path) for path in self.paths)
        files[self.PICTURE] = "picture\n"
        for path in absent:
            files.pop(path.replace("ash_template", site))
        for path, body in (change or {}).items():
            files[path.replace("ash_template", site)] = body
        for path, site_path in (elsewhere or {}).items():
            files[site_path] = files.pop(path.replace("ash_template", site))
        files["platform/mix.exs"] = mix_exs(site, module, deps="[{:own, \"~> 1.0\"}]")
        self.serve(f"regents-ai/{site}", commit, files)

    def files(self, site):
        return {f["path"]: f for f in site["files"]}

    def test_each_file_is_same_differs_missing_or_not_used_under_the_site_names(self):
        repo_ex = "platform/lib/ash_template/repo.ex"
        metrics = "platform/lib/ash_template_web/metrics.ex"
        gate = "platform/lib/ash_template_web/plugs/launch_gate.ex"
        self.serve_site("techtree", "Techtree", "c" * 40,
                        change={repo_ex: "platform/lib/techtree/repo.ex\nTechtree techtree own\nextra\n"},
                        absent=[metrics])

        out = self.report(self.root, "drift.sh", "techtree")

        self.assertEqual(out["template"], self.git(self.root, "rev-parse", "HEAD"))
        [site] = out["sites"]
        self.assertEqual((site["site"], site["repo"], site["main"], site["app"], site["module"]),
                         ("techtree", "regents-ai/techtree", "c" * 40, "techtree", "Techtree"))
        self.assertIsNone(site["live_homepage"])
        files = self.files(site)
        self.assertEqual({f["list"] for f in site["files"]}, {"shared", "build"})

        differs = files[repo_ex]
        self.assertEqual((differs["status"], differs["site_path"], differs["added"], differs["removed"]),
                         ("differs", "platform/lib/techtree/repo.ex", 2, 1))
        diff = (self.root / differs["diff"]).read_text()
        self.assertIn("+extra", diff)
        self.assertIn("--- template/platform/lib/ash_template/repo.ex", diff)

        self.assertEqual(files[metrics]["status"], "missing")
        self.assertEqual((files[gate]["status"], files[gate]["why"]), ("not_used", "public, no sign-in: never closed"))
        same = files["platform/lib/ash_template_web/plugs/parsers.ex"]
        self.assertEqual(same, {
            "list": "shared", "path": "platform/lib/ash_template_web/plugs/parsers.ex",
            "site_path": "platform/lib/techtree_web/plugs/parsers.ex", "status": "same",
            "added": None, "removed": None, "diff": None, "why": None,
        })
        self.assertEqual(files["platform/mix.exs"]["status"], "same")
        self.assertEqual(files["Makefile"]["status"], "same")

    def test_a_moved_file_is_read_at_the_site_path_and_runs_keep_their_own_folders(self):
        chain = "platform/lib/ash_template/chain_client.ex"
        self.serve_site("autolaunch", "Autolaunch", "a" * 40,
                        elsewhere={chain: "platform/lib/autolaunch/chain/node_client.ex"},
                        change={"Makefile": "drifted\n"})

        first = self.report(self.root, "drift.sh", "autolaunch")
        second = self.report(self.root, "drift.sh", "autolaunch")

        files = self.files(first["sites"][0])
        self.assertEqual((files[chain]["status"], files[chain]["site_path"]),
                         ("same", "platform/lib/autolaunch/chain/node_client.ex"))
        firsts, seconds = (self.files(run["sites"][0])["Makefile"]["diff"] for run in (first, second))
        self.assertNotEqual(Path(firsts).parent, Path(seconds).parent)
        self.assertTrue((self.root / firsts).is_file())
        self.assertTrue((self.root / seconds).is_file())

    def live_pages(self, template, regents):
        live = self.base / "live"
        live.mkdir()
        (live / "template.regents.sh.html").write_text(template)
        (live / "regents.sh.html").write_text(regents)

    def test_regents_adds_the_homepage_files_and_the_live_homepages(self):
        picture = self.PICTURE
        self.serve_site("regents", "Regents", "b" * 40)
        page = ('<section class="home__glass" id="home-glass"><!-- tabs -->'
                '<nav class="home__foot"><a href="/autolaunch">Autolaunch</a></nav>'
                '<p>Words outside a link are not compared</p><a href="https://x.com/regents">X</a>'
                '</section><p class="home__copyright">© Regents</p>')
        self.live_pages(page, page.replace("Autolaunch</a>", 'Autolaunch</a><a href="/techtree">Techtree</a>'))

        out = self.report(self.root, "drift.sh", "regents")

        [site] = out["sites"]
        self.assertIn("homepage", {f["list"] for f in site["files"]})
        self.assertEqual(self.files(site)[picture]["status"], "same")
        homepage = site["live_homepage"]
        self.assertEqual((homepage["status"], homepage["added"], homepage["removed"]), ("differs", 3, 1))
        diff = (self.root / homepage["diff"]).read_text()
        self.assertIn("+Techtree", diff)
        self.assertIn(" link https://x.com/regents", diff)
        self.assertIn(" © Regents", diff)
        self.assertNotIn("Words outside", diff)

    def test_a_picture_is_compared_by_its_blob_and_a_page_without_the_panel_is_missing(self):
        picture = self.PICTURE
        self.serve_site("regents", "Regents", "b" * 40, change={picture: "another picture\n"})
        self.live_pages('<section id="home-glass"><a href="/">Home</a></section>', "<main>No panel</main>")

        out = self.report(self.root, "drift.sh", "regents")

        [site] = out["sites"]
        self.assertEqual(self.files(site)[picture],
                         {"list": "homepage", "path": picture, "site_path": picture, "status": "differs",
                          "added": None, "removed": None, "diff": None, "why": None})
        self.assertEqual(site["live_homepage"], {"status": "missing", "added": None, "removed": None,
                                                 "diff": None, "why": "no glass panel on regents.sh"})

    def test_a_failed_read_other_than_404_stops_the_run(self):
        self.serve_site("keyfleet", "Keyfleet", "d" * 40)
        error = self.base / "github/regents-ai/keyfleet" / ("d" * 40) / "platform/lib/keyfleet/repo.ex.error"
        error.write_text("")
        done = self.run_script(self.root, "drift.sh", "keyfleet")
        self.assertNotEqual(done.returncode, 0)
        self.assertIn("HTTP 502", done.stderr)
        self.assertEqual(done.stdout, "")


class Init(Fixture):
    def test_the_makefile_keeps_reading_the_template_repository(self):
        root = self.repo(self.base / "ash-template")
        (root / "scripts").mkdir()
        shutil.copy2(SCRIPTS / "init.sh", root / "scripts" / "init.sh")
        reports = ["scripts/drift.sh", "scripts/pins.sh", "scripts/github.sh", "scripts/shared-files.sh",
                   "scripts/harvest.sh", "scripts/stale-prs.sh", "scripts/tests/test_reports.py", "automation/harvest.md",
                   "automation/spread.md"]
        self.commit(root, "template", {
            **{path: "report\n" for path in reports},
            "Makefile": (
                "# Every site checks ash-template's current main branch.\n"
                f"{MAKEFILE_TEMPLATE}\n"
                "check-required-fixes:\n"
                "\telixir check.exs \"ash-template $$rev\"\n"
                "handoff:\n"
                "\tcd platform && mix ash_template.route_handoff\n"
                "# template-only\ncheck-scripts:\n\ttrue\n# /template-only\n"
            ),
            "platform/lib/mix/tasks/ash_template.route_handoff.ex": "defmodule Mix.Tasks.AshTemplate.RouteHandoff do\nend\n",
            "platform/fly.staging.toml": "app = \"ash-template-staging\"\n",
            "CHANGELOG.md": "# Changelog\n",
        })

        done = self.run_script(root, "init.sh", "night_owl", "NightOwl", "Night Owl")

        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual((root / "Makefile").read_text(), (
            "# Every site checks ash-template's current main branch.\n"
            f"{MAKEFILE_TEMPLATE}\n"
            "check-required-fixes:\n"
            "\telixir check.exs \"ash-template $$rev\"\n"
            "handoff:\n"
            "\tcd platform && mix night_owl.route_handoff\n"
        ))
        self.assertEqual((root / "platform/fly.staging.toml").read_text(), "app = \"night-owl-staging\"\n")
        self.assertTrue((root / "platform/lib/mix/tasks/night_owl.route_handoff.ex").is_file())
        self.assertFalse(any((root / path).exists() for path in reports))


class StalePrs(Fixture):
    def pull(self, number, days, branch="spread/2026-11-01", draft=False, title="Bring the template's checks"):
        opened = datetime.now(timezone.utc) - timedelta(days=days, hours=1)
        return {"number": number, "url": f"https://github.com/regents-ai/keyfleet/pull/{number}",
                "title": title, "headRefName": branch, "isDraft": draft,
                "createdAt": opened.strftime("%Y-%m-%dT%H:%M:%SZ")}

    def test_a_draft_waiting_for_sean_is_listed_and_never_closed(self):
        root = self.template({})
        pulls = [
            self.pull(1, 8),
            self.pull(2, 3),
            self.pull(3, 12, draft=True, title="Waits for Sean: wallet steps"),
            self.pull(4, 2, draft=True, title="Waits for Sean: sign-in"),
            self.pull(5, 9, draft=True, title="Draft without a letter to wait for"),
            self.pull(6, 7, title="Waits for Sean: not a draft"),
            self.pull(7, 20, branch="harvest/keyfleet-repo-2026-11-01"),
        ]
        folder = self.base / "github/regents-ai/keyfleet"
        folder.mkdir(parents=True)
        (folder / "pulls.json").write_text(json.dumps(pulls))

        out = self.report(root, "stale-prs.sh", "regents-ai/keyfleet", "spread/")

        self.assertEqual(out["repo"], "regents-ai/keyfleet")
        self.assertEqual([(p["number"], p["days_open"]) for p in out["close"]], [(1, 8), (5, 9), (6, 7)])
        self.assertEqual([(p["number"], p["days_open"]) for p in out["waiting"]], [(3, 12), (4, 2)])
        self.assertEqual(out["waiting"][0], {"number": 3, "url": "https://github.com/regents-ai/keyfleet/pull/3",
                                             "title": "Waits for Sean: wallet steps", "days_open": 12})


class Pins(Fixture):
    LIBRARIES = {
        "elixir-utils": "https://github.com/regents-ai/elixir-utils.git",
        "design-system": "https://github.com/regents-ai/design-system.git",
        "ash_postgres": "https://github.com/ash-project/ash_postgres.git",
        "regents-cli": "https://github.com/regents-ai/regents-cli.git",
    }
    SIWA = "siwa/siwa-elixir/apps/siwa/mix.exs"

    def setUp(self):
        super().setUp()
        # Each library's GitHub address leads to a local repository instead.
        for index, (name, url) in enumerate(self.LIBRARIES.items()):
            self.env[f"GIT_CONFIG_KEY_{index}"] = f"url.file://{self.base / 'libraries' / name}.insteadOf"
            self.env[f"GIT_CONFIG_VALUE_{index}"] = url
        self.env["GIT_CONFIG_COUNT"] = str(len(self.LIBRARIES))
        for name in self.LIBRARIES:
            self.repo(self.base / "libraries" / name)

        utils = self.base / "libraries/elixir-utils"
        self.u1 = self.commit(utils, "siwa 0.1.0", {self.SIWA: '  @version "0.1.0"\n'}, days=1)
        self.u2 = self.commit(utils, "format", {"format/lib.ex": "x\n"}, days=2)
        self.git(utils, "tag", "v0.2.0")
        self.u3 = self.commit(utils, "siwa 0.1.1", {self.SIWA: '  @version "0.1.1"\n'}, days=5)
        # A pull request's commit, reachable only from its pull request ref.
        self.git(utils, "checkout", "-q", "--detach", self.u1)
        self.pr = self.commit(utils, "pull request", {"agents/lib.ex": "pr\n"}, days=1)
        self.git(utils, "update-ref", "refs/pull/7/head", self.pr)
        self.git(utils, "checkout", "-q", "main")

        design = self.base / "libraries/design-system"
        self.d1 = self.commit(design, "ui", {"ui.css": "a\n"})
        cli = self.base / "libraries/regents-cli"
        self.r1 = self.commit(cli, "cli 1.0.0", {"cli.py": "1\n"})
        self.git(cli, "tag", "v1.0.0")
        self.r2 = self.commit(cli, "cli 1.0.1", {"cli.py": "2\n"}, days=3)
        postgres = self.base / "libraries/ash_postgres"
        self.a1 = self.commit(postgres, "pg", {"pg.ex": "1\n"})

        self.root = self.template({
            "platform/mix.lock": self.lock(
                ("regent_format", "elixir-utils", self.u3), ("siwa", "elixir-utils", self.u3),
                ("regent_ui", "design-system", self.d1), ("ash_postgres", "ash_postgres", self.a1)),
            "Makefile": f"REGENTS_CLI_REV := {self.r2}\n",
        })

    def lock(self, *pins, hex_postgres=None):
        lines = ["%{"]
        for app, library, commit in pins:
            url = self.LIBRARIES[library]
            lines.append(f'  "{app}": {{:git, "{url}", "{commit}", [ref: "{commit}"]}},')
        if hex_postgres:
            lines.append(f'  "ash_postgres": {{:hex, :ash_postgres, "{hex_postgres}", "abc", [:mix], [], "hexpm", "def"}},')
        return "\n".join(lines + ["}"]) + "\n"

    def rows(self, out, site):
        return {row["library"] + ("" if row["pin"] is None else ":" + row["pin"]): row
                for row in out["pins"] if row["site"] == site}

    def test_each_pin_counts_the_commits_and_days_it_lacks(self):
        site_commit = "e" * 40
        self.serve("regents-ai/keyfleet", site_commit, {
            "platform/mix.lock": self.lock(
                ("regent_format", "elixir-utils", self.u1), ("siwa", "elixir-utils", self.u1),
                ("regent_agents", "elixir-utils", self.pr), hex_postgres="2.6.0"),
            "Makefile": f"REGENTS_CLI_REV := {self.r1}\n",
        })

        out = self.report(self.root, "pins.sh", "keyfleet")

        self.assertEqual(out["library_main"], {
            "elixir-utils": self.u3, "design-system": self.d1, "ash_postgres": self.a1, "regents-cli": self.r2})
        template = self.rows(out, "template")
        self.assertEqual(template[f"elixir-utils:{self.u3}"]["commit"], self.git(self.root, "rev-parse", "HEAD"))
        self.assertIsNone(template[f"elixir-utils:{self.u3}"]["behind_template"])
        self.assertEqual(template[f"siwa:{self.u3}"]["version"], "0.1.1")

        site = self.rows(out, "keyfleet")
        self.assertEqual({row["commit"] for row in site.values()}, {site_commit})
        old = site[f"elixir-utils:{self.u1}"]
        self.assertEqual((old["apps"], old["on_github"], old["tag"]), (["regent_format", "siwa"], True, None))
        days = 7  # from the pin's commit to the newest it lacks, u3
        self.assertEqual(old["behind_template"],
                         {"target": self.u3, "on_github": True, "lacking": 2, "ahead": 0, "days": days})
        self.assertEqual(old["behind_main"], old["behind_template"])

        pull = site[f"elixir-utils:{self.pr}"]
        self.assertEqual((pull["apps"], pull["on_github"]), (["regent_agents"], True))
        self.assertEqual((pull["behind_main"]["lacking"], pull["behind_main"]["ahead"]), (2, 1))

        siwa = site[f"siwa:{self.u1}"]
        self.assertEqual((siwa["version"], siwa["behind_template"]["lacking"]), ("0.1.0", 1))

        self.assertEqual(site["design-system"], {
            "site": "keyfleet", "commit": site_commit, "library": "design-system", "pin": None,
            "tag": None, "hex": None, "version": None, "apps": [], "on_github": None,
            "behind_template": None, "behind_main": None,
        })
        self.assertEqual((site["ash_postgres"]["hex"], site["ash_postgres"]["apps"]), ("2.6.0", ["ash_postgres"]))

        cli = site[f"regents-cli:{self.r1}"]
        self.assertEqual((cli["tag"], cli["behind_template"]["lacking"], cli["behind_template"]["days"]),
                         ("v1.0.0", 1, 3))

    def test_a_pin_missing_from_github_has_no_counts(self):
        unknown = "f" * 40
        self.serve("regents-ai/techtree", "1" * 40, {
            "platform/mix.lock": self.lock(("regent_ui", "design-system", unknown)),
        })

        out = self.report(self.root, "pins.sh", "techtree")

        row = self.rows(out, "techtree")[f"design-system:{unknown}"]
        self.assertFalse(row["on_github"])
        self.assertEqual(row["behind_main"],
                         {"target": self.d1, "on_github": True, "lacking": None, "ahead": None, "days": None})
        self.assertNotIn("regents-cli", {r["library"] for r in out["pins"] if r["site"] == "techtree"})


if __name__ == "__main__":
    unittest.main()
