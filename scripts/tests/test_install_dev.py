"""Exercise app replacement/rollback in a temporary Applications folder, with no real processes."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
MOCK = r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ["INSTALL_TEST_ROOT"])
with (root / "commands.jsonl").open("a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "swift":
    if os.environ.get("FAIL_BUILD"):
        sys.exit(1)
    if "--show-bin-path" in args:
        print(root / "binary")
elif name == "git":
    print("v0.24" if "describe" in args else "123")
elif name == "codesign":
    sys.exit(1 if os.environ.get("FAIL_SIGN") else 0)
elif name == "pgrep":
    sys.exit(0 if (root / "running").exists() else 1)
elif name == "pkill":
    if not os.environ.get("REFUSE_QUIT"):
        (root / "running").unlink(missing_ok=True)
elif name == "open":
    if os.environ.get("FAIL_LAUNCH") and not (root / "launch_failed").exists():
        (root / "launch_failed").touch()
        sys.exit(1)
    (root / "running").touch()
elif name == "mv":
    if os.environ.get("FAIL_INSTALL") and ".dinky-dev." in args[0] and args[0].endswith("/Dinky Dev.app"):
        sys.exit(1)
    os.execv("/bin/mv", ["mv", *args])
elif name != "sleep":
    sys.exit("Unexpected command " + name)
'''


class InstallDevTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dinky-install-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, INSTALL_TEST_ROOT=str(self.root),
                        DINKY_APPLICATIONS_DIR=str(self.root / "Applications"),
                        DINKY_BIN_DIR=str(self.root / "cli-bin"), IDENTITY="-")
        for key in ("VERSION", "BUILD", "FAIL_BUILD", "FAIL_SIGN", "FAIL_INSTALL", "FAIL_LAUNCH", "REFUSE_QUIT"):
            self.env.pop(key, None)
        (self.root / "Applications").mkdir()
        self.cli = self.root / "cli-bin/dinky"
        self.cli.parent.mkdir()
        self.cli.symlink_to("/Applications/dinky.app/Contents/MacOS/dinky")
        (self.root / "scripts").mkdir()
        shutil.copy2(ROOT / "scripts/install-dev.sh", self.root / "scripts/install-dev.sh")
        (self.root / "Resources").mkdir()
        shutil.copy2(ROOT / "Resources/Info.plist", self.root / "Resources/Info.plist")
        binary = self.root / "binary/dinky"
        binary.parent.mkdir()
        binary.write_text("new binary")
        binary.chmod(0o755)
        framework = self.root / ".build/artifacts/sparkle/Sparkle/macos-arm64_x86_64/Sparkle.framework"
        (framework / "Versions/B").mkdir(parents=True)
        (framework / "Versions/Current").symlink_to("B")
        self.app = self.root / "Applications/Dinky Dev.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        (self.app / "Contents/MacOS/dinky").write_text("old binary")
        (self.root / "running").touch()
        mocks = self.root / "mocks"
        mocks.mkdir()
        for name in ("swift", "git", "codesign", "pgrep", "pkill", "open", "mv", "sleep"):
            path = mocks / name
            path.write_text(f"#!{sys.executable}\n" + MOCK)
            path.chmod(0o755)
        self.env["PATH"] = str(mocks) + os.pathsep + self.env["PATH"]

    def install(self):
        return subprocess.run(["bash", "scripts/install-dev.sh"], cwd=self.root, env=self.env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def commands(self):
        return [json.loads(line) for line in (self.root / "commands.jsonl").read_text().splitlines()]

    def assert_old_app(self):
        self.assertEqual((self.app / "Contents/MacOS/dinky").read_text(), "old binary")
        self.assertFalse(list((self.root / "Applications").glob(".dinky-dev.*")))
        self.assertEqual(os.readlink(self.cli), "/Applications/dinky.app/Contents/MacOS/dinky")

    def test_build_sign_quit_install_and_launch_with_backup(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.app / "Contents/MacOS/dinky").read_text(), "new binary")
        info = plistlib.loads((self.app / "Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "com.brnbw.dinky.dev")
        self.assertEqual(info["CFBundleShortVersionString"], "0.24")
        self.assertNotIn("SUFeedURL", info)
        backups = list((self.root / "build/dev-app-backups").glob("*/Dinky Dev.app/Contents/MacOS/dinky"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old binary")
        commands = self.commands()
        names = [c[0] for c in commands]
        self.assertLess(max(i for i, name in enumerate(names) if name == "codesign"), names.index("pkill"))
        self.assertLess(names.index("pkill"), names.index("open"))
        self.assertEqual(next(c for c in commands if c[0] == "pkill"), ["pkill", "-TERM", "-x", "dinky"])
        self.assertEqual(next(c for c in commands if c[0] == "open")[1], str(self.app))
        self.assertEqual(os.readlink(self.cli), str(self.app / "Contents/MacOS/dinky"))

    def test_build_or_sign_failure_leaves_running_app_untouched(self):
        for key in ("FAIL_BUILD", "FAIL_SIGN"):
            self.env[key] = "1"
            result = self.install()
            self.env.pop(key)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assert_old_app()
            self.assertTrue((self.root / "running").exists())
        self.assertNotIn("pkill", [c[0] for c in self.commands()])

    def test_install_or_launch_failure_restores_and_restarts_old_app(self):
        for key in ("FAIL_INSTALL", "FAIL_LAUNCH"):
            self.env[key] = "1"
            result = self.install()
            self.env.pop(key)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assert_old_app()
            self.assertTrue((self.root / "running").exists())

    def test_refuses_to_replace_app_that_does_not_quit(self):
        self.env["REFUSE_QUIT"] = "1"
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not quit", result.stdout)
        self.assert_old_app()
        self.assertNotIn("mv", [c[0] for c in self.commands()])

    def test_installs_cli_when_none_exists_and_removes_it_on_launch_failure(self):
        self.cli.unlink()
        self.env["FAIL_LAUNCH"] = "1"
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.cli.is_symlink())
        self.assertEqual((self.app / "Contents/MacOS/dinky").read_text(), "old binary")
        self.env.pop("FAIL_LAUNCH")
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(os.readlink(self.cli), str(self.app / "Contents/MacOS/dinky"))

    def test_refuses_to_overwrite_a_regular_cli_file(self):
        self.cli.unlink()
        self.cli.write_text("another installation")
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-symlink CLI", result.stdout)
        self.assertEqual(self.cli.read_text(), "another installation")
        self.assertEqual((self.app / "Contents/MacOS/dinky").read_text(), "old binary")


if __name__ == "__main__":
    unittest.main()
