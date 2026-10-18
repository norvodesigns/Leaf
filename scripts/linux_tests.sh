#!/usr/bin/env bash
# Runs the Foundation-only logic tests (everything in Shared/ plus LeafTests/) on Linux, or on any machine with a
# Swift toolchain and no Xcode. The iPhone app, watch app and the store tests need Xcode and run in CI instead.
#
#   scripts/linux_tests.sh                    # all tests
#   scripts/linux_tests.sh --filter Forecast  # extra arguments go to `swift test`
#
# Set SWIFT_BIN to the toolchain's usr/bin directory if `swift` is not on PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${LEAF_LINUX_TESTS_DIR:-${TMPDIR:-/tmp}/leaf-linux-tests}"
[ -n "${SWIFT_BIN:-}" ] && export PATH="$SWIFT_BIN:$PATH"

mkdir -p "$WORK/Sources" "$WORK/Tests"
ln -sfn "$ROOT/Shared" "$WORK/Sources/LeafCore"
ln -sfn "$ROOT/LeafTests" "$WORK/Tests/LeafCoreTests"
cat > "$WORK/Package.swift" <<'SWIFT'
// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "LeafCore",
    targets: [
        .target(name: "LeafCore", path: "Sources/LeafCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "LeafCoreTests", dependencies: ["LeafCore"], path: "Tests/LeafCoreTests", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
SWIFT

cd "$WORK"
exec swift test "$@"
