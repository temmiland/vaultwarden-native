#!/usr/bin/env bash
# Shared local/CI tool pin. The verified release is used even when another xcodegen is on PATH.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="2.46.0"
RELEASE_ASSET_ID="478866069"
ZIP_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
TOOL_ROOT="$REPOSITORY_ROOT/.build/tools/xcodegen-$VERSION"
mkdir -p "$TOOL_ROOT"
if [[ ! -f "$TOOL_ROOT/xcodegen.zip" ]]; then
  DOWNLOAD_PATH="$(mktemp "$TOOL_ROOT/download.XXXXXX")"
  trap 'rm -f "$DOWNLOAD_PATH"' EXIT
  DOWNLOAD_VERIFIED=false
  # Both URLs address the same pinned official asset. A partial transfer or an API JSON
  # response must never become an executable tool cache entry.
  for DOWNLOAD_URL in \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip" \
    "https://api.github.com/repos/yonaskolb/XcodeGen/releases/assets/$RELEASE_ASSET_ID"
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
  mv "$DOWNLOAD_PATH" "$TOOL_ROOT/xcodegen.zip"
  trap - EXIT
fi
[[ "$(shasum -a 256 "$TOOL_ROOT/xcodegen.zip" | awk '{print $1}')" == "$ZIP_SHA256" ]] || {
  echo 'XcodeGen archive hash mismatch; refusing execution' >&2; exit 1;
}
unzip -q -o "$TOOL_ROOT/xcodegen.zip" -d "$TOOL_ROOT/bin"
TOOL_BINARY="$TOOL_ROOT/bin/xcodegen/bin/xcodegen"
[[ "$("$TOOL_BINARY" --version)" == "Version: $VERSION" ]] || {
  echo 'Unexpected XcodeGen version' >&2; exit 1;
}
exec "$TOOL_BINARY" "$@"
