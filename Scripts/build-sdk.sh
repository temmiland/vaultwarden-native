#!/usr/bin/env bash
# Build in an isolated clone only. Never checkout/patch existing sdk-internal or rewrite
# committed generated Swift bindings during ordinary builds. --upgrade explicitly replaces the
# generated bindings and local binary, retaining the previous SDK inside the isolated build root.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_REVISION="a13b4c4e1fa3685280241f417920fd19d7ef24a6"
RUST_TOOLCHAIN="1.99.0"
SDK_LOCK_SHA256="4d87866952641365ab38c937087c1b1e2f42d343a5c45b48353b10acc764ae38"
PATCH_SHA256="b824cd9c8fba29af01b0f1782f5314721cf10532d180a66303b9aa484a91c70c"
PATCH="$REPOSITORY_ROOT/Scripts/patches/0001-add-macos-target-to-xcframework-build.patch"
DEPENDENCY_PATCH="$REPOSITORY_ROOT/Scripts/patches/0003-update-sdk-dependencies.patch"
DEPENDENCY_PATCH_SHA256="44e11046b48fb4b31ebb9a5ea01368fc1dee42a987162de08fda19e78f343aaa"
PACKAGE_DIR="$REPOSITORY_ROOT/Packages/VaultwardenSDK"
MODE="${1:---build}"
RESUME_ROOT=""
if [[ "$MODE" == "--verify-build" ]]; then
  [[ $# == 2 ]] || { echo "Usage: bash Scripts/build-sdk.sh --verify-build PATH" >&2; exit 2; }
elif [[ "$MODE" == "--upgrade" && $# == 2 ]]; then
  RESUME_ROOT="$(cd "$2" && pwd)"
  [[ "$(dirname "$RESUME_ROOT")" == "$REPOSITORY_ROOT/.build/sdk-isolated" && "${RESUME_ROOT##*/}" == build.* ]] || {
    echo "Resume only an explicit build.* directory under this repository's .build/sdk-isolated." >&2; exit 2;
  }
elif [[ $# -gt 1 || ! "$MODE" =~ ^--(check|build|install|upgrade)$ ]]; then
  echo "Usage: bash Scripts/build-sdk.sh [--check|--build|--install|--upgrade [BUILD_ROOT]|--verify-build PATH]" >&2
  exit 2
fi
ACTUAL_PATCH_SHA256="$(shasum -a 256 "$PATCH" | awk '{print $1}')"
[[ "$ACTUAL_PATCH_SHA256" == "$PATCH_SHA256" ]] || { echo "SDK patch hash mismatch" >&2; exit 1; }
[[ "$(shasum -a 256 "$DEPENDENCY_PATCH" | awk '{print $1}')" == "$DEPENDENCY_PATCH_SHA256" ]] || {
  echo "SDK dependency patch hash mismatch" >&2; exit 1;
}
verify_build() {
  local build_root="$1"
  local sdk_source="$build_root/sdk"
  local swift_dir="$sdk_source/crates/bitwarden-uniffi/swift"
  [[ "$(git -C "$sdk_source" rev-parse HEAD)" == "$SDK_REVISION" ]] || { echo "Unexpected SDK source revision" >&2; exit 1; }
  local expected_lock actual_lock
  expected_lock="$SDK_LOCK_SHA256"
  actual_lock="$(shasum -a 256 "$sdk_source/Cargo.lock" | awk '{print $1}')"
  [[ "$expected_lock" == "$actual_lock" ]] || { echo "Cargo.lock differs from the reviewed dependency patch" >&2; exit 1; }
  # Upstream's source directory carries .gitignore; it is repository metadata, not a generated
  # binding. Compare every other file, including unexpected Swift/support additions.
  diff -qr -x .gitignore "$PACKAGE_DIR/Sources/BitwardenSdk" "$swift_dir/Sources/BitwardenSdk"
  diff -qr -x .gitignore "$PACKAGE_DIR/Sources/BitwardenSdkSupport" "$swift_dir/Sources/BitwardenSdkSupport"
  swift "$REPOSITORY_ROOT/Scripts/sdk-artifact-inventory.swift" "$swift_dir/BitwardenFFI.xcframework" > "$build_root/artifact-inventory.json"
  (cd "$sdk_source" && RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN" cargo metadata --locked --format-version 1 > "$build_root/cargo-metadata.json")
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
command -v rustup >/dev/null || { echo "rustup is required (toolchain $RUST_TOOLCHAIN)." >&2; exit 1; }
command -v cargo >/dev/null || { echo "cargo from rustup must be on PATH." >&2; exit 1; }
mkdir -p "$REPOSITORY_ROOT/.build/sdk-isolated"
BUILD_ROOT="${RESUME_ROOT:-$(mktemp -d "$REPOSITORY_ROOT/.build/sdk-isolated/build.XXXXXX")}"
SDK_SOURCE="$BUILD_ROOT/sdk"
# Reuse git objects read-only; uncommitted upstream changes are not copied.
if [[ -n "$RESUME_ROOT" ]]; then
  [[ "$(git -C "$SDK_SOURCE" rev-parse HEAD)" == "$SDK_REVISION" ]] || { echo "Unexpected resumed SDK revision" >&2; exit 1; }
  git -C "$SDK_SOURCE" diff -- crates/bitwarden-uniffi/swift/build.sh | cmp -s "$PATCH" - || {
    echo "Resumed SDK build patch differs from the reviewed patch" >&2; exit 1;
  }
  git -C "$SDK_SOURCE" diff -- Cargo.lock | cmp -s "$DEPENDENCY_PATCH" - || {
    echo "Resumed SDK dependency patch differs from the reviewed patch" >&2; exit 1;
  }
elif git -C "$REPOSITORY_ROOT/sdk-internal" cat-file -e "$SDK_REVISION^{commit}" 2>/dev/null; then
  git clone --quiet --no-hardlinks --no-checkout "$REPOSITORY_ROOT/sdk-internal" "$SDK_SOURCE"
else
  git clone --quiet --no-checkout https://github.com/bitwarden/sdk-internal.git "$SDK_SOURCE"
fi
if [[ -z "$RESUME_ROOT" ]]; then
  git -C "$SDK_SOURCE" checkout --quiet --detach "$SDK_REVISION"
  [[ "$(git -C "$SDK_SOURCE" rev-parse HEAD)" == "$SDK_REVISION" ]] || exit 1
  git -C "$SDK_SOURCE" apply --check "$PATCH"
  git -C "$SDK_SOURCE" apply "$PATCH"
  git -C "$SDK_SOURCE" apply --check "$DEPENDENCY_PATCH"
  git -C "$SDK_SOURCE" apply "$DEPENDENCY_PATCH"
fi
grep -qx "channel = \"$RUST_TOOLCHAIN\"" "$SDK_SOURCE/rust-toolchain.toml" || {
  echo "Unexpected Rust toolchain in pinned upstream" >&2; exit 1;
}
export RUSTUP_TOOLCHAIN="$RUST_TOOLCHAIN"
rustup target add aarch64-apple-ios-sim aarch64-apple-ios x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin
LOCK_SHA256="$(shasum -a 256 "$SDK_SOURCE/Cargo.lock" | awk '{print $1}')"
[[ "$LOCK_SHA256" == "$SDK_LOCK_SHA256" ]] || { echo "Unexpected patched Cargo.lock" >&2; exit 1; }
SWIFT_DIR="$SDK_SOURCE/crates/bitwarden-uniffi/swift"
# The reviewed build patch enforces --locked and retains upstream's dependency/license guards.
(cd "$SWIFT_DIR" && BUILD_MACOS=true DEBUG_MODE=false ./build.sh)
[[ "$(shasum -a 256 "$SDK_SOURCE/Cargo.lock" | awk '{print $1}')" == "$LOCK_SHA256" ]] || {
  echo "Cargo.lock changed; refusing SDK output" >&2; exit 1;
}
if [[ "$MODE" == "--upgrade" ]]; then
  python3 - "$SWIFT_DIR" "$PACKAGE_DIR" "$BUILD_ROOT" <<'PY'
import os, pathlib, shutil, sys
source, package, build = map(pathlib.Path, sys.argv[1:])
staging = build / "upgrade-staging"
backups = build / "previous-sdk"
staging.mkdir(); backups.mkdir()
replacements = []
for module in ("BitwardenSdk", "BitwardenSdkSupport"):
    staged = staging / module
    shutil.copytree(source / "Sources" / module, staged, ignore=shutil.ignore_patterns(".gitignore"))
    replacements.append((package / "Sources" / module, staged, backups / module))
framework = "BitwardenFFI.xcframework"
shutil.copytree(source / framework, staging / framework, symlinks=True)
replacements.append((package / "Frameworks" / framework, staging / framework, backups / framework))
changed = []
try:
    for destination, staged, backup in replacements:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if os.path.lexists(destination):
            os.replace(destination, backup)
        changed.append((destination, backup))
        os.replace(staged, destination)
except BaseException:
    for destination, backup in reversed(changed):
        if destination.is_symlink(): destination.unlink()
        elif destination.exists(): shutil.rmtree(destination)
        if os.path.lexists(backup): os.replace(backup, destination)
    raise
print("Previous bindings/framework retained at", backups)
PY
fi
verify_build "$BUILD_ROOT"
if [[ "$MODE" == "--install" ]]; then
  mkdir -p "$PACKAGE_DIR/Frameworks"
  [[ ! -e "$PACKAGE_DIR/Frameworks/BitwardenFFI.xcframework" ]] || { echo "Artifact installed concurrently; refusing overwrite" >&2; exit 1; }
  cp -R "$SWIFT_DIR/BitwardenFFI.xcframework" "$PACKAGE_DIR/Frameworks/BitwardenFFI.xcframework"
fi
echo "Built SDK in $BUILD_ROOT (retained for provenance/review; gitignored)."
if [[ "$MODE" == "--upgrade" ]]; then
  echo "Generated bindings and local framework upgraded; prior SDK retained for rollback."
else
  echo "No existing upstream checkout or committed generated source was modified."
fi
