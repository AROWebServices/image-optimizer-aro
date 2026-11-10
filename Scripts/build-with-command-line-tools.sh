#!/bin/zsh
# Builds "Image Optimizer ARO.app" with only the Xcode Command Line Tools (no Xcode.app needed).
#
#   Scripts/build-with-command-line-tools.sh [debug|release]
#   UNIVERSAL=1 Scripts/build-with-command-line-tools.sh release   # Apple Silicon + Intel
#
# The core library and libwebp are built with SwiftPM; the SwiftUI app is compiled with swiftc
# and assembled into a minimal .app bundle, signed ad hoc. The bundle is NOT sandboxed
# (sandboxing requires a Developer ID or Xcode signing); use the Xcode project for that.
#
# Build products are written outside the source tree because cloud-synced folders (OneDrive,
# iCloud Drive) add Finder metadata that breaks code signing.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${IMAGE_OPTIMIZER_SOURCE_DIR:-$ROOT/ImageOptimizer}"
SCRATCH="${IMAGE_OPTIMIZER_BUILD_DIR:-$HOME/Library/Caches/ImageOptimizer-build}"
OUT="$SCRATCH/app-$CONFIG"
APP="$OUT/Image Optimizer ARO.app"
ARCHS=("$(uname -m)")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCHS=(arm64 x86_64); fi

echo "▸ Building OptimizerCore ($CONFIG, ${ARCHS[*]}) with SwiftPM…"
ARCH_FLAGS=()
if (( ${#ARCHS[@]} > 1 )); then for a in "${ARCHS[@]}"; do ARCH_FLAGS+=(--arch "$a"); done; fi
swift build --package-path "$ROOT/OptimizerCore" --scratch-path "$SCRATCH/core" -c "$CONFIG" "${ARCH_FLAGS[@]}" 2>&1 | grep -v "ld: warning" || true
if [[ "$CONFIG" == "release" ]]; then OPT="-O"; else OPT="-Onone -g"; fi
if (( ${#ARCHS[@]} > 1 )); then
  # Multi-arch builds go through the Xcode build system, which writes products here.
  PRODUCTS="$SCRATCH/core/out/Products/${(C)CONFIG}"
  [[ -d "$PRODUCTS" ]] || PRODUCTS="$SCRATCH/core/apple/Products/${(C)CONFIG}"
else
  PRODUCTS="$SCRATCH/core/$CONFIG"
fi
[[ -f "$PRODUCTS/libOptimizerCore.a" ]] || { echo "OptimizerCore did not build"; exit 1; }
MODULEMAP="$(find "$SCRATCH/core" -path "*GeneratedModuleMaps*" -name libwebp.modulemap | head -1 || true)"
WEBP_INCLUDE="$(find "$SCRATCH/core/checkouts" -type d -path "*libwebp-Xcode/include" | head -1)"

echo "▸ Compiling the app with swiftc…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# The Command Line Tools lack the SwiftUIMacros plugin that implements `@State` in recent SDKs.
# Compile a temporary copy of the sources in which `@State` is spelled `@CLTState`, a
# module-local property wrapper (Scripts/CLTShims) that forwards to SwiftUI.State.
STAGED="$OUT/sources"
rm -rf "$STAGED"
mkdir -p "$STAGED"
find "$SRC" -name '*.swift' | while read -r file; do
  relative="${file#$SRC/}"
  mkdir -p "$STAGED/$(dirname "$relative")"
  sed -E -e 's/@State([^A-Za-z0-9_])/@CLTState\1/g' -e 's/([^A-Za-z0-9_.])State\((initialValue|wrappedValue):/\1CLTState(\2:/g' "$file" > "$STAGED/$relative"
done
cp "$ROOT"/Scripts/CLTShims/*.swift "$STAGED/"
SOURCES=("${(@f)$(find "$STAGED" -name '*.swift' | sort)}")
EXTRA_MODULE_FLAGS=()
if [[ -n "$MODULEMAP" ]]; then EXTRA_MODULE_FLAGS+=(-Xcc -fmodule-map-file="$MODULEMAP"); fi
if [[ -n "$WEBP_INCLUDE" ]]; then EXTRA_MODULE_FLAGS+=(-I "$WEBP_INCLUDE"); fi
BINARIES=()
for arch in "${ARCHS[@]}"; do
  BIN="$OUT/ImageOptimizer-$arch"
  xcrun --sdk macosx swiftc ${=OPT} -parse-as-library -module-name ImageOptimizer -target "$arch-apple-macos14.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -I "$PRODUCTS" "${EXTRA_MODULE_FLAGS[@]}" \
    "${SOURCES[@]}" \
    "$PRODUCTS/libOptimizerCore.a" "$PRODUCTS/libwebp.o" \
    -framework SwiftUI -framework AppKit -framework ImageIO -framework CoreImage -framework Accelerate -framework UniformTypeIdentifiers \
    -o "$BIN"
  BINARIES+=("$BIN")
done
if (( ${#BINARIES[@]} > 1 )); then
  lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/ImageOptimizer"
else
  mv "${BINARIES[1]}" "$APP/Contents/MacOS/ImageOptimizer"
fi
rm -f "$OUT"/ImageOptimizer-*

echo "▸ Assembling the bundle…"
sed -e 's/\$(DEVELOPMENT_LANGUAGE)/en/' -e 's/\$(EXECUTABLE_NAME)/ImageOptimizer/' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.example.ImageOptimizer/' -e 's/\$(PRODUCT_NAME)/ImageOptimizer/' \
    -e 's/\$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/' -e 's/\$(MARKETING_VERSION)/1.0/' -e 's/\$(CURRENT_PROJECT_VERSION)/1/' \
    -e 's/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/' "$SRC/Resources/Info.plist" > "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null
echo "✓ Built $APP"
echo "  open \"$APP\""
