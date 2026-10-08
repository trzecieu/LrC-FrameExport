import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

from test_release import package_release


class UpdaterTests(unittest.TestCase):
    def test_lua_updater_with_real_archives_and_files(self):
        source = Path(__file__).resolve().parents[1]
        runtime = shutil.which("lua5.1") or shutil.which("luatex")
        if not runtime:
            self.fail("Updater tests require lua5.1 or LuaTeX")
        with tempfile.TemporaryDirectory(prefix="frameexport-updater-") as temporary:
            root = Path(temporary)
            for directory, version in (("installed", "1.0.0"), ("release", "1.0.1")):
                plugin = root / directory / "FrameExport.lrplugin"
                shutil.copytree(source / "FrameExport.lrplugin", plugin)
                info = plugin / "Info.lua"
                a, b, c = version.split(".")
                info.write_text(re.sub(
                    r"VERSION\s*=\s*\{[^}]+\}",
                    f"VERSION = {{ major = {a}, minor = {b}, revision = {c}, build = 1 }}",
                    info.read_text(),
                ))
                if directory == "installed":
                    for module in plugin.glob("*.lua"):
                        module.write_text(module.read_text() + "\n-- previous-version fixture\n")
                shutil.copy2(source / "README.md", root / directory / "README.md")
            archive, _ = package_release(root / "release", root / "assets", "v1.0.1")
            with ZipFile(archive) as valid:
                entries = {name: valid.read(name) for name in valid.namelist()}
            for case in ("compressed", "traversal", "missing", "duplicate", "symlink", "wrong-version"):
                with ZipFile(root / (case + ".zip"), "w",
                             ZIP_DEFLATED if case == "compressed" else ZIP_STORED) as output:
                    for name, contents in entries.items():
                        if case == "missing" and name.endswith("/Updater.lua"):
                            continue
                        if case == "wrong-version" and name.endswith("/Info.lua"):
                            contents = contents.replace(b"minor = 0", b"minor = 1")
                        output.writestr(name, contents)
                    if case == "traversal":
                        output.writestr("FrameExport.lrplugin/../outside.lua", b"bad")
                    elif case == "duplicate":
                        # Duplicate names are deliberate parser rejection fixtures.
                        import warnings
                        with warnings.catch_warnings():
                            warnings.simplefilter("ignore", UserWarning)
                            output.writestr("FrameExport.lrplugin/Info.lua", b"bad")
                    elif case == "symlink":
                        link = ZipInfo("FrameExport.lrplugin/link.lua")
                        link.create_system = 3
                        link.external_attr = 0o120777 << 16
                        output.writestr(link, b"../../outside")
            command = [runtime]
            if Path(runtime).name == "luatex":
                command += ["--luaonly"]
            result = subprocess.run(
                command + ["tests/updater.lua", str(root)], cwd=source,
                text=True, capture_output=True, timeout=30,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS:", result.stdout)
            print(result.stdout.strip())


if __name__ == "__main__":
    unittest.main()
