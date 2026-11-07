#!/usr/bin/env bash
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vaultwarden-architecture.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
mkdir -p "$CHECK_ROOT/Packages/AppModules"
cp -R "$REPOSITORY_ROOT/Packages/AppModules/Sources" "$CHECK_ROOT/Packages/AppModules/Sources"
cp "$REPOSITORY_ROOT/Packages/AppModules/Package.swift" "$CHECK_ROOT/Packages/AppModules/Package.swift"
swift "$REPOSITORY_ROOT/Scripts/check-architecture.swift" --root "$CHECK_ROOT"
# Files here are disposable negative fixtures, not product/upstream edits.
reject_fixture() {
  local relative="$1"
  local mutation="$2"
  printf '\n%s\n' "$mutation" >> "$CHECK_ROOT/Packages/AppModules/Sources/$relative"
  if swift "$REPOSITORY_ROOT/Scripts/check-architecture.swift" --root "$CHECK_ROOT"; then
    echo "Architecture checker accepted forbidden fixture: $relative" >&2
    exit 1
  fi
  cp "$REPOSITORY_ROOT/Packages/AppModules/Sources/$relative" "$CHECK_ROOT/Packages/AppModules/Sources/$relative"
}
reject_fixture VaultPresentation/VaultModel.swift 'import Networking'
reject_fixture Data/AuthCredentialStore.swift 'import BitwardenSdk'
reject_fixture Domain/Domain.swift 'import SecurityStorage'
reject_fixture SendPresentation/Models/SendModel.swift 'let forbiddenFactory = Factory.live()'
reject_fixture Data/DefaultSendRepository.swift 'let forbiddenTransport = URLSessionHTTPClient()'
reject_fixture AutoFillFeature/CredentialListView.swift 'import AutoFillData'
echo "Six negative architecture fixtures rejected as expected."
