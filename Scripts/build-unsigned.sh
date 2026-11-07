#!/usr/bin/env bash
# Generates the Xcode project and builds both app targets without signing. Derived data stays in a
# disposable project-specific directory so the working tree remains source-only.
set -euo pipefail

BUILD_CONFIGURATION="${1:-Debug}"
if [[ $# -gt 1 || ! "$BUILD_CONFIGURATION" =~ ^(Debug|Release)$ ]]; then
  echo "Usage: bash Scripts/build-unsigned.sh [Debug|Release]" >&2
  exit 2
fi

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="$(mktemp -d "${TMPDIR:-/tmp}/vaultwarden-macos-build.XXXXXX")"
trap 'rm -rf "${DERIVED_DATA_PATH}"' EXIT

cd "${REPOSITORY_ROOT}"
./Scripts/generate-xcodeproj.sh

xcodebuild \
  -project Vaultwarden.xcodeproj \
  -scheme VaultwardenMac \
  -configuration "$BUILD_CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}/macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project Vaultwarden.xcodeproj \
  -scheme VaultwardenIOS \
  -configuration "$BUILD_CONFIGURATION" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "${DERIVED_DATA_PATH}/iOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
