#!/usr/bin/env bash
# Local synthetic account only: disposable loopback Vaultwarden, no mounts and no production data.
set -euo pipefail
[[ $# == 0 ]] || { echo 'Usage: bash Scripts/test-disposable-server.sh' >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE='ghcr.io/dani-garcia/vaultwarden@sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f'
CONTAINER="vw-synthetic-$(uuidgen | tr '[:upper:]' '[:lower:]')"
RESULTS="$(mktemp -d "${TMPDIR:-/tmp}/vw-disposable-server.XXXXXX")"
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$RESULTS"
}
trap cleanup EXIT
docker run -d --rm --name "$CONTAINER" -e I_REALLY_WANT_VOLATILE_STORAGE=true \
  -e SIGNUPS_ALLOWED=true -e SIGNUPS_VERIFY=false -e ROCKET_LOG=critical \
  -p 127.0.0.1::80 "$IMAGE" >/dev/null
PORT="$(docker port "$CONTAINER" 80/tcp | sed 's/.*://')"
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo 'Could not determine disposable server port.' >&2; exit 1; }
READY=0
for attempt in {1..45}; do
  if curl -fsS "http://127.0.0.1:$PORT/alive" >/dev/null 2>&1; then READY=1; break; fi
  [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" == true ]] || break
  sleep 1
done
[[ "$READY" == 1 ]] || { echo 'Disposable Vaultwarden did not become ready.' >&2; exit 1; }
cd "$ROOT"
if ! env -u VW_TEST_LIVE -u VW_TEST_ALLOW_WRITES -u VW_TEST_SERVER_URL -u VW_TEST_SERVER_VERSION -u VW_TEST_EMAIL \
  -u VW_TEST_PASSWORD -u VW_TEST_TOTP -u VW_TEST_PASSKEY_CIPHER_ID \
  VW_TEST_EPHEMERAL_LOOPBACK="http://127.0.0.1:$PORT" \
  swift test --package-path Packages/AppModules --filter disposableLocalServerContracts \
  > "$RESULTS/test.log" 2>&1; then
  echo 'Disposable server contract failed; inspect the redacted stage below.' >&2
  grep -E 'LOCAL SERVER:|LOCAL SERVER.*failed|error:' "$RESULTS/test.log" >&2 || true
  exit 1
fi
for required in \
  'LOCAL SERVER: long encrypted filename create/read/delete passed' \
  'LOCAL SERVER: unsupported individual device revocation detected safely'; do
  grep -Fqx "$required" "$RESULTS/test.log" || { echo 'A required disposable-server stage did not complete.' >&2; exit 1; }
done
grep -Fqx 'LOCAL SERVER: login TOTP challenge passed' "$RESULTS/test.log" || {
  echo 'A required disposable-server stage did not complete.' >&2
  exit 1
}
grep -Fqx 'LOCAL SERVER: stale concurrent cipher write was rejected; the accepted field remained intact' \
  "$RESULTS/test.log" || {
    echo 'The concurrent cipher contract did not complete.' >&2
    exit 1
  }
CONCURRENT_RESULT="$(grep -F 'LOCAL SERVER: stale concurrent cipher write was rejected; the accepted field remained intact' \
  "$RESULTS/test.log")"
echo "Disposable Vaultwarden 1.37.5: long Send filename and login TOTP passed; $CONCURRENT_RESULT; individual device revocation is unsupported."
