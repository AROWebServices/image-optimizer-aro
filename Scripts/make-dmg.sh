#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) release and packages it as dist/Image Optimizer ARO.dmg.
#
#   Scripts/make-dmg.sh
#
# The image holds the app, an Applications alias and install notes. The app is signed ad hoc, so on
# another Mac the first launch needs "Open Anyway" in System Settings → Privacy & Security.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${IMAGE_OPTIMIZER_BUILD_DIR:-$HOME/Library/Caches/ImageOptimizer-build}"
APP="$SCRATCH/app-release/Image Optimizer ARO.app"
STAGE="$SCRATCH/dmg-stage"
DIST="$ROOT/dist"
DMG="$DIST/Image Optimizer ARO.dmg"

UNIVERSAL=1 "$ROOT/Scripts/build-with-command-line-tools.sh" release

echo "▸ Staging the disk image…"
rm -rf "$STAGE"; mkdir -p "$STAGE" "$DIST"
ditto "$APP" "$STAGE/Image Optimizer ARO.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Read Me First.txt" <<'NOTES'
Image Optimizer ARO — install notes

1. Drag "Image Optimizer ARO" onto the Applications folder alias in this window.
2. Open it from Applications the first time.

This copy is signed ad hoc rather than with an Apple Developer ID, so macOS will
refuse to open it at first with a message like "Apple could not verify…".
Do this once:

  • Click Done on that message.
  • Open System Settings → Privacy & Security, scroll to the Security section
    and click "Open Anyway" next to Image Optimizer ARO, then confirm.

Alternatively, run this in Terminal after copying the app to Applications:

  xattr -dr com.apple.quarantine "/Applications/Image Optimizer ARO.app"

Requirements: macOS 14 Sonoma or later, Apple Silicon or Intel.
NOTES

echo "▸ Creating $DMG…"
rm -f "$DMG"
hdiutil create -volname "Image Optimizer ARO" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
hdiutil verify -quiet "$DMG"
echo "✓ $DMG"
