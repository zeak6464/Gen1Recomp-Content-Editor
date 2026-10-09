"""Run updater cleanup against disposable download folders."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CleanupTests(unittest.TestCase):
    def test_cleanup_removes_only_owned_artifacts(self):
        for only in ("", "source-1791544472-1"):
            with self.subTest(only=only), tempfile.TemporaryDirectory(prefix="update ' test ", dir=ROOT / "tests/content-editor") as temp:
                base = Path(temp)
                owned = ["source-1791544472-1", "source-1791544472-2",
                         "source-" + "a" * 40 + ".tar.gz",
                         "runtime-" + "b" * 40 + ".tar.gz"]
                protected = ["mods", "runtime", "source-personal", "source-123",
                             "runtime-not-a-sha.tar.gz", "install.log", "installed.txt"]
                for name in owned + protected:
                    path = base / name
                    if "." in name:
                        path.write_text("keep or delete")
                    else:
                        path.mkdir()
                        (path / "payload").write_text("data")
                script = base / ("cleanup.ps1" if os.name == "nt" else "cleanup.sh")
                env = dict(os.environ, CLEANUP_DIR=temp, CLEANUP_SCRIPT=str(script), CLEANUP_ONLY=only)
                program = '''
package.path = "tools/content-editor/?.lua;" .. package.path
local f = assert(io.open(os.getenv("CLEANUP_SCRIPT"), "wb"))
local only = os.getenv("CLEANUP_ONLY")
f:write(require("UpdateCleanup").script(os.getenv("CLEANUP_DIR"),
  package.config:sub(1,1) == "\\\\", only ~= "" and only or nil))
f:close()
'''
                subprocess.run([os.environ.get("LUA_TEST", "luajit"), "-e", program],
                               cwd=ROOT, env=env, check=True)
                command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"] if os.name == "nt" else ["sh"]
                subprocess.run(command + [str(script)], check=True)
                for name in owned:
                    self.assertEqual((base / name).exists(), bool(only and name != only), name)
                for name in protected:
                    self.assertTrue((base / name).exists(), name)


if __name__ == "__main__":
    unittest.main()
