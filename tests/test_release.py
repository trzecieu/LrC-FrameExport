import hashlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from package_release import package_release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        source = Path(__file__).resolve().parents[1]
        shutil.copytree(source / "FrameExport.lrplugin", self.root / "FrameExport.lrplugin")
        # Keep the fixture version independent of future plugin version bumps.
        (self.root / "FrameExport.lrplugin/Info.lua").write_text(
            "return { VERSION = { major = 1, minor = 1, revision = 0, build = 1 } }\n"
        )
        shutil.copy2(source / "README.md", self.root / "README.md")
        self.output = Path(self.temporary.name) / "output"

    def test_installable_folder_and_checksum(self):
        (self.root / "FrameExport.lrplugin" / ".DS_Store").write_text("local noise")
        archive, checksum = package_release(self.root, self.output, "v1.1.0")
        with ZipFile(archive) as release:
            self.assertIsNone(release.testzip())
            expected = {"README.md", *(
                path.relative_to(self.root).as_posix()
                for path in (self.root / "FrameExport.lrplugin").glob("*.lua")
            )}
            self.assertEqual(set(release.namelist()), expected)
            for name in expected:
                self.assertEqual(release.read(name), (self.root / name).read_bytes())
                self.assertEqual(release.getinfo(name).compress_type, ZIP_STORED)
            release.extractall(self.output / "extracted")
        self.assertTrue((self.output / "extracted/FrameExport.lrplugin/Info.lua").is_file())
        self.assertEqual(
            checksum.read_text(),
            f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}\n",
        )
        self.assertEqual((self.output / "FrameExport-update.txt").read_text(),
                         "FrameExport update manifest 1\nversion=v1.1.0\n"
                         f"archive={archive.name}\nsha256={hashlib.sha256(archive.read_bytes()).hexdigest()}\n")

    def test_rejects_mismatched_version_before_writing(self):
        with self.assertRaisesRegex(ValueError, "must match VERSION"):
            package_release(self.root, self.output, "v2.0.0")
        self.assertFalse(self.output.exists())

    def test_accepts_future_version(self):
        (self.root / "FrameExport.lrplugin/Info.lua").write_text(
            "return { VERSION = { major = 2, minor = 3, revision = 4, build = 1 } }\n"
        )
        archive, _ = package_release(self.root, self.output, "v2.3.4")
        self.assertEqual(archive.name, "FrameExport-v2.3.4.zip")

    def test_rejects_missing_runtime_module(self):
        (self.root / "FrameExport.lrplugin/Magick.lua").unlink()
        with self.assertRaisesRegex(ValueError, "Missing plugin file"):
            package_release(self.root, self.output, "v1.1.0")
        self.assertFalse(self.output.exists())

    def test_rejects_invalid_tag(self):
        with self.assertRaisesRegex(ValueError, "vMAJOR.MINOR.PATCH"):
            package_release(self.root, self.output, "../escape")
        self.assertFalse(self.output.exists())

    def test_rejects_symlink(self):
        (self.root / "FrameExport.lrplugin/external.lua").symlink_to(self.root / "README.md")
        with self.assertRaisesRegex(ValueError, "symlinks"):
            package_release(self.root, self.output, "v1.1.0")
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
