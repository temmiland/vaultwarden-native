#!/usr/bin/env bash
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.63.0"
RELEASE_ASSET_ID="536986489"
ZIP_SHA256="28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f"
TOOL_ROOT="$REPOSITORY_ROOT/.build/tools/swiftformat-$VERSION"
mkdir -p "$TOOL_ROOT"
if [[ ! -f "$TOOL_ROOT/swiftformat.zip" ]]; then
  DOWNLOAD_PATH="$(mktemp "$TOOL_ROOT/download.XXXXXX")"
  trap 'rm -f "$DOWNLOAD_PATH"' EXIT
  DOWNLOAD_VERIFIED=false
  # Both URLs address the same pinned official asset. A partial transfer or an API JSON
  # response must never become an executable tool cache entry.
  for DOWNLOAD_URL in \
    "https://api.github.com/repos/nicklockwood/SwiftFormat/releases/assets/$RELEASE_ASSET_ID" \
    "https://github.com/nicklockwood/SwiftFormat/releases/download/$VERSION/swiftformat.zip"
  do
    : > "$DOWNLOAD_PATH"
    if curl --fail --location --silent --show-error \
      --retry 2 --retry-all-errors --retry-delay 2 --retry-max-time 60 --connect-timeout 15 --max-time 45 \
      --header 'Accept: application/octet-stream' --header 'X-GitHub-Api-Version: 2022-11-28' \
      "$DOWNLOAD_URL" --output "$DOWNLOAD_PATH"; then
      if [[ "$(shasum -a 256 "$DOWNLOAD_PATH" | awk '{print $1}')" == "$ZIP_SHA256" ]]; then
        DOWNLOAD_VERIFIED=true
        break
      fi
      echo "Official tool download has an unexpected checksum; trying the alternate endpoint." >&2
    else
      echo "Official tool download failed; trying the alternate endpoint." >&2
    fi
  done
  [[ "$DOWNLOAD_VERIFIED" == true ]] || {
    echo "No verified tool archive could be downloaded; refusing execution." >&2; exit 1;
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
