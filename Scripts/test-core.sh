#!/bin/zsh
# Runs the OptimizerCore test suite with the Command Line Tools.
# The explicit plugin flag works around a Swift 6.4 CLT quirk where the Swift Testing macro
# plugin is sometimes not found on incremental builds. Xcode does not need it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${IMAGE_OPTIMIZER_BUILD_DIR:-$HOME/Library/Caches/ImageOptimizer-build}"
PLUGIN="$(xcrun --find swift | xargs dirname)/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
FLAGS=()
[[ -f "$PLUGIN" ]] && FLAGS=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
swift test --package-path "$ROOT/OptimizerCore" --scratch-path "$SCRATCH/core" "${FLAGS[@]}" "$@" 2>&1 | grep -v "ld: warning"
