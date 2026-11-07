#!/usr/bin/env bash
# Regenerates Vaultwarden.xcodeproj from project.yml via XcodeGen. The .xcodeproj itself is
# gitignored - project.yml is the source of truth; xcodegen.sh owns the verified tool pin.
set -euo pipefail
cd "$(dirname "$0")/.."

bash Scripts/xcodegen.sh generate
echo "Done. Open Vaultwarden.xcodeproj in Xcode (or build with xcodebuild)."
