#!/usr/bin/env bash
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.63.0"
ZIP_SHA256="28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f"
TOOL_ROOT="$REPOSITORY_ROOT/.build/tools/swiftformat-$VERSION"
mkdir -p "$TOOL_ROOT"
if [[ ! -f "$TOOL_ROOT/swiftformat.zip" ]]; then
  DOWNLOAD_PATH="$(mktemp "$TOOL_ROOT/download.XXXXXX")"
  trap 'rm -f "$DOWNLOAD_PATH"' EXIT
  curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 --max-time 300 \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/$VERSION/swiftformat.zip" \
    --output "$DOWNLOAD_PATH"
  [[ "$(shasum -a 256 "$DOWNLOAD_PATH" | awk '{print $1}')" == "$ZIP_SHA256" ]] || {
    echo "Downloaded tool archive hash mismatch; refusing execution" >&2; exit 1;
  }
  mv "$DOWNLOAD_PATH" "$TOOL_ROOT/swiftformat.zip"
  trap - EXIT
fi
[[ "$(shasum -a 256 "$TOOL_ROOT/swiftformat.zip" | awk '{print $1}')" == "$ZIP_SHA256" ]] || {
  echo "SwiftFormat archive hash mismatch; refusing execution" >&2; exit 1;
}
unzip -q -o "$TOOL_ROOT/swiftformat.zip" -d "$TOOL_ROOT/bin"
[[ "$("$TOOL_ROOT/bin/swiftformat" --version)" == "$VERSION" ]] || {
  echo "Unexpected SwiftFormat version" >&2; exit 1;
}
"$TOOL_ROOT/bin/swiftformat" "$REPOSITORY_ROOT/App" "$REPOSITORY_ROOT/AutoFillExtension" \
  "$REPOSITORY_ROOT/Composition" "$REPOSITORY_ROOT/Tests" "$REPOSITORY_ROOT/Packages/AppModules" \
  "$REPOSITORY_ROOT/Scripts" --config "$REPOSITORY_ROOT/.swiftformat" "$@"
