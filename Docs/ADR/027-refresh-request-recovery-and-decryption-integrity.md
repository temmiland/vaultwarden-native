# 027 – Refresh-Anfrage, Commit-Bestätigung und SDK-Integrität

Stand: 2026-09-28. Betrifft S-302/S-303/U-504 sowie A-206/A-207/X-601.
Keine neuen Serverfunktionen, Änderungen an offiziellen Subrepos oder generierten Bindings.

## Refresh ist mehr als Compare-and-Write

Die bisherigen kurzen Storage-Transaktionen schützen einzelne Writes, aber nicht die Benutzung
eines rotierenden Refresh-Tokens. Die Live-Persistenz verwendet deshalb einen **separaten**
async FD-Lock `.vaultwarden-refresh.lock` über Anfrage, Antwortklassifikation und Commit hinweg.
Nach Erwerb werden Scope, Autorität und Generation erneut gelesen. Ein anderer Gewinner wird
übernommen; kein zweiter Request mit dem inzwischen verbrauchten Token. Die bestehende kurze
`.vaultwarden-token-store.lock`-Transaktion wird niemals über einen Netzwerk-Await gehalten.
Lock/Logout erwerben keinen Netzwerk-Lock und können den Runtime-Widerruf weiterhin ausführen.
Warten ist begrenzt; eine bereits erworbene Lease wird nicht vorzeitig für einen anderen Writer
freigegeben oder per Dateilöschung ersetzt. Fehlender App Group Container ist kein Fallback.
`processOnly` bleibt eine ausdrücklich synthetische Fixture-Policy, kein Live-Betriebsmodus.

Vor HTTP wird `auth.refresh.intent.v1` im gemeinsamen Keychain geschrieben: Schema, Operation-ID,
Scope, Generation und Publication-Epoch; **keine Tokens, Schlüssel, Antworttexte oder Namen**.
Ein Writefehler verhindert den Request. Der App-Provider bindet zudem seine Persistenz an die
bereits beim Login/Unlock erfasste Epoch. Eine wartende alte Anfrage darf sich nicht an die neue
Epoch nach Lock binden. Extension-Persistenz bleibt an ihren exakten Unlock-Proof gebunden.

## Wiederanlauf und Unsicherheit

- Ein bestätigter, dauerhaft gespeicherter Nachfolger erlaubt Nutzung. Falls nur Shared oder nur
  Private erfolgreich war, gilt weiterhin die strikt scope-/grantgebundene Merge-Policy.
- Ein Marker einer älteren Generation verhindert nicht die Nutzung eines bereits gespeicherten
  neueren Gewinners. Er wird beim nächsten autorisierten Refresh durch dessen Marker ersetzt.
- Explizite OAuth-Ablehnung und klassifizierte 4xx-Antworten außer Timeout/Conflict können den
  Request beenden. Nur das bestehende eindeutige `invalid_grant` läuft über Session-Expiry.
  429 bleibt einschließlich Retry-After ohne automatischen Logout wiederholbar.
- Transportverlust, Cancellation, malformed 2xx, 408/409 und 5xx beweisen nicht, dass kein Token
  ausgegeben wurde. Der Marker bleibt; auch ein neuer Provider/Prozess darf denselben Request
  nicht blind wiederholen. Die Sitzung und Vault-Daten werden **nicht automatisch gelöscht**.
  Owned Transports zeigen `SessionAuthorizationError.refreshRecoveryRequired`: Abmelden und
  erneut anmelden. Das ist bewusst konservativer als ein unbegrenzter Offline-/5xx-Retry.
- Logout entfernt den Marker mit den anderen Credentials; fehlgeschlagenes Entfernen wird über
  den vorhandenen Cleanup-Intent wiederholt. Foreign-Lineage-Marker autorisieren keine Tokens.
  Ein beschädigter Marker bleibt fail-closed und verlangt die explizite Recovery.

Das ist ein durables **Unsicherheitsjournal**, kein gespeicherter Token-Response und keine
atomare Server/Keychain-Transaktion. Eine vor Speicherung verlorene Antwort lässt sich nicht
rekonstruieren. Scheitern sämtliche Credential-Writes, gibt es keine erfundene erfolgreiche
Rotation. Der zuvor falsche Sonderfall „kein Grant + fehlgeschlagener Private-Write = vermeintlich
erfolgreiche Shared-Publikation“ ist korrigiert; Capability-Revoke wird unabhängig versucht.

Vault, Send, Settings und der eigene Passkey-HTTP-Adapter verwenden den throwing Token-Port.
Nur die vorgeschriebene SDK-Token-Callback-Grenze bleibt optional. Ein Auth-Fehler **vor** dem
Cipher-Request entfernt die unsubmitted Passkey-Reservation und wird nicht als möglicherweise
gespeicherte Passkey behandelt. Die Extension fordert die Recovery in der Haupt-App an.

## Fresh Login hat einen eindeutigen Commit-Punkt

Account/Token/Schnittstellenproof bleiben im atomaren privaten Record. Publication-Epoch und
alle potenziell fehlschlagenden Cleanup-Abhängigkeiten werden vor dem Record-Write geprüft;
PIN-/Biometrie-Removals werden unabhängig versucht. Nach bestätigtem Write gibt es weder einen
neuen Epoch-Read noch einen Consumer-Cancellation-Check oder Handler-Install-Await, der daraus
scheinbar einen uncommitted Login machen könnte. Der Expiry-Handler wird bei Coordinator-Erzeugung
übergeben. Runtime-/Handoff-Widerruf bleibt separat wirksam. Keine verteilte Rollback-Garantie
für alle Enrollment-Keys; ein abgebrochener Precommit kann den bisherigen Account gesperrt und
ohne PIN/Biometrie hinterlassen, nicht als neu erfolgreich angemeldet.

## SDK darf kaputte Felder nicht in einen erfolgreichen Write verwandeln

Der gepinnte SDK-Legacy-Decryptor verwendet an mehreren Stellen `.ok().flatten()` bzw.
`unwrap_or_default()`. Unser Adapter prüft danach Identität, Payload-/Feldpräsenz und Array-
Kardinalität für vorhandene Login-, Card-, Identity-, SSH-, Notes-, Field- und History-Inhalte.
Fehlende Felder/URIs oder ein leerer verpflichtender Name verwerfen die Projektion, bevor sie
editierbar, cachefähig oder AutoFill-fähig wird. Batch-Sync weist sie als unavailable aus.
Legitime leere **optionale** Strings sind kein Fehler. Attachment-Decryption hat bereits einen
separaten Fehlerpfad: übrige lesbare Inhalte bleiben erhalten, Writes bleiben gesperrt.

Präsenzprüfung ist kein eigener Kryptobeweis und kann unbekannte zukünftige SDK-Semantik nicht
verifizieren. Ein absichtlich leer verschlüsselter Pflichtname oder eine vom SDK entfernte URI
führt konservativ zu unavailable; Reparatur im offiziellen Client. Der SDK-Code bleibt unverändert.

## Begrenzter KDF-Aufwand und feste Cache-Fixtures

Vor jeder eigenen SDK-KDF-Konvertierung gelten lokale, ausdrücklich **nicht servernormative**
Obergrenzen: PBKDF2 2.000.000 Iterationen; Argon2id 10 Iterationen, 256 MiB, 16 Lanes,
Memory mindestens Lanes und Iterationen × MiB höchstens 768. Bestehende algorithmusspezifische
Defaults bleiben unverändert, ältere positive niedrige Werte bleiben lesbar. Ungültige oder zu
teure Werte werden verweigert, nie auf andere Parameter geklemmt. Das verhindert extreme
Metadatenwerte, garantiert aber kein extensiontaugliches Peak-Memory oder Laufzeitbudget.
Accounts oberhalb der lokalen Grenzen benötigen einen anderen Client; keine stille KDF-Migration.

Eingecheckte synthetische Golden-Dateien prüfen originlose Legacy-Caches, vorherige ownergebundene
Caches ohne monotone Revision und den aktuellen Payload-Fence. Truncation darf nicht als leere
erfolgreiche Projektion erscheinen. Keine erfundene Authority/Migration alter originloser Daten.

## Nachweisgrenzen

Gated Fixtures nutzen tatsächliche unabhängige Store-Instanzen und denselben FD-Lock, aber im
Testprozess mit synthetischen Keychains. Wiederanlauf wird durch neue Provider/Stores simuliert.
Das ist kein echter signierter App-/Extension-Prozess-, Power-loss-, Server- oder Apple-Controller-
Test. Alte Binaries nehmen am neuen Netzwerk-Lock nicht teil. Ausgeführte Testtargets/Builds und
die verbleibenden Freigaben stehen in [Verifikation](../Verification.md) und
[Restarbeiten](../RemainingReleaseWork.md).
