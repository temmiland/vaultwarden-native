#!/usr/bin/env bash
# One acceptance process: package boundaries -> real native composition/hosting -> opt-in server.
# No signing, upstream edits, release upload, automatic server creation or production mutations.
set -Eeuo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TASK_ROOT"

SERVER_MODE=0
SKIP_PACKAGE_TESTS=0
for argument in "$@"; do
  case "$argument" in
    --with-server)
      [[ "$SERVER_MODE" == 0 ]] || { echo 'Usage: bash Scripts/test-integration.sh [--with-server] [--skip-package-tests]' >&2; exit 2; }
      SERVER_MODE=1
      ;;
    --skip-package-tests)
      [[ "$SKIP_PACKAGE_TESTS" == 0 ]] || { echo 'Usage: bash Scripts/test-integration.sh [--with-server] [--skip-package-tests]' >&2; exit 2; }
      SKIP_PACKAGE_TESTS=1
      ;;
    *)
      echo 'Usage: bash Scripts/test-integration.sh [--with-server] [--skip-package-tests]' >&2
      exit 2
      ;;
  esac
done
if [[ "$SERVER_MODE" == 1 && "$SKIP_PACKAGE_TESTS" == 1 ]]; then
  echo 'Usage: --skip-package-tests cannot be combined with --with-server.' >&2
  exit 2
fi

# Preflight before any build. Messages name the problem, never a configured value.
refuse() { echo "Integration preflight: $1" >&2; exit 2; }
LIVE_KEYS=(VW_TEST_LIVE VW_TEST_ALLOW_WRITES VW_TEST_SERVER_URL VW_TEST_SERVER_VERSION VW_TEST_EMAIL
  VW_TEST_PASSWORD VW_TEST_PASSKEY_CIPHER_ID VW_TEST_TOTP VW_TEST_EPHEMERAL_LOOPBACK)
if [[ "$SERVER_MODE" == 1 ]]; then
  [[ "${VW_TEST_ALLOW_WRITES:-}" == "isolated-synthetic-account" ]] ||
    refuse 'server tests require explicit isolated-synthetic-account write consent.'
  for key in VW_TEST_SERVER_URL VW_TEST_SERVER_VERSION VW_TEST_EMAIL VW_TEST_PASSWORD VW_TEST_PASSKEY_CIPHER_ID; do
    [[ -n "${!key:-}" ]] || refuse "missing required test configuration: $key"
  done
  [[ "$VW_TEST_SERVER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] ||
    refuse 'VW_TEST_SERVER_VERSION must be a concrete version such as 1.34.3, not a moving tag.'
  [[ -z "${VW_TEST_TOTP:-}" || "$VW_TEST_TOTP" =~ ^[0-9]{6}$ ]] ||
    refuse 'VW_TEST_TOTP must be a fresh six-digit code when set.'
fi
TASK_IOS_DESTINATION="${VW_IOS_TEST_DESTINATION:-}"
if [[ -z "$TASK_IOS_DESTINATION" ]]; then
  # Select before the long package/macOS steps so a missing runtime fails immediately.
  TASK_SIMULATOR_ID="$(xcrun simctl list devices available -j | swift Scripts/select-test-simulator.swift)" ||
    refuse 'no iOS simulator destination; see the message above.'
  TASK_IOS_DESTINATION="platform=iOS Simulator,id=$TASK_SIMULATOR_ID"
elif [[ "$TASK_IOS_DESTINATION" == 'platform=iOS Simulator,id='* &&
        "$TASK_IOS_DESTINATION" != *,id=*,* ]]; then
  TASK_REQUESTED_SIMULATOR_ID="${TASK_IOS_DESTINATION#platform=iOS Simulator,id=}"
  TASK_SIMULATOR_ID="$(xcrun simctl list devices available -j |
    swift Scripts/select-test-simulator.swift --id "$TASK_REQUESTED_SIMULATOR_ID")" ||
    refuse 'explicit iOS simulator destination is unavailable, ambiguous or invalid.'
  TASK_IOS_DESTINATION="platform=iOS Simulator,id=$TASK_SIMULATOR_ID"
else
  refuse 'VW_IOS_TEST_DESTINATION must use "platform=iOS Simulator,id=<UUID>"; select a concrete simulator ID.'
fi

STEP='preflight'
trap 'echo "Integration step failed: $STEP. Nothing after this step ran." >&2' ERR
step() { STEP="$1"; echo "==> $1"; }
# Check that CoreSimulator can actually start the selected runtime before spending time on package
# builds. `simctl list devices` can advertise devices whose mounted runtime is unusable.
step 'boot selected iOS simulator runtime preflight'
xcrun simctl bootstatus "$TASK_SIMULATOR_ID" -b >/dev/null 2>&1 ||
  refuse 'selected iOS simulator could not boot; repair or reinstall its existing Xcode runtime before building.'
# Only the final live package step may see server configuration or credentials. Package baseline,
# Xcode manifests/result bundles and the native runner never receive any VW_TEST_* value.
UNSET_LIVE=()
for key in "${LIVE_KEYS[@]}"; do UNSET_LIVE+=(-u "$key"); done
without_live() { env "${UNSET_LIVE[@]}" "$@"; }

export TMPDIR=/private/tmp
# Temporary DerivedData avoided a bundle-load stall seen on an external workspace volume; the
# cause is not proven. Override with a test-local path if needed.
TASK_DERIVED_ROOT="${VW_INTEGRATION_DERIVED_DATA_ROOT:-/private/tmp/vaultwarden-platform-integration-${UID}}"

step 'architecture rules'
without_live swift Scripts/check-architecture.swift
if [[ "$SKIP_PACKAGE_TESTS" == 0 ]]; then
  step 'package tests (AppModules, VaultwardenSDK)'
  without_live bash Scripts/test-packages.sh
fi
step 'generate Xcode project'
without_live bash Scripts/generate-xcodeproj.sh

step "macOS integration bundle (results: $TASK_DERIVED_ROOT/macOS/Logs/Test)"
without_live xcodebuild \
  -project Vaultwarden.xcodeproj -scheme VaultwardenMacIntegration \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -derivedDataPath "$TASK_DERIVED_ROOT/macOS" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  CODE_SIGNING_ALLOWED=NO test

step "iOS integration bundle on $TASK_IOS_DESTINATION (results: $TASK_DERIVED_ROOT/iOS/Logs/Test)"
without_live xcodebuild \
  -project Vaultwarden.xcodeproj -scheme VaultwardenIOSIntegration \
  -destination "$TASK_IOS_DESTINATION" -parallel-testing-enabled NO \
  -derivedDataPath "$TASK_DERIVED_ROOT/iOS" \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 300 \
  CODE_SIGNING_ALLOWED=NO test

if [[ "$SERVER_MODE" == 1 ]]; then
  step 'opt-in live server contract'
  LIVE_OUTPUT="$(mktemp -d "$TMPDIR/vaultwarden-live-contract.XXXXXX")"
  trap 'rm -rf "$LIVE_OUTPUT"' EXIT
  # Reuses the package build from the baseline step. The test prints stage names only; its raw
  # output is still not a publishable artifact and is deleted on exit.
  (cd Packages/AppModules && env -u VW_TEST_EPHEMERAL_LOOPBACK VW_TEST_LIVE=1 swift test --filter LiveServerContractTests --no-parallel) 2>&1 |
    tee "$LIVE_OUTPUT/output.txt"
  # A skipped or partially executed contract must never look like a pass.
  grep -q '^SERVER CONTRACT: all stages passed' "$LIVE_OUTPUT/output.txt" ||
    { STEP='opt-in live server contract (did not complete)'; false; }
  echo 'Integrated acceptance passed, including the opt-in server contract stages listed above.'
else
  echo 'Native integration passed. SERVER CONTRACT: NOT RUN (no server configured for this invocation).'
fi
