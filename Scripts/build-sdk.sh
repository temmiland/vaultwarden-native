#!/usr/bin/env bash
# Build in an isolated clone only. Never checkout/patch existing sdk-internal or rewrite
# committed generated Swift bindings. --install installs an absent ignored binary only.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_REVISION="fbd21679c1c3690cba424ad3dbb0ba662eb9863e"
PATCH_SHA256="95f74e5f6d544be11f8b3542bbf90dd7ad4fc9ae00ad2ca5f3389041622748df"
PATCH="$REPOSITORY_ROOT/Scripts/patches/0001-add-macos-target-to-xcframework-build.patch"
PACKAGE_DIR="$REPOSITORY_ROOT/Packages/VaultwardenSDK"
MODE="${1:---build}"
if [[ "$MODE" == "--verify-build" ]]; then
  [[ $# == 2 ]] || { echo "Usage: bash Scripts/build-sdk.sh --verify-build PATH" >&2; exit 2; }
elif [[ $# -gt 1 || ! "$MODE" =~ ^--(check|build|install)$ ]]; then
  echo "Usage: bash Scripts/build-sdk.sh [--check|--build|--install|--verify-build PATH]" >&2
  exit 2
fi
ACTUAL_PATCH_SHA256="$(shasum -a 256 "$PATCH" | awk '{print $1}')"
[[ "$ACTUAL_PATCH_SHA256" == "$PATCH_SHA256" ]] || { echo "SDK patch hash mismatch" >&2; exit 1; }
verify_build() {
  local build_root="$1"
  local sdk_source="$build_root/sdk"
  local swift_dir="$sdk_source/crates/bitwarden-uniffi/swift"
  [[ "$(git -C "$sdk_source" rev-parse HEAD)" == "$SDK_REVISION" ]] || { echo "Unexpected SDK source revision" >&2; exit 1; }
  local expected_lock actual_lock
  expected_lock="$(git -C "$sdk_source" show "$SDK_REVISION:Cargo.lock" | shasum -a 256 | awk '{print $1}')"
  actual_lock="$(shasum -a 256 "$sdk_source/Cargo.lock" | awk '{print $1}')"
  [[ "$expected_lock" == "$actual_lock" ]] || { echo "Cargo.lock differs from the source pin" >&2; exit 1; }
  # Upstream's source directory carries .gitignore; it is repository metadata, not a generated
  # binding. Compare every other file, including unexpected Swift/support additions.
  diff -qr -x .gitignore "$PACKAGE_DIR/Sources/BitwardenSdk" "$swift_dir/Sources/BitwardenSdk"
  diff -qr -x .gitignore "$PACKAGE_DIR/Sources/BitwardenSdkSupport" "$swift_dir/Sources/BitwardenSdkSupport"
  swift "$REPOSITORY_ROOT/Scripts/sdk-artifact-inventory.swift" "$swift_dir/BitwardenFFI.xcframework" > "$build_root/artifact-inventory.json"
  (cd "$sdk_source" && RUSTUP_TOOLCHAIN=1.96.0 cargo metadata --locked --format-version 1 > "$build_root/cargo-metadata.json")
  echo "SDK source/lock/generated bindings verified; inventories retained in $build_root."
}
if [[ "$MODE" == "--verify-build" ]]; then
  BUILD_ROOT="$(cd "$2" && pwd)"
  [[ "$(dirname "$BUILD_ROOT")" == "$REPOSITORY_ROOT/.build/sdk-isolated" && "${BUILD_ROOT##*/}" == build.* ]] || {
    echo "Verify only an explicit build.* directory under this repository's .build/sdk-isolated." >&2; exit 2;
  }
  verify_build "$BUILD_ROOT"
  exit 0
fi
if [[ "$MODE" == "--check" ]]; then
  echo "SDK source pin: $SDK_REVISION; build patch hash verified."
  [[ -d "$PACKAGE_DIR/Frameworks/BitwardenFFI.xcframework" ]] || {
    echo "No local SDK artifact; use --install before package/app tests." >&2; exit 1;
  }
  swift "$REPOSITORY_ROOT/Scripts/sdk-artifact-inventory.swift" "$PACKAGE_DIR/Frameworks/BitwardenFFI.xcframework"
  exit 0
fi
if [[ "$MODE" == "--install" && -e "$PACKAGE_DIR/Frameworks/BitwardenFFI.xcframework" ]]; then
  echo "SDK artifact exists. Refusing overwrite; use --check or --build for comparison." >&2
  exit 1
fi
command -v rustup >/dev/null || { echo "rustup is required (toolchain 1.96.0)." >&2; exit 1; }
command -v cargo >/dev/null || { echo "cargo from rustup must be on PATH." >&2; exit 1; }
mkdir -p "$REPOSITORY_ROOT/.build/sdk-isolated"
BUILD_ROOT="$(mktemp -d "$REPOSITORY_ROOT/.build/sdk-isolated/build.XXXXXX")"
SDK_SOURCE="$BUILD_ROOT/sdk"
# Reuse git objects read-only; uncommitted upstream changes are not copied.
if git -C "$REPOSITORY_ROOT/sdk-internal" cat-file -e "$SDK_REVISION^{commit}" 2>/dev/null; then
  git clone --quiet --no-hardlinks --no-checkout "$REPOSITORY_ROOT/sdk-internal" "$SDK_SOURCE"
else
  git clone --quiet --no-checkout https://github.com/bitwarden/sdk-internal.git "$SDK_SOURCE"
fi
git -C "$SDK_SOURCE" checkout --quiet --detach "$SDK_REVISION"
[[ "$(git -C "$SDK_SOURCE" rev-parse HEAD)" == "$SDK_REVISION" ]] || exit 1
git -C "$SDK_SOURCE" apply --check "$PATCH"
git -C "$SDK_SOURCE" apply "$PATCH"
grep -qx 'channel = "1.96.0"' "$SDK_SOURCE/rust-toolchain.toml" || {
  echo "Unexpected Rust toolchain in pinned upstream" >&2; exit 1;
}
export RUSTUP_TOOLCHAIN=1.96.0
rustup target add aarch64-apple-ios-sim aarch64-apple-ios x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin
LOCK_SHA256="$(shasum -a 256 "$SDK_SOURCE/Cargo.lock" | awk '{print $1}')"
SWIFT_DIR="$SDK_SOURCE/crates/bitwarden-uniffi/swift"
# Build-command hardening in the isolated copy only. No API/feature/crypto changes.
sed -i '' -e 's/cargo build /cargo build --locked /g' -e 's/cargo run /cargo run --locked /g' "$SWIFT_DIR/build.sh"
(cd "$SWIFT_DIR" && BUILD_MACOS=true DEBUG_MODE=false ./build.sh)
[[ "$(shasum -a 256 "$SDK_SOURCE/Cargo.lock" | awk '{print $1}')" == "$LOCK_SHA256" ]] || {
  echo "Cargo.lock changed; refusing SDK output" >&2; exit 1;
}
verify_build "$BUILD_ROOT"
if [[ "$MODE" == "--install" ]]; then
  mkdir -p "$PACKAGE_DIR/Frameworks"
  [[ ! -e "$PACKAGE_DIR/Frameworks/BitwardenFFI.xcframework" ]] || { echo "Artifact installed concurrently; refusing overwrite" >&2; exit 1; }
  cp -R "$SWIFT_DIR/BitwardenFFI.xcframework" "$PACKAGE_DIR/Frameworks/BitwardenFFI.xcframework"
fi
echo "Built SDK in $BUILD_ROOT (retained for provenance/review; gitignored)."
echo "No existing upstream checkout or committed generated source was modified."
