#!/usr/bin/env bash
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.63.0"
ZIP_SHA256="28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f"
TOOL_ROOT="$REPOSITORY_ROOT/.build/tools/swiftformat-$VERSION"
mkdir -p "$TOOL_ROOT"
if [[ ! -f "$TOOL_ROOT/swiftformat.zip" ]]; then
  curl --fail --location --silent --show-error \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/$VERSION/swiftformat.zip" \
    --output "$TOOL_ROOT/swiftformat.zip"
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
