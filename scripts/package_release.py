"""Build an installable Lightroom plugin archive and a SHA-256 checksum."""

import argparse
import hashlib
import re
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile


def package_release(root: Path, output_dir: Path, tag: str) -> tuple[Path, Path]:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("Release tag must use vMAJOR.MINOR.PATCH")
    plugin = root / "FrameExport.lrplugin"
    for required in ("Info.lua", "ExportFilter.lua", "Frame.lua", "Magick.lua",
                     "Runtime.lua", "Updater.lua", "UpdateCore.lua", "PluginInfo.lua",
                     "Init.lua", "Shutdown.lua"):
        if not (plugin / required).is_file():
            raise ValueError(f"Missing plugin file: {required}")
    info = (plugin / "Info.lua").read_text(encoding="utf-8")
    version = re.search(
        r"VERSION\s*=\s*\{\s*major\s*=\s*(\d+)\s*,\s*minor\s*=\s*(\d+)"
        r"\s*,\s*revision\s*=\s*(\d+)",
        info,
    )
    if not version or tag != "v" + ".".join(version.groups()):
        raise ValueError("Release tag must match VERSION in FrameExport.lrplugin/Info.lua")
    readme = root / "README.md"
    if not readme.is_file():
        raise ValueError("Missing README.md")
    files = [readme]
    for path in sorted(plugin.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Plugin must not contain symlinks: {path}")
        if path.is_file() and not any(part.startswith(".") for part in path.relative_to(plugin).parts):
            files.append(path)
    output_dir.mkdir(parents=True, exist_ok=True)
    archive = output_dir / f"FrameExport-{tag}.zip"
    # The updater reads stored ZIP entries directly in Lua on macOS and Windows.
    with ZipFile(archive, "w", ZIP_STORED) as output:
        for path in files:
            output.write(path, path.relative_to(root).as_posix())
    checksum = archive.with_suffix(".zip.sha256")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum.write_text(
        f"{digest}  {archive.name}\n",
        encoding="ascii",
    )
    (output_dir / "FrameExport-update.txt").write_text(
        f"FrameExport update manifest 1\nversion={tag}\narchive={archive.name}\nsha256={digest}\n",
        encoding="ascii",
    )
    return archive, checksum


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("dist"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    try:
        for path in package_release(root, args.output_dir.resolve(), args.tag):
            print(path)
        print(args.output_dir.resolve() / "FrameExport-update.txt")
    except ValueError as error:
        parser.exit(1, f"Packaging failed: {error}\n")


if __name__ == "__main__":
    main()
