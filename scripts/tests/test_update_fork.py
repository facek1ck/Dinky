"""Exercise updater safety with real temporary Git repositories; no network or Swift builds."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "update-fork.sh"


class UpdateForkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dinky-update-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, GIT_CONFIG_NOSYSTEM="1",
                        GIT_CONFIG_GLOBAL=os.devnull, GIT_TERMINAL_PROMPT="0",
                        GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.invalid",
                        GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.invalid")
        self.repo = self.root / "checkout"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        (self.repo / "shared").write_text("base\n")
        (self.repo / "scripts").mkdir()
        shutil.copy2(SCRIPT, self.repo / "scripts/update-fork.sh")
        installer = self.repo / "scripts/install-dev.sh"
        installer.write_text('#!/bin/sh\necho installing > installed\nexit "${INSTALL_TEST_EXIT:-0}"\n')
        installer.chmod(0o755)
        self.git("add", ".")
        self.git("commit", "-m", "base")
        for remote in ("upstream", "origin"):
            path = self.root / f"{remote}.git"
            self.run_command(["git", "clone", "--bare", str(self.repo), str(path)])
            self.git("remote", "add", remote, str(path))
        self.git("switch", "-c", "feat/personal")
        (self.repo / "personal").write_text("keep my feature\n")
        self.git("add", ".")
        self.git("commit", "-m", "personal feature")
        self.before = self.git("rev-parse", "HEAD").stdout.strip()
        mocks = self.root / "bin"
        mocks.mkdir()
        for name in ("swift", "python3"):
            path = mocks / name
            path.write_text('#!/bin/sh\nexit "${UPDATE_TEST_EXIT:-0}"\n')
            path.chmod(0o755)
        self.env["PATH"] = str(mocks) + os.pathsep + self.env["PATH"]

    def run_command(self, args, check=True):
        return subprocess.run(args, cwd=self.repo, env=self.env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=check)

    def git(self, *args):
        return self.run_command(["git", *args])

    def update_upstream(self, conflict=False):
        self.git("switch", "main")
        (self.repo / "shared").write_text("upstream\n")
        self.git("add", ".")
        self.git("commit", "-m", "upstream change")
        self.git("push", "upstream", "main")
        upstream = self.git("rev-parse", "HEAD").stdout.strip()
        self.git("switch", "feat/personal")
        if conflict:
            (self.repo / "shared").write_text("personal edit\n")
            self.git("add", ".")
            self.git("commit", "-m", "conflicting feature")
            self.before = self.git("rev-parse", "HEAD").stdout.strip()
        return upstream

    def update(self, *args):
        return self.run_command(["bash", "scripts/update-fork.sh", "--source-only", *args], check=False)

    def backups(self):
        return self.git("for-each-ref", "--format=%(objectname)", "refs/heads/fix/update-backup-*").stdout.split()

    def test_merges_preserves_history_untracked_files_and_pushes(self):
        upstream = self.update_upstream()
        (self.repo / "untracked").write_text("leave alone")
        result = self.update("--push")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.git("merge-base", "--is-ancestor", self.before, "HEAD")
        self.git("merge-base", "--is-ancestor", upstream, "HEAD")
        self.assertEqual((self.repo / "personal").read_text(), "keep my feature\n")
        self.assertEqual((self.repo / "untracked").read_text(), "leave alone")
        self.assertIn(self.before, self.backups())
        self.assertEqual(self.git("rev-parse", "HEAD").stdout,
                         self.git("rev-parse", "origin/feat/personal").stdout)

    def test_refuses_tracked_and_staged_changes(self):
        (self.repo / "personal").write_text("unfinished")
        for staged in (False, True):
            if staged:
                self.git("add", "personal")
            result = self.update()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Commit or stash", result.stdout)
            self.assertEqual((self.repo / "personal").read_text(), "unfinished")
            self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.before)

    def test_conflicts_stop_without_push_and_can_be_aborted(self):
        self.update_upstream(conflict=True)
        result = self.update("--push")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Resolve the conflicts", result.stdout)
        self.assertIn(self.before, self.backups())
        self.git("merge", "--abort")
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.before)
        self.assertNotIn("refs/heads/feat/personal", self.git("ls-remote", "origin").stdout)

    def test_failed_tests_do_not_push(self):
        self.update_upstream()
        self.env["UPDATE_TEST_EXIT"] = "1"
        result = self.update("--push")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tests failed; nothing was pushed", result.stdout)
        self.assertIn(self.before, self.backups())
        self.assertNotIn("refs/heads/feat/personal", self.git("ls-remote", "origin").stdout)

    def test_untracked_collision_does_not_overwrite(self):
        self.git("switch", "main")
        (self.repo / "collision").write_text("upstream")
        self.git("add", ".")
        self.git("commit", "-m", "new upstream file")
        self.git("push", "upstream", "main")
        self.git("switch", "feat/personal")
        (self.repo / "collision").write_text("local work")
        result = self.update()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.repo / "collision").read_text(), "local work")
        self.assertEqual(self.git("rev-parse", "HEAD").stdout.strip(), self.before)

    def test_installs_by_default_and_source_only_skips_install(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.repo / "installed").exists())
        result = self.run_command(["bash", "scripts/update-fork.sh"], check=False)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((self.repo / "installed").exists())

    def test_install_failure_stops_push(self):
        self.env["INSTALL_TEST_EXIT"] = "1"
        result = self.run_command(["bash", "scripts/update-fork.sh", "--push"], check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("refs/heads/feat/personal", self.git("ls-remote", "origin").stdout)


if __name__ == "__main__":
    unittest.main()
