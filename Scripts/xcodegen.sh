#!/usr/bin/env bash
# Shared local/CI tool pin. The verified release is used even when another xcodegen is on PATH.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="2.46.0"
ZIP_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
TOOL_ROOT="$REPOSITORY_ROOT/.build/tools/xcodegen-$VERSION"
mkdir -p "$TOOL_ROOT"
if [[ ! -f "$TOOL_ROOT/xcodegen.zip" ]]; then
  DOWNLOAD_PATH="$(mktemp "$TOOL_ROOT/download.XXXXXX")"
  trap 'rm -f "$DOWNLOAD_PATH"' EXIT
  curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 20 --max-time 300 \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip" \
    --output "$DOWNLOAD_PATH"
  [[ "$(shasum -a 256 "$DOWNLOAD_PATH" | awk '{print $1}')" == "$ZIP_SHA256" ]] || {
    echo "Downloaded tool archive hash mismatch; refusing execution" >&2; exit 1;
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
