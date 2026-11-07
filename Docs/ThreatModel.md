# Threat Model – Lernprojekt, kein Audit

Stand: 2026-09-29. Erste Veröffentlichung: nur Quellcode. Sicherheitsannahmen beschreiben
beabsichtigte Grenzen und aktuelle lokale Nachweise, keine Garantie für echte Geräte/Server.

## Assets und Angreifer

Schützenswert: Master-Passwort, User-/Organisation-Keys, PIN-/Biometrie-Wrapping, Refresh-/Access-
Tokens, entschlüsselte Vault-/Send-/Attachment-Daten, TOTP-Seeds/Codes, Passkey-Material sowie
Browsing-/Account-Metadaten. Auch Credential IDs, RP und User Handles gehören nicht in Reports.

Betrachtet werden manipulierte Serverantworten/Dateinamen/Redirects, falsche Domains/Identitäten,
alte App-/Extension-Aufrufe, Cancellation/Reentrancy und Teilfehler während Writes/Persistenz.
OS und SDK-Cryptographie werden vertraut. Root-/Kernel-Kompromittierung, bösartige signierte
Upgrades, Malware im eigenen Prozess, physisch kompromittierte Geräte und SDK-Crypto-Fehler
können diese Grenzen umgehen. Das Projekt ist dafür kein Gegenbeweis und kein Ersatz für Audit.

## Trust Boundaries

| Grenze | Schutz im eigenen Code | Verbleibende Einschränkung |
| --- | --- | --- |
| UI ↔ Data/SDK | Domain-only Ports, opaque/revocable Capabilities, Secret-Cleanup, redigierte Beschreibungen | Swift-Strings/FFI sind kein nachweislich zeroisierbarer Speicher |
| App ↔ Extension | account/server/lineage/unlockgebundene Keychain-Werte, encrypted-only Cache, stabile Prozesslocks | Entitlements/signierte Parallelprozesse noch nicht verifiziert; alte Binaries verstehen neue Marker nicht |
| Network ↔ Credentials | HTTPS-Policy, Debug-HTTP nur Loopback, Credential-Requests ohne Redirects, Attachment same-origin | kein Certificate Pinning; tatsächlicher Serververtrag noch nicht gepinnt getestet |
| Mutationen ↔ UI-Cancellation | repository-/writer-eigene Writes, eindeutiger Commit/Repair statt blindem Retry | HTTP ist nicht rückrufbar; kein genereller Server-Idempotenzvertrag |
| Cache/Keychain ↔ OS Identity Store | exakte Proof-/Revision-Checks, gemeinsamer async Mutationslock, gezieltes Cleanup | Prozessdeath kann bereits beim OS-Daemon eingereichte Requests nicht zurückrufen |
| Passkey-Write ↔ Neustart | persistentes Metadata-only Journal, fail-closed bei corrupt/future/unklar | fehlender Nachweis blockiert weiter; Abandonment ist keine Server-Rejection |
| Lock/Logout ↔ Neustart | deny-Cleanup-Marker bis alle Keychain-Schritte gelingen, Replay vor Restore | Marker-Schreibfehler/Power Loss nicht beweisbar repariert |
| Rotierender Token ↔ konkurrierende Anfrage/Neustart | separate async Network-Lease, durabler nonsecret Pre-Request-Intent, Scope-/Epoch-/Generation-Rechecks | verlorene Antwort nicht rekonstruierbar; erneute Anmeldung, keine atomare Server/Keychain-Transaktion; alte Binaries nehmen nicht teil |
| Untrusted KDF-/SDK-Payload ↔ Crypto/Write | lokale Aufwandlimits, Feldpräsenz/Kardinalität prüfen, unknown Payload read-only | Strukturguard kein Kryptobeweis; keine gemessene Geräte-Heap-/CPU-Garantie |
| Datei/Preview ↔ Filesystem | eigener registrierter Temp-Root, normalisierte Namen, 0700/0600, Cleanup/Recovery bei Lock | SDK liest ganze Dateien; Crash-/Disk-full-/Device-Protection-Matrix unvollständig |
| Clipboard ↔ andere Apps | concealed, local-only, Expiry und changeCount-Guard | Kopieren ist bewusste Secret-Freigabe; Clipboard-Consumer können bereits gelesen haben |
| SDK/Tools ↔ Supply Chain | Source-/Toolchain-/Patch-Pins, Tool-Archivhash, isolierter SDK-Neubau und realer FFI-Smoke, Byte-Inventar | Remote-CI/fremde Fresh-Machine nicht ausgeführt; Hash der lokalen Bytes ist keine Provenance-Attestation |

macOS Sandbox/Signing/Direct Distribution wird für eine spätere App-Veröffentlichung separat
entschieden; die Quellcodeentscheidung wählt keinen Store-/Notarization-Pfad. Unkonfigurierte
App-Group/Keychain-Einstellungen öffnen nicht still einen unsicheren Fallback-Container.

## Fehler- und Recovery-Policy

- Netzfehler/429/5xx sind nicht automatisch Logout; endgültige Token-Ablehnung ist separat.
- Unbestätigte Refreshes (Antwortverlust, malformed 2xx, 408/409/5xx) sind kein sicherer Retry:
  durabler Marker verlangt explizite erneute Anmeldung, ohne automatisch Credentials zu löschen.
- Unbekannte Required-Payloads/Permissions/KDFs/Contracts werden abgewiesen, nicht normalisiert.
- Konkrete AutoFill-Domain oder Credential-ID fällt nicht auf einen beliebigen ganzen Vault zurück.
- Re-Prompt-geschützte Secrets bleiben ohne Master-Passwort-Nachweis gesperrt; Gerätebiometrie
  allein ersetzt diesen Nachweis nicht.
- Cleanup-/Projektionsfehler werden angezeigt; bestätigter Upload plus Cleanupfehler empfiehlt
  Lock/Repair, keinen zweiten Upload. Unklare Passkey-Writes werden nicht automatisch wiederholt.
- Keine Telemetrie. Logs/Fehler dürfen keine rohen Credentials, Response-Bodies oder Browsing-
  Historie veröffentlichen. Der Secret-Scanner ist nur eine Heuristik, kein vollständiges Audit.

## Verifikation und offener Nachweis

Lokale Unit-/Contract-Fixtures verwenden synthetische Daten, explizite Task-Gates und teils echte
temporäre Dateien/FDs. Der SDK-Smoke führt Rust-FFI aus, aber keine echten Passkey-/Crypto-Vektoren.
Unsigned Debug/Release-Komponentenbau validiert Typ-/Import-/Warning-Grenzen, keine Signing-
Entitlements, OS-Prompts oder OS-Akzeptanz der Credentials.

Hostlose macOS-/iOS-Integrationsbundles führen die echte App-/Extension-Composition, Hosting und
den Apple-Controller mit In-Memory-Keychains, isolierten Preferences und synthetischem HTTP aus;
sie verweigern den Lauf, wenn eine App Group auflösbar wäre. Kein ausgeführter Vaultwarden-
Contract-Smoke, signierter App-/Extension-Parallelprozess, Process Kill, Power Loss, XCUITest/
signiertes UI-Target, echter Extension-Context oder externer Security Review ist belegt. Nicht mit
„Tests grün“ wegdokumentieren. Für konkrete Prüfungen siehe [Arbeitscheckliste](RemainingReleaseWork.md),
[AutoFillLifecycleChecks](AutoFillLifecycleChecks.md) und
[Verification](Verification.md). Reports: [SECURITY.md](../SECURITY.md).
