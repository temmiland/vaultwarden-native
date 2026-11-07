# Unknown cipher fields must not become lossy writes

Status: implemented, 2026-09-28. Local verification is recorded in
[Verification](../Verification.md). No new server compatibility.

## Problem

Synthesized Codable decoding ignored unknown JSON fields at the cipher root and inside login,
URI, passkey, card, identity, note, SSH key, custom-field, history, permission and attachment
objects. The resulting SDK model could still be editable. A later full replacement from that
model had no way to preserve the omitted fields, including during passkey registration.

## Decision

Recognize the existing writable wire shape before allowing mutations. Unknown keys, including
null/empty values and later array elements, make that item read-only. Do not invent their
semantics, add SDK fields, or blindly echo opaque server fields into a request. Only the existing
root/attachment `object` response discriminators are explicitly non-payload metadata.

`CipherResponseDTO` records a nonsecret, externally read-only safety Boolean. Its SDK conversion
forces `edit=false`; `CipherRequestDTO` rejects read-only backing. The projected encrypted DTO
also contains `edit=false` and `_nativeHasUnrecognizedPayload=true`, preserving write denial
when decoding the cache after unknown values have been omitted. Older readers that honor the
existing edit flag also see read-only. A false incoming Boolean cannot hide an unknown key.

App source permissions inspect retained encrypted backing independently of SDK decryption.
Summary/detail permissions expose `unsupportedPayload` and a clear official-client repair hint.
Draft creation, save, delete and attachment mutations stop before HTTP; save rechecks the
current backing after encryption. Existing known-field reading, password/TOTP and attachment
download remain governed by their unchanged secret-access checks.

The AutoFill decrypted wrapper also retains the write fence independently of the SDK view.
Registration revalidates the latest encrypted cache before each write stage; a retained earlier
selection cannot bypass the fence. The request builder is the final common create/update/
passkey guard. A fresh known-only server response replaces the earlier fence; it is not a
permanent preference or a reason to alter server data.

## Boundaries

This is server-data preservation **by refusing unsupported writes**, not an arbitrary unknown-
JSON round trip. Unknown values are not retained in the local projected DTO or displayed; the
server remains authoritative. No promise about unknown access-policy semantics or future crypto
formats follows. Blob/malformed payloads retain their existing unavailable-item behavior.

Caches written by earlier versions may already have lost unknown fields without an edit flag.
The information cannot be reconstructed locally: a fresh app sync is required before relying
on this guard for those entries. Uncoordinated older binaries and signed cross-process upgrade
behavior remain unverified. No new cache envelope version, endpoint or upstream change.

## Verification

Eleven new test methods cover all nested shapes, null/empty unknown values, existing response
discriminators, cache encode/decode, changed public edit flags, retained passkey targets,
source-level read-only behavior despite an edit=true crypto fake, known-only resync and denied
HTTP writes. The existing encrypt/sync race method additionally covers a newly unsupported
payload after encryption starts. Existing supported-type round-trip assertions remain intact.

The targeted five-suite run passed 56 methods. Full regression and unsigned platform build
results are kept in the verification document. Real server/Apple-controller/device/upgrade
checks remain separate; these fixtures do not close every H-103/A-206/X-604 acceptance criterion.
