#!/usr/bin/env bash
# Execute the repository's real Swift/Rust smoke against a separately rebuilt framework.
# Copies source/tests unchanged into its own scratch package; no installed SDK overwrite.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 1 ]] || { echo "Usage: bash Scripts/test-rebuilt-sdk.sh BUILD_ROOT" >&2; exit 2; }
BUILD_ROOT="$(cd "$1" && pwd)"
bash "$REPOSITORY_ROOT/Scripts/build-sdk.sh" --verify-build "$BUILD_ROOT"
FRAMEWORK="$BUILD_ROOT/sdk/crates/bitwarden-uniffi/swift/BitwardenFFI.xcframework"
TEST_ROOT="$(mktemp -d "$BUILD_ROOT/smoke.XXXXXX")"
mkdir -p "$TEST_ROOT/package/Frameworks"
cp "$REPOSITORY_ROOT/Packages/VaultwardenSDK/Package.swift" "$TEST_ROOT/package/Package.swift"
cp -R "$REPOSITORY_ROOT/Packages/VaultwardenSDK/Sources" "$TEST_ROOT/package/Sources"
cp -R "$REPOSITORY_ROOT/Packages/VaultwardenSDK/Tests" "$TEST_ROOT/package/Tests"
ln -s "$FRAMEWORK" "$TEST_ROOT/package/Frameworks/BitwardenFFI.xcframework"
env TMPDIR=/private/tmp swift test --package-path "$TEST_ROOT/package" --scratch-path "$TEST_ROOT/build" \
  --build-system native --no-parallel
echo "Fresh SDK smoke passed in $TEST_ROOT; existing SDK/checkouts unchanged."
