#!/usr/bin/env bash
# Negative/positive fixtures for the integration runner's preflight and the simulator selector.
# Synthetic values only. Build tools are stubbed, so a regressed preflight fails fast instead of
# starting package/Xcode work, and no fixture value may ever appear in the runner's output.
set -euo pipefail
REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/vaultwarden-integration-preflight.XXXXXX")"
trap 'rm -rf "$CHECK_ROOT"' EXIT
cd "$REPOSITORY_ROOT"
SWIFT="$(command -v swift)"

fail() { echo "Preflight fixture failed: $1" >&2; exit 1; }

# --- Simulator selector -------------------------------------------------------------------------
select_from() {
  local json="$1"
  shift
  printf '%s' "$json" | "$SWIFT" Scripts/select-test-simulator.swift "$@" 2> "$CHECK_ROOT/selector.err"
}
ios='com.apple.CoreSimulator.SimRuntime.iOS-27-0'
phone() { printf '{"name":"%s","udid":"%s","isAvailable":%s,"state":"%s"}' "$1" "$2" "$3" "$4"; }
low='00000000-0000-4000-8000-000000000001'
high='00000000-0000-4000-8000-000000000002'

selected="$(select_from "{\"devices\":{\"$ios\":[$(phone 'iPhone A' "$low" true Shutdown),$(phone 'iPhone B' "$high" true Booted)]}}")"
[[ "$selected" == "$high" ]] || fail 'a booted iPhone must be preferred'
selected="$(select_from "{\"devices\":{\"$ios\":[$(phone 'iPhone B' "$high" true Shutdown),$(phone 'iPhone A' "$low" true Shutdown)]}}")"
[[ "$selected" == "$low" ]] || fail 'selection without a booted device must be stable'
selected="$(select_from "{\"devices\":{\"$ios\":[$(phone 'iPhone A' "$low" false Booted),$(phone 'iPhone B' "$high" true Shutdown)]}}")"
[[ "$selected" == "$high" ]] || fail 'an unavailable device must be ignored'

reject_selection() {
  if select_from "$1" > /dev/null; then fail "selector accepted: $2"; fi
  grep -q "$3" "$CHECK_ROOT/selector.err" || fail "selector gave an unclear message for: $2"
}
reject_selection "{\"devices\":{\"$ios\":[$(phone 'iPad Pro' "$low" true Booted)]}}" 'only an iPad' 'no available iPhone'
reject_selection "{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.watchOS-11-0\":[$(phone 'iPhone Watch' "$low" true Booted)]}}" \
  'a non-iOS runtime' 'no available iPhone'
reject_selection "{\"devices\":{\"$ios\":[$(phone 'iPhone A' 'not-a-uuid' true Booted)]}}" 'an invalid UDID' 'no available iPhone'
reject_selection '{"devices":{}}' 'no devices' 'no available iPhone'
reject_selection '{"devices":' 'malformed JSON' 'not valid JSON'
echo 'Simulator selector: 3 positive and 5 negative fixtures behaved as expected.'

selected="$(select_from "{\"devices\":{\"$ios\":[$(phone 'iPad Fixture' "$high" true Shutdown)]}}" --id "$high")"
[[ "$selected" == "$high" ]] || fail 'an explicit iPad ID must resolve'
for json in \
  "{\"devices\":{\"$ios\":[$(phone 'iPhone Fixture' "$high" false Shutdown)]}}" \
  "{\"devices\":{\"$ios\":[$(phone 'iPhone A' "$high" true Shutdown),$(phone 'iPhone B' "$high" true Shutdown)]}}" \
  "{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.watchOS-11-0\":[$(phone 'iPhone Fixture' "$high" true Shutdown)]}}"; do
  if select_from "$json" --id "$high" > /dev/null; then fail 'explicit unavailable/ambiguous/non-iOS ID accepted'; fi
done
if select_from '{"devices":{}}' --id not-a-uuid > /dev/null; then fail 'malformed explicit UUID accepted'; fi
echo 'Explicit simulator selector: one positive and four negative fixtures behaved as expected.'

# --- Runner preflight ---------------------------------------------------------------------------
mkdir "$CHECK_ROOT/bin"
for tool in xcodebuild xcrun swift xcodegen; do
  printf '#!/bin/sh\necho "unexpected build step: %s" >&2\nexit 99\n' "$tool" > "$CHECK_ROOT/bin/$tool"
  chmod +x "$CHECK_ROOT/bin/$tool"
done
# Keep the actual Swift selector available while all build tools remain stubbed, so the JSON and
# boot-failure cases below exercise the real preflight path rather than a fake `swift` error.
printf '#!/bin/sh\nif [ "$1" = Scripts/select-test-simulator.swift ]; then exec "%s" "$@"; fi\nif [ -n "${VW_TEST_EPHEMERAL_LOOPBACK:-}" ]; then echo "loopback flag leaked to baseline" >&2; exit 98; fi\necho "unexpected build step: swift" >&2\nexit 99\n' \
  "$SWIFT" > "$CHECK_ROOT/bin/swift"
SECRET_EMAIL='fixture-email@example.invalid'
SECRET_PASSWORD='fixture-password-value'
valid_server=(VW_TEST_ALLOW_WRITES=isolated-synthetic-account VW_TEST_SERVER_URL=https://vault.example.invalid
  VW_TEST_SERVER_VERSION=1.34.3 "VW_TEST_EMAIL=$SECRET_EMAIL" "VW_TEST_PASSWORD=$SECRET_PASSWORD"
  VW_TEST_PASSKEY_CIPHER_ID=00000000-0000-4000-8000-000000000003)

reject_run() {
  local description="$1" expected="$2"
  shift 2
  set +e
  env -i HOME="$HOME" PATH="$CHECK_ROOT/bin:/usr/bin:/bin" TMPDIR="$CHECK_ROOT" "$@" > "$CHECK_ROOT/runner.out" 2>&1
  local status=$?
  set -e
  [[ "$status" == 2 ]] || fail "runner exit $status instead of preflight refusal for: $description"
  grep -q "$expected" "$CHECK_ROOT/runner.out" || fail "runner gave an unclear message for: $description"
  if grep -q -e "$SECRET_EMAIL" -e "$SECRET_PASSWORD" "$CHECK_ROOT/runner.out"; then
    fail "runner printed a configured value for: $description"
  fi
}
runner=(bash Scripts/test-integration.sh)
reject_run 'unknown argument' 'Usage:' "${runner[@]}" --bogus
reject_run 'extra argument' 'Usage:' "${runner[@]}" --with-server extra
reject_run 'package skip with live server' 'cannot be combined' "${runner[@]}" --with-server --skip-package-tests
reject_run 'missing consent' 'write consent' "${runner[@]}" --with-server
reject_run 'wrong consent' 'write consent' VW_TEST_ALLOW_WRITES=production "${runner[@]}" --with-server
for missing in VW_TEST_SERVER_URL VW_TEST_SERVER_VERSION VW_TEST_EMAIL VW_TEST_PASSWORD VW_TEST_PASSKEY_CIPHER_ID; do
  remaining=()
  for assignment in "${valid_server[@]}"; do [[ "$assignment" == "$missing="* ]] || remaining+=("$assignment"); done
  reject_run "missing $missing" "missing required test configuration: $missing" "${remaining[@]}" "${runner[@]}" --with-server
done
reject_run 'moving version tag' 'concrete version' "${valid_server[@]}" VW_TEST_SERVER_VERSION=latest \
  "${runner[@]}" --with-server
reject_run 'malformed TOTP' 'six-digit' "${valid_server[@]}" VW_TEST_TOTP=12ab56 "${runner[@]}" --with-server
reject_run 'non-simulator destination' 'iOS Simulator' VW_IOS_TEST_DESTINATION=platform=macOS "${runner[@]}"
reject_run 'ambiguous name destination' 'concrete simulator ID' \
  'VW_IOS_TEST_DESTINATION=platform=iOS Simulator,name=iPhone Fixture' "${runner[@]}"
reject_run 'extra destination field' 'concrete simulator ID' \
  "VW_IOS_TEST_DESTINATION=platform=iOS Simulator,id=$high,OS=latest" "${runner[@]}"
reject_run 'no simulator runtime' 'no iOS simulator destination' "${runner[@]}"

# A runtime can be advertised as available but fail when CoreSimulator attempts to mount/boot it.
# This must fail before package and Xcode builds.
cat > "$CHECK_ROOT/bin/xcrun" <<'SH'
#!/bin/sh
if [ "$*" = 'simctl list devices available -j' ]; then
  printf '%s\n' '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"name":"iPhone Fixture","udid":"00000000-0000-4000-8000-000000000004","isAvailable":true,"state":"Shutdown"}]}}'
  exit 0
fi
if [ "$*" = 'simctl bootstatus 00000000-0000-4000-8000-000000000004 -b' ]; then
  if [ "${CHECK_BOOT_SUCCEEDS:-}" = 1 ]; then
    : > "$CHECK_BOOT_MARKER"
    exit 0
  fi
  exit 1
fi
echo 'unexpected simulator preflight command' >&2
exit 99
SH
chmod +x "$CHECK_ROOT/bin/xcrun"
reject_run 'runtime cannot boot' 'selected iOS simulator could not boot' "${runner[@]}"
reject_run 'explicit runtime cannot boot' 'selected iOS simulator could not boot' \
  'VW_IOS_TEST_DESTINATION=platform=iOS Simulator,id=00000000-0000-4000-8000-000000000004' "${runner[@]}"
reject_run 'explicit unavailable ID' 'explicit iOS simulator destination' \
  "VW_IOS_TEST_DESTINATION=platform=iOS Simulator,id=$high" "${runner[@]}"
reject_run 'explicit invalid UUID' 'explicit iOS simulator destination' \
  'VW_IOS_TEST_DESTINATION=platform=iOS Simulator,id=invalid' "${runner[@]}"

# A valid explicit destination must boot before the first build step. The Swift shim stops that
# first build with 99, so this positive fixture cannot accidentally run packages or Xcode builds.
set +e
env -i HOME="$HOME" PATH="$CHECK_ROOT/bin:/usr/bin:/bin" TMPDIR="$CHECK_ROOT" \
  CHECK_BOOT_SUCCEEDS=1 CHECK_BOOT_MARKER="$CHECK_ROOT/booted" \
  VW_TEST_EPHEMERAL_LOOPBACK=http://127.0.0.1:65000 \
  'VW_IOS_TEST_DESTINATION=platform=iOS Simulator,id=00000000-0000-4000-8000-000000000004' \
  "${runner[@]}" > "$CHECK_ROOT/runner.out" 2>&1
status=$?
set -e
[[ "$status" == 99 && -f "$CHECK_ROOT/booted" ]] || fail 'explicit target did not boot before build'
grep -q 'unexpected build step: swift' "$CHECK_ROOT/runner.out" || fail 'positive fixture did not reach build boundary'
echo 'Integration runner: 19 preflight refusals and one boot-before-build fixture passed, without printing values.'
