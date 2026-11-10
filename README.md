# Image Optimizer ARO for macOS

A native macOS app for preparing images for the web: import one file or whole folders, pick a
format (or let the app choose), resize, set quality, strip metadata and export a batch with a
before/after report. Built with Swift, SwiftUI and the system imaging frameworks, plus a bundled
copy of libwebp because macOS can read WebP but not write it.

Layout: settings sidebar on the left, image queue (list or grid) in the middle, before/after
inspector on the right, and a bottom toolbar with Add Images, Auto Optimize, progress, Pause,
Cancel and Export.

## Features

- **Import**: drag and drop files or folders, Add Images / Add Folder (⌘O / ⇧⌘O), Finder "Open With",
  recursive folder import, duplicate detection, thumbnails with format, dimensions and size, reorder,
  remove, clear.
- **Queue**: drag and drop files or folders, reorder, remove single images, or clear the whole
  queue from the bottom bar, the context menu or Edit → Clear Queue (⇧⌘⌫).
- **Formats**: WebP (lossy, lossless, animated), AVIF, JPEG (progressive), PNG (lossless palette
  optimisation), HEIC, GIF, "Same as original" and **Auto** with a per-file explanation of the choice.
- **Resize**: fit, fill/crop, exact, percentage; longest-edge presets 3840…640 px; aspect lock;
  "Only shrink images, never enlarge"; optional sharpening; EXIF orientation applied first.
- **Quality**: 1–100 slider with format-specific guidance, presets (Maximum compression, Web optimized,
  High quality, Near-lossless, Lossless), artifact warnings, live output-size estimate.
- **Preview**: side-by-side, split slider and press-to-compare modes with zoom to 400 % and a true 100 % view.
- **Auto optimize**: one switch that picks a format per image, shrinks oversized images, keeps
  transparency and animation, removes metadata, never enlarges and reports every decision.
  Advanced: "Use best format automatically" and "Prefer WebP over AVIF".
- **Metadata**: remove all, keep colour profile only, keep copyright/author only, keep all (GPS still
  removed unless you opt in). Wide-gamut images are converted to sRGB with the system colour engine,
  or the profile is embedded if you turn conversion off.
- **Output**: "optimized" subfolder, beside originals, custom folder, or replace originals after an
  explicit confirmation; preserve or flatten folder structure; `-optimized`, `-web`, none or custom
  suffix; rename / skip / overwrite conflict handling; keep the original if the result would be larger.
- **Batch**: bounded parallelism, progress, pause/resume, cancel, per-file status, summary with
  totals, savings, average reduction and failure count. Decimal (kB) or binary (KiB) units.
- **Safeguards**: confirmation before flattening animation, dropping transparency, recompressing an
  already heavily compressed file or replacing originals; outputs are re-opened and verified after
  writing; source files are never modified except by "Replace the originals".
- **Native**: light/dark mode, full keyboard operation and menu bar commands, VoiceOver labels,
  Settings window (⌘,), remembered settings, built-in and custom presets, string catalog for
  localisation, App Sandbox with security-scoped bookmarks.

## Requirements

- macOS 14 Sonoma or later (macOS 14+ is also required for the system AVIF encoder).
- Xcode 16 or later to build the app. The core library and tests also build with just the
  Command Line Tools (see below).
- No external tools. WebP support comes from [libwebp](https://github.com/SDWebImage/libwebp-Xcode)
  compiled from source by Swift Package Manager (fetched on first build).

## Supported formats

| Input | Output |
|---|---|
| JPEG (incl. .jfif), PNG, GIF (incl. animated), WebP (incl. animated), AVIF, HEIC/HEIF, TIFF, BMP, SVG | WebP, AVIF, JPEG, PNG, HEIC, GIF |

- **SVG** is rasterised with AppKit at the chosen output size (set a size in Resize; otherwise the
  file's intrinsic size is used). SVG output is not offered because optimising vector markup is a
  different job; keep the original SVG for scalable use.
- **Animated** GIF, APNG and WebP keep their animation when the output is WebP, GIF or PNG. Any other
  output flattens to the first frame and asks first.
- **Transparency** is preserved for WebP, AVIF, PNG, HEIC and GIF. Converting a transparent image to
  JPEG requires confirmation and fills with white.
- **16-bit** and CMYK sources are converted to 8-bit RGB for the web.

## How automatic format selection works

The rules live in `OptimizerCore/Sources/OptimizerCore/Formats/FormatSelector.swift` as an ordered
table; the first matching rule wins:

1. **Animated input** → animated WebP (GIF/APNG in compatibility mode) so no frame is lost.
2. **SVG** → lossless WebP (PNG in compatibility mode), rendered at the requested size.
3. **Graphic with transparency** → lossless WebP (PNG in compatibility mode).
4. **Graphic / screenshot / text** → indexed PNG if it has ≤ 256 colours, otherwise lossless WebP (PNG in compatibility mode).
5. **Photo with transparency** → AVIF if allowed, else lossy WebP (PNG in compatibility mode).
6. **Photo** → AVIF if allowed, else WebP (JPEG in compatibility mode).

"Photo" versus "graphic" is decided by sampling a 256 px thumbnail: distinct colour count and the
fraction of identical neighbouring pixels. AVIF is only chosen automatically when *Use best format
automatically* is on **and** *Prefer WebP over AVIF* is off; the default favours WebP for browser
support. A manually selected format is always respected; only technically impossible conversions
fall back (e.g. an encoder that this Mac does not have).

## How quality percentages work

The slider is 1–100 for every lossy encoder, but the scales differ:

| Format | Scale | Good web default | Visible artifacts below |
|---|---|---|---|
| JPEG | libjpeg scale | 80–85 | ~70 |
| WebP | libwebp scale (80 ≈ JPEG 85–90, smaller file) | 75–82 | ~60 |
| AVIF | 60–70 already matches JPEG 85; 100 is **not** lossless | 60–75 | ~45 |
| HEIC | HEVC scale, 70–80 ≈ JPEG 85–90 | 75 | ~55 |
| PNG, GIF | always lossless; "optimisation" means palette reduction and metadata removal | – | – |

The app shows the explanation for the selected format in the Quality section and warns when the
value is low enough to cause blocking or banding. Lossless mode exists for WebP and PNG. AVIF has
no lossless mode with the system encoder; requesting it uses quality 99 and says so.

## Building and running

### With Xcode

1. Open `ImageOptimizer.xcodeproj`.
2. Xcode resolves the local `OptimizerCore` package and fetches libwebp (network needed once).
3. Select the **ImageOptimizer** scheme and press Run (⌘R).
4. Tests: Product → Test (⌘U) runs the `OptimizerCoreTests` Swift Testing suite.

Set your team in Signing & Capabilities if you want to run the sandboxed build on another Mac.

### With the Command Line Tools only (no Xcode.app)

```bash
Scripts/build-with-command-line-tools.sh release   # builds ~/Library/Caches/ImageOptimizer-build/app-release/"Image Optimizer ARO.app"
```

```bash
Scripts/test-core.sh                                # swift test for OptimizerCore (85 tests)
```

```bash
Scripts/verify-batch.sh                             # generates sample images, runs a real batch, checks every output
```

The CLT build is ad-hoc signed and **not sandboxed**. It stages a copy of the sources in which
`@State` is spelled `@CLTState` (a thin wrapper around `SwiftUI.State` in `Scripts/CLTShims`) because
recent SDKs implement `@State` as a macro whose plugin only ships with Xcode. The Xcode project
compiles the sources unchanged.

Build products go to `~/Library/Caches/ImageOptimizer-build` (override with
`IMAGE_OPTIMIZER_BUILD_DIR`). Do not build inside a cloud-synced folder such as OneDrive or iCloud
Drive: the sync client adds Finder metadata to build products and `codesign` rejects them.

## Project layout

```
ImageOptimizer.xcodeproj/        App project (file-system-synchronised group, Xcode 16 format)
ImageOptimizer/                  SwiftUI app
  App/                           @main, menu commands, Finder open handler
  Models/                        QueueItem
  ViewModels/                    AppModel (queue, import, export orchestration), PreviewModel
  Services/                      Persistence, preferences, presets, sandbox folder access
  Views/                         Sidebar sections, queue list/grid, inspector + comparison, sheets, components
  Resources/                     Assets, Info.plist, Localizable.xcstrings
OptimizerCore/                   Swift package, no UI, fully testable
  Sources/OptimizerCore/
    Models/                      Settings, presets, analysis and result types
    Analysis/                    ImageAnalyzer, ContentClassifier (photo vs graphic)
    Formats/                     EncoderCapabilities, FormatSelector rule table
    Processing/                  ImageDecoder, Resizer, MetadataFilter, PNGOptimizer, WebPEncoder,
                                 ImageEncoder, OptimizationPipeline (plan → encode → write → verify)
    Export/                      OutputNamer (paths, suffixes, conflicts), BatchProcessor, bookmarks
  Tests/OptimizerCoreTests/      Swift Testing suites (generated images, no binary fixtures)
Scripts/                         CLT build, test and verification scripts
```

## Installing on other Macs

```bash
Scripts/make-dmg.sh
```

This builds a universal release (Apple Silicon and Intel, macOS 14 or later) and writes
`dist/Image Optimizer ARO.dmg`, containing the app, an Applications alias and install notes. Copy
the .dmg to the other Mac, open it and drag the app into Applications.

The Command Line Tools build is signed ad hoc, not with a Developer ID, so the first launch on
another Mac is blocked by Gatekeeper. Open System Settings → Privacy & Security and click
"Open Anyway", or remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/Image Optimizer ARO.app"
```

## Technical notes

- Decoding uses `CGImageSourceCreateThumbnailAtIndex` with a maximum pixel size, so a 24-megapixel
  file being resized to 2560 px never exists in memory at full size, and EXIF orientation is applied
  during decode. Each batch item runs inside an autorelease pool; parallelism defaults to half the
  CPU cores (max 4) and is adjustable in Settings.
- Resizing draws through Core Graphics with high-quality interpolation after the thumbnail decode;
  colour conversion to sRGB happens in the same pass. Sharpening (optional) is a gentle Core Image
  unsharp mask.
- WebP goes through libwebp's advanced API (`use_sharp_yuv`, configurable `method`/effort,
  `WebPAnimEncoder` for animation, `WebPMux` for ICC and XMP chunks). JPEG, PNG, AVIF, HEIC and GIF
  use ImageIO. PNGs with ≤ 256 colours are rewritten as indexed images; unused alpha channels are dropped.
- Metadata is handled through `CGImageMetadata`: GPS tags are removed by path prefix, orientation
  is normalised to 1 and EXIF pixel dimensions are updated. WebP cannot carry EXIF, so "Keep all"
  stores XMP instead and the app says so.
- Every written file is re-opened and decoded at thumbnail size before it is reported as done; a
  file that fails this check is deleted and reported as a failure.
- The main window's three columns are laid out by SwiftUI alone (an `HStack` with draggable
  dividers; widths are remembered). `NavigationSplitView` and `.inspector` were dropped on purpose:
  on macOS 26/27 their `NSSplitView` backing aborted with "needing another Update Constraints in
  Window pass" when a column's minimum size changed, for example while restoring the window.
- Inside the App Sandbox the app can only write where you pointed it. It remembers folders with
  security-scoped bookmarks and asks once per destination folder (Settings → Folders lists them).

## Privacy and metadata behaviour

- By default all EXIF, IPTC and XMP metadata is removed and only the colour profile is kept.
- GPS location is **never** written unless you choose "Keep all metadata" *and* switch off
  "Remove GPS location"; the UI then shows a warning.
- Nothing leaves your Mac. There is no network access, analytics or external encoder.

## Known limitations

- The Xcode project was authored by hand on a Mac without Xcode; it follows the Xcode 16
  synchronised-group format and parses correctly, but it has not been opened in Xcode yet. The app
  itself was compiled, launched and exercised with the Command Line Tools build. If Xcode
  reports a problem, create a new macOS App target, delete its template files, add the
  `ImageOptimizer` folder and the local `OptimizerCore` package, and point the target at
  `ImageOptimizer/Resources/Info.plist` and `ImageOptimizer/ImageOptimizer.entitlements`.
- AVIF encoding depends on the system encoder (macOS 14+); there is no lossless AVIF, and animated
  AVIF is not produced.
- Animated WebP input decodes through ImageIO; very long animations are kept in memory frame by frame
  while re-encoding.
- "Replace the originals" when the format changes writes the new file beside the original and moves
  the original to the Trash (it cannot literally overwrite `photo.jpg` with `photo.webp`).
- WebP XMP metadata is written but ImageIO does not read it back; other tools (exiftool, browsers
  with developer tools) do.
- The before/after preview is downscaled to 4096 px on the longest side for very large outputs;
  the reported size is still the exact encoded size.
- No app icon artwork is included (the asset catalogue has an empty AppIcon set).

## Testing

```bash
Scripts/test-core.sh
```

or in Xcode with ⌘U. The suite (`OptimizerCore/Tests/OptimizerCoreTests`) covers: format rules,
resize geometry (fit, fill, exact, percentage, only-shrink), analysis (photo/graphic, transparency,
EXIF orientation, animation, wide gamut, corrupted and unsupported files), every encoder round-trip
including transparency and quality ordering, progressive JPEG, PNG palette optimisation, animated
WebP/GIF/APNG, metadata policies and GPS removal, sRGB conversion and profile retention, naming and
conflict handling, the full pipeline (upright output, kept-original-when-larger, confirmations,
SVG rasterisation, folder structure, replace-originals), batch processing, pause, cancellation and
failure counting.

All test images are generated in code so the repository has no binary fixtures. To run the pipeline
against your own photos, point the suite at a folder:

```bash
OPTIMIZER_SAMPLE_DIR=~/Pictures/samples Scripts/test-core.sh
```

`Scripts/verify-batch.sh [folder]` is an end-to-end check that builds a sample set (photographs, a
6000×4000 image, EXIF-rotated JPEGs with GPS, transparent PNGs, Display P3, HEIC, TIFF, animated GIF,
SVG and a corrupted file), runs Auto optimize through the real `BatchProcessor`, verifies that every
output opens with the right size, orientation, transparency and animation, and confirms that no
source file changed.

## Licence notes

libwebp is © Google, BSD-3-Clause, pulled in as a Swift package from SDWebImage/libwebp-Xcode.
