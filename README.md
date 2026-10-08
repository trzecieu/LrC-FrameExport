# FrameExport for Lightroom Classic

FrameExport adds a solid border to exported photos. It runs as a **Lightroom Classic export filter** on macOS and Windows, without changing the catalog photo or its Develop settings. Lightroom cloud and mobile editions do not support this plugin SDK.

Lightroom hosts the plugin so that adding a border becomes the final export step and its settings can be saved in an export preset. Photoshop would require another application or additional automation. Since the Lightroom SDK cannot extend an image's canvas, the plugin uses a local installation of **ImageMagick 7**.

## Installation

1. Install ImageMagick 7 from <https://imagemagick.org/script/download.php>. On macOS with Homebrew, run `brew install imagemagick`. On Windows, use the installer from the ImageMagick website.
2. Download `FrameExport-vX.Y.Z.zip` from the repository's [Releases](https://github.com/trzecieu/ttt/releases) page when a release is available. Extract it and keep the entire `FrameExport.lrplugin` folder in a permanent location. Alternatively, use that folder from a checkout of this repository.
3. In Lightroom Classic, open **File → Plug-in Manager → Add** and select the `FrameExport.lrplugin` folder.
4. Open **Export**. Under **Post-Process Actions**, add **FrameExport**. Leave the executable path empty for automatic detection; the detection result appears below it.
5. Select **JPEG** or **TIFF**, set the border percentage and color, and export. Click the color swatch to open Lightroom's native color picker, or enter an exact HEX code next to it. Both controls stay synchronized. You can save these settings in an export preset.

### ImageMagick detection

The plugin first searches the Lightroom process's `PATH`, then common Homebrew locations (`/opt/homebrew/bin`, `/usr/local/bin`), MacPorts (`/opt/local/bin`), or `ImageMagick-7*` directories under Windows Program Files. It checks that the executable is ImageMagick 7. Lightroom launched from the desktop may have a different PATH from your terminal, which is why installation directories are also checked.

For a custom installation, click **Choose…** to select the executable using a file dialog. The optional path takes precedence over automatic detection. **Detect again** clears that path and restarts the search. The executable is checked again during export, independently of the status displayed in the dialog. After upgrading the plugin, click Detect again if an old preset contains an example path from the previous version.

Do not place another filter that changes image dimensions after this filter. Test with exports to a new folder first. On Windows, executable and export paths cannot contain `"`, `%`, or `!`; the plugin rejects these characters because of how the system shell interprets them.

## Border settings

- **Canvas width increase (%)**: the total increase in canvas width, relative to the exported photo's width, split equally between the left and right sides. **The same thickness in pixels is applied to the top and bottom**, regardless of the photo's aspect ratio. There is one thickness setting.
- **Border color**: use the native picker or a hexadecimal `#RRGGBB` value, such as `#FFFFFF`, `#000000`, or `#E8DCC8`. Values are interpreted in the export's color space; choose sRGB for predictable screen colors. The border is opaque.
- The percentage range is 0–200; use a decimal point for fractional values. Border thickness is rounded to the nearest whole pixel. A very small percentage may produce zero pixels. A percentage of zero leaves the export unchanged, without re-encoding or requiring ImageMagick.

Example: a **4000 × 3000** photo with a **10%** canvas width increase gets a **200 px border on every side**, producing a **4400 × 3400** image. For a 100 px border on that photo, enter 5%.

Formula: `thickness = round(photo width × percentage / 200)`. Version 1.1 preserves the previous width percentage semantics and preset setting; the old height percentage is ignored. Consider saving your preset again after upgrading.

Percentages apply to the file **after Lightroom's cropping and resizing**. The border increases the final dimensions beyond the limit configured under Image Sizing. Lightroom applies its watermark and output sharpening before the border is added; the watermark stays on the photo rather than on the border.

## Formats, quality, and file handling

JPEG is re-encoded using the quality selected in Lightroom's export settings, adding another lossy compression step. The JPEG size limit in KB is not guaranteed after adding the border. For maximum quality, export TIFF: the plugin uses lossless ZIP compression and preserves image bit depth. ImageMagick carries over ICC profiles and metadata, but check unusual metadata on your own files; identical preservation of every field is not guaranteed.

PSD, DNG, and Original exports are not supported. The plugin reports an export error instead of silently leaving an apparently successful result without a border. ImageMagick errors are passed back to Lightroom. Output is first written to a temporary file next to the export and replaces the export only after successful processing. If replacement fails, the plugin attempts to restore the original export; if restoration is impossible, the error identifies the retained backup. The export directory must be writable and have enough space for the output and an export backup.

## Releases

The GitHub Actions release workflow attaches two files to a release:

- `FrameExport-vX.Y.Z.zip`, containing `FrameExport.lrplugin/` and this README. Extract the ZIP before adding the plugin to Lightroom. ImageMagick is installed separately.
- `FrameExport-vX.Y.Z.zip.sha256`, containing the ZIP's SHA-256 checksum.

GitHub also provides its usual source archives; use the **FrameExport ZIP asset** for installation. GitHub release assets are files, so the plugin folder is delivered inside that ZIP.

To publish a version, update `VERSION` in `FrameExport.lrplugin/Info.lua`, commit and push the change, then create and push a matching tag:

```sh
# Example for the current plugin version:
git tag v1.1.1
git push origin v1.1.1
```

Use `vMAJOR.MINOR.PATCH`, matching the plugin version. The workflow verifies the version, packages the plugin, and creates a GitHub release with generated notes, or uploads the assets to an existing release. Publishing a release in GitHub also triggers packaging. To rebuild assets for an existing tag, run **Release plugin** from the Actions tab and provide that tag. These triggers use the workflow at the selected tag; the tagged commit must contain the workflow and packaging script.

Local packaging requires only Python 3:

```sh
python3 -m unittest discover -s tests -p 'test_release.py'
python3 scripts/package_release.py --tag v1.1.1 --output-dir /tmp/frameexport-release
```

Adding the workflow does not publish a version by itself. A tag push, published release, or manual workflow run starts publication.

## Validation

From the repository root on Linux with ImageMagick 7 and LuaTeX:

```sh
luatex --luaonly tests/run.lua
```

The tests run real ImageMagick and check equal border thickness on landscape and portrait photos, border color, preservation of 16-bit TIFF pixels, JPEG output, zero percentage, errors, and file restoration. PATH discovery is tested on Linux; Windows/macOS installation locations and two-way color picker/HEX binding are tested with a simulated SDK. Lightroom Classic and Windows have not been run in this cloud environment.

Before regular use, test automatic ImageMagick detection, the color picker, saving/loading a preset, and landscape/portrait JPEG and TIFF exports in Lightroom Classic. Check output dimensions, ICC profiles, metadata, and watermark placement. This desktop integration check is necessary and is not replaced by the Linux tests.
