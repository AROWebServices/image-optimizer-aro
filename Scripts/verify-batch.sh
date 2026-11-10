#!/bin/zsh
# Builds and runs Scripts/VerifyBatch against the core library (Command Line Tools only).
#   Scripts/verify-batch.sh [output-folder]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${IMAGE_OPTIMIZER_BUILD_DIR:-$HOME/Library/Caches/ImageOptimizer-build}"
swift build --package-path "$ROOT/OptimizerCore" --scratch-path "$SCRATCH/core" -c release 2>&1 | grep -v "ld: warning" || true
PRODUCTS="$SCRATCH/core/release"
MODULEMAP="$(find "$SCRATCH/core" -path "*GeneratedModuleMaps*" -name libwebp.modulemap | head -1)"
TARGET="arm64-apple-macos14.0"; [[ "$(uname -m)" == "x86_64" ]] && TARGET="x86_64-apple-macos14.0"
mkdir -p "$SCRATCH/verify"
xcrun --sdk macosx swiftc -O -module-name VerifyBatch -target "$TARGET" -I "$PRODUCTS" -Xcc -fmodule-map-file="$MODULEMAP" \
  "$ROOT/Scripts/VerifyBatch/main.swift" "$PRODUCTS/libOptimizerCore.a" "$PRODUCTS/libwebp.o" \
  -framework AppKit -framework ImageIO -framework CoreImage -framework Accelerate -framework UniformTypeIdentifiers \
  -o "$SCRATCH/verify/verify-batch" 2>&1 | grep -v "ld: warning" || true
"$SCRATCH/verify/verify-batch" "$@"
