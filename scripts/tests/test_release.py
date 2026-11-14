"""Run scripts/deploy.sh and scripts/rollback.sh on a fixture repository.

Each test builds a git repository with its own origin in a fresh temporary folder,
holding copies of the scripts and three commits on main: `first`, `second` (which
adds a migration) and `third`, each with its own platform/fly.toml. Fly, the site,
the locks and the wait between reads of the site are stand-ins: `fly` records each
call, answers the running image and the release list from files, and keeps the Fly
configuration each switch was given; `curl` answers from a file; `lockf` records
its call and runs its command without taking a lock; `sleep` returns at once. None
of them reaches a real app. The fixtures stay in the system's temporary folder,
which the system clears; the tests delete nothing.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
COPIED = ["deploy.sh", "rollback.sh", "release-lib.sh"]
APP = "night-owl"
SITE = f"https://{APP}.fly.dev/capabilities.json"
APP_LOCK = f"/tmp/regent-release-{APP}.lock"
SHARED_PLACE = "/tmp/regent-shared-db-release.lock"
SECOND_PLACE = "/tmp/regent-shared-db-release-2.lock"

GIT_ENV = {
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_SYSTEM": os.devnull,
    "GIT_AUTHOR_NAME": "Fixture",
    "GIT_AUTHOR_EMAIL": "fixture@example.invalid",
    "GIT_COMMITTER_NAME": "Fixture",
    "GIT_COMMITTER_EMAIL": "fixture@example.invalid",
}

FAKE_FLY = r"""#!/usr/bin/env bash
# Records every call in $FAKE/fly.log. `fly image show` answers $FAKE/image.json and
# `fly releases` $FAKE/releases.json. A switch (`fly deploy --image`) keeps the Fly
# configuration it was given in $FAKE/switched.toml and makes the site answer
# $FAKE/site-after, when that file exists.
set -euo pipefail
echo "$*" >> "$FAKE/fly.log"
case "$1" in
  image) cat "$FAKE/image.json" ;;
  releases) cat "$FAKE/releases.json" ;;
  deploy)
    if [[ " $* " == *" --image "* ]]; then
      while [[ $1 != --config ]]; do shift; done
      cp "$2" "$FAKE/switched.toml"
      if [[ -f "$FAKE/site-after" ]]; then cp "$FAKE/site-after" "$FAKE/site"; fi
    fi
    ;;
  *) exit 2 ;;
esac
"""

FAKE_CURL = r"""#!/usr/bin/env bash
# curl ... <url>: records the address in $FAKE/curl.log and answers $FAKE/site; a
# missing file is a failed read. Once read, $FAKE/site-next, when it exists, becomes
# the next answer.
set -euo pipefail
echo "${!#}" >> "$FAKE/curl.log"
cat "$FAKE/site" 2>/dev/null || exit 22
if [[ -f "$FAKE/site-next" ]]; then mv "$FAKE/site-next" "$FAKE/site"; fi
"""

FAKE_LOCKF = r"""#!/usr/bin/env bash
# lockf [-k] [-s] [-t <seconds>] <file> <command...>: records the call in
# $FAKE/lockf.log and runs the command without taking a lock. A file named in
# $FAKE/held is taken: a try with -t 0 fails on it.
set -euo pipefail
echo "$*" >> "$FAKE/lockf.log"
wait=""
while [[ "$1" == -* ]]; do
  if [[ "$1" == -t ]]; then
    wait="$2"
    shift
  fi
  shift
done
if [[ $wait == 0 ]] && grep -qxF "$1" "$FAKE/held" 2>/dev/null; then exit 75; fi
shift
exec "$@"
"""

FAKE_SLEEP = "#!/usr/bin/env bash\n"


def capabilities(commit):
    """The site's /capabilities.json, naming the commit it runs."""
    return json.dumps({"build": {"commit": commit, "release": commit[:7]}})


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="ash-template-release-test-"))
        self.fake = self.tmp / "fake"
        self.bin = self.tmp / "bin"
        self.fake.mkdir()
        self.bin.mkdir()
        for name, body in [
            ("fly", FAKE_FLY),
            ("curl", FAKE_CURL),
            ("lockf", FAKE_LOCKF),
            ("sleep", FAKE_SLEEP),
        ]:
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        self.env = {
            **os.environ,
            **GIT_ENV,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "FAKE": str(self.fake),
            "TMPDIR": str(self.tmp),
        }

        origin = self.tmp / "origin.git"
        self.repo = self.tmp / "repo"
        self.git(self.tmp, "init", "--quiet", "--bare", "--initial-branch=main", str(origin))
        self.git(self.tmp, "clone", "--quiet", str(origin), str(self.repo))
        (self.repo / "scripts").mkdir()
        for name in COPIED:
            shutil.copy(SCRIPTS / name, self.repo / "scripts" / name)
        self.write("platform/fly.toml", "# first\n")
        self.write("platform/priv/repo/migrations/1_first.exs", "")
        self.first = self.commit("first")
        self.write("platform/fly.toml", "# second\n")
        self.write("platform/priv/repo/migrations/2_second.exs", "")
        self.second = self.commit("second")
        self.write("platform/fly.toml", "# third\n")
        self.write("platform/page.txt", "third\n")
        self.third = self.commit("third")
        self.git(self.repo, "push", "--quiet", "origin", "main")

    def git(self, cwd, *args):
        result = subprocess.run(
            ["git", *args], cwd=cwd, env=self.env, capture_output=True, text=True, check=True
        )
        return result.stdout.strip()

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self, message):
        self.git(self.repo, "add", "--all")
        self.git(self.repo, "commit", "--quiet", "-m", message)
        return self.git(self.repo, "rev-parse", "HEAD")

    def running(self, label):
        """The app's machines run the image labelled `label`, as `fly image show --json` lists it."""
        image = {"Registry": "registry.fly.io", "Repository": APP, "Tag": label, "MachineID": "m1"}
        (self.fake / "image.json").write_text(json.dumps([image]))

    def releases(self, *rows):
        """Each row is (version, status, commit the image was built from)."""
        (self.fake / "releases.json").write_text(
            json.dumps(
                [
                    {"Version": version, "Status": status, "ImageRef": f"registry.fly.io/{APP}:{commit[:7]}"}
                    for version, status, commit in rows
                ]
            )
        )

    def run_script(self, name, *args):
        return subprocess.run(
            [str(self.repo / "scripts" / name), *args],
            cwd=self.tmp,
            env=self.env,
            capture_output=True,
            text=True,
        )

    def log(self, name):
        path = self.fake / f"{name}.log"
        return path.read_text().splitlines() if path.exists() else []

    def changes(self):
        """The calls that would change the app: every `fly deploy`."""
        return [call for call in self.log("fly") if call.startswith("deploy")]

    def printed(self, result):
        return [line for line in result.stdout.splitlines() if line.startswith("Would run:")]

    def held(self, *places):
        (self.fake / "held").write_text("".join(f"{place}\n" for place in places))


class DeployTest(Fixture):
    def test_deploys_a_commit_that_contains_the_live_one(self):
        self.running(self.first[:7])
        result = self.run_script("deploy.sh", APP)
        self.assertEqual(result.returncode, 0, result.stderr)
        build, switch = self.changes()
        self.assertIn("--build-only", build)
        self.assertIn(f"SOURCE_COMMIT={self.third}", build)
        self.assertIn(f"--image-label {self.third[:7]}", build)
        self.assertIn(f"--image registry.fly.io/{APP}:{self.third[:7]}", switch)
        self.assertEqual((self.fake / "switched.toml").read_text(), "# third\n")
        locks = self.log("lockf")
        self.assertIn(f"-k {APP_LOCK} bash -euo pipefail -c release", locks)
        self.assertTrue(any(call.startswith(f"-k {SHARED_PLACE} fly deploy") for call in locks))

    def test_deploys_the_live_commit_again(self):
        self.running(self.third[:7])
        result = self.run_script("deploy.sh", APP)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.changes()), 2)

    def test_switches_in_the_second_place_when_the_first_is_taken(self):
        self.running(self.first[:7])
        self.held(SHARED_PLACE)
        result = self.run_script("deploy.sh", APP)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(any(call.startswith(f"-k {SECOND_PLACE} fly deploy") for call in self.log("lockf")))

    def test_refuses_an_older_commit_than_the_live_one(self):
        self.git(self.repo, "checkout", "--quiet", self.second)
        self.running(self.third[:7])
        for args in ([APP], ["--dry-run", APP]):
            result = self.run_script("deploy.sh", *args)
            self.assertEqual(result.returncode, 1)
            self.assertIn(self.third, result.stderr)
        self.assertEqual(self.changes(), [])

    def test_refuses_a_live_image_that_names_no_commit(self):
        for label in ["deployment-01JABCDEF", "ab" * 20, ""]:
            self.running(label)
            result = self.run_script("deploy.sh", APP)
            self.assertEqual(result.returncode, 1, label)
        self.assertEqual(self.changes(), [])

    def test_refuses_a_working_tree_with_a_change(self):
        self.running(self.first[:7])
        self.write("platform/page.txt", "changed\n")
        for args in ([APP], ["--dry-run", APP]):
            result = self.run_script("deploy.sh", *args)
            self.assertEqual(result.returncode, 1)
        self.assertEqual(self.log("fly"), [])

    def test_refuses_a_commit_that_is_not_on_origin_main(self):
        self.running(self.third[:7])
        self.write("platform/page.txt", "unpushed\n")
        self.commit("unpushed")
        result = self.run_script("deploy.sh", APP)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.log("fly"), [])

    def test_dry_run_prints_every_command_and_runs_none_that_change_anything(self):
        self.running(self.first[:7])
        result = self.run_script("deploy.sh", "--dry-run", APP)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.changes(), [])
        self.assertEqual(self.log("fly"), [f"image show --app {APP} --json"])
        self.assertNotIn(APP_LOCK, "\n".join(self.log("lockf")))
        build, switch = self.printed(result)
        self.assertIn("fly deploy . --config platform/fly.toml", build)
        self.assertIn(f"SOURCE_COMMIT={self.third}", build)
        self.assertIn(f"lockf -k {SHARED_PLACE} fly deploy", switch)
        self.assertIn(f"--image registry.fly.io/{APP}:{self.third[:7]}", switch)

    def test_rejects_other_arguments(self):
        self.running(self.first[:7])
        for args in ([], [APP, "--dry-run"], ["--force", APP], [APP, APP]):
            result = self.run_script("deploy.sh", *args)
            self.assertEqual(result.returncode, 2, args)
        self.assertEqual(self.log("fly"), [])


class RollbackTest(Fixture):
    def setUp(self):
        super().setUp()
        # v1 ran `first`, v2 `second` (a new migration), v3 failed, v4 runs `third`.
        self.releases(
            (4, "complete", self.third),
            (3, "failed", self.second),
            (2, "complete", self.second),
            (1, "complete", self.first),
        )
        self.running(self.third[:7])
        (self.fake / "site").write_text(capabilities(self.third))

    def test_switches_to_a_release_with_the_same_migrations_and_its_own_configuration(self):
        (self.fake / "site-after").write_text(capabilities(self.second))
        result = self.run_script("rollback.sh", APP, "v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        (switch,) = self.changes()
        self.assertIn(f"--image registry.fly.io/{APP}:{self.second[:7]}", switch)
        self.assertIn("--ha=false", switch)
        self.assertNotIn("--build-only", switch)
        self.assertEqual((self.fake / "switched.toml").read_text(), "# second\n")
        self.assertEqual(self.log("curl"), [SITE])
        locks = self.log("lockf")
        self.assertIn(f"-k {APP_LOCK} bash -euo pipefail -c rollback", locks)
        self.assertTrue(any(call.startswith(f"-k {SHARED_PLACE} fly deploy") for call in locks))
        self.assertEqual(list(self.tmp.glob("tmp.*")), [])

    def test_reads_the_site_until_it_names_the_release(self):
        (self.fake / "site-next").write_text(capabilities(self.second))
        result = self.run_script("rollback.sh", APP, "v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.log("curl"), [SITE, SITE])

    def test_rolls_back_a_site_too_broken_to_answer(self):
        (self.fake / "site").unlink()
        (self.fake / "site-after").write_text(capabilities(self.second))
        result = self.run_script("rollback.sh", APP, "v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.changes()), 1)

    def test_fails_when_the_site_never_names_the_release(self):
        result = self.run_script("rollback.sh", APP, "v2")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.changes()), 1)
        self.assertEqual(len(self.log("curl")), 24)
        self.assertIn(self.second, result.stderr)

    def test_refuses_a_release_across_a_migration(self):
        for args in ([APP, "v1"], ["--dry-run", APP, "v1"]):
            result = self.run_script("rollback.sh", *args)
            self.assertEqual(result.returncode, 1)
            self.assertIn("platform/priv/repo/migrations/2_second.exs", result.stderr)
        self.assertEqual(self.changes(), [])

    def test_refuses_a_release_across_a_changed_migration(self):
        self.write("platform/priv/repo/migrations/2_second.exs", "# changed\n")
        changed = self.commit("change the second migration")
        self.git(self.repo, "push", "--quiet", "origin", "main")
        self.running(changed[:7])
        result = self.run_script("rollback.sh", APP, "v4")
        self.assertEqual(result.returncode, 1)
        self.assertIn("2_second.exs", result.stderr)
        self.assertEqual(self.changes(), [])

    def test_refuses_a_release_that_did_not_complete(self):
        result = self.run_script("rollback.sh", APP, "v3")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.changes(), [])

    def test_refuses_a_release_the_app_never_had(self):
        result = self.run_script("rollback.sh", APP, "v9")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.changes(), [])

    def test_refuses_an_image_that_names_no_commit_this_checkout_holds(self):
        self.releases((2, "complete", "cd" * 20))
        result = self.run_script("rollback.sh", APP, "v2")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.changes(), [])

    def test_refuses_when_the_live_image_names_no_commit(self):
        self.running("deployment-01JABCDEF")
        result = self.run_script("rollback.sh", APP, "v2")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.changes(), [])

    def test_dry_run_prints_the_switch_and_runs_nothing_that_changes_anything(self):
        result = self.run_script("rollback.sh", "--dry-run", APP, "v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.changes(), [])
        self.assertEqual(self.log("curl"), [])
        self.assertNotIn(APP_LOCK, "\n".join(self.log("lockf")))
        (printed,) = self.printed(result)
        self.assertIn(f"lockf -k {SHARED_PLACE} fly deploy", printed)
        self.assertIn(f"--image registry.fly.io/{APP}:{self.second[:7]}", printed)
        self.assertEqual(list(self.tmp.glob("tmp.*")), [])

    def test_rejects_other_arguments(self):
        for args in ([APP, "249"], [APP, "v2", "--dry-run"], ["--force", APP, "v2"], [APP], []):
            result = self.run_script("rollback.sh", *args)
            self.assertEqual(result.returncode, 2, args)
        self.assertEqual(self.log("fly"), [])


if __name__ == "__main__":
    unittest.main()
