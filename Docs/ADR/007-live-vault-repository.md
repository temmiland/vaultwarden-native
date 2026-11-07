# ADR 007: Live Vault-Repository und gekoppelte Projektionen

Datum: 2026-09-27. Status: live implementiert und lokal getestet; reale Integration ausstehend.

## Entscheidung und Ownership

Die App-Komposition erzeugt pro akzeptiertem `AuthenticatedSession` genau ein
`DefaultVaultRepository`. Alle Fenster dieses AppModels verwenden dieselbe Instanz.
Der Vault-Bildschirm erhält Repository, Passwortgenerator, Zugriffsprüfung und Plattformports;
er baut keinen Live-Servicegraphen und erhält weder Session noch Token-Closure.

```text
AppComposition / LegacySessionAdapter
  ├─ DefaultVaultRepository (Data): Snapshot, FIFO, Single-Flight, Projektionen
  │    ├─ SDKVaultSourceAdapter → SDKVaultSessionSource
  │    │    └─ SDK-Backing, HTTP, Crypto, verlustarme Draft-Rekonstruktion
  │    ├─ AutoFillProjectionWriter → account-/grant-gebundener Dateistore
  │    └─ CredentialIdentityPublisher → SystemCredentialIdentityStore
  └─ VaultPresentation.VaultRootView → retained @Observable VaultModel → Domain-Snapshot
```

`VaultState` besitzt keine SDK-Cipher-/Folder-/Collection-Arrays mehr. Es hält einen abgeleiteten
Domain-Snapshot und ausschließlich UI-Zustand. Der Stream wird direkt im Repository registriert;
der initiale und folgende Stand werden revisionsgeordnet angenommen. Direkte Nachfragen nach
einer Mutation verhindern, dass ein abgeschlossener UI-Effekt vor seinem Snapshot endet.

Der SDK-Adapter behält verschlüsselte DTOs und entschlüsselte SDK-Werte nur für Crypto und
Rekonstruktion. Details, Drafts, TOTP und Passkey-Zusammenfassungen verlassen ihn SDK-frei.
Networking/AutoFillContract sind hier zusätzliche explizite Adapter-Abhängigkeiten. Die weitere
Zerlegung in separate API-Ports bleibt möglich. Crypto verwendet jetzt den injizierbaren,
`Sendable`-Port `VaultCryptoServicing`; Produktion nutzt weiterhin `SDKVaultCryptoService`.

## Operationen und Fehler

- Sync ist Single-Flight. Ein abgebrochener View-Consumer canceln nicht den von anderen benötigten
  Sync; seine Rückkehr bleibt cancellation-geprüft.
- Sync und Servermutationen verwenden eine gemeinsame FIFO-Schlange. Nach einer akzeptierten
  Mutation werden UI, verschlüsselter Cache und System-Identitäten vom selben Quellstand abgeleitet.
- SDK-Backing prüft lokale Cipher-Revision und aktuelle Berechtigungen vor dem Schreiben und nach
  suspendierender Verschlüsselung. Keine zusätzliche Server-API oder Kompatibilitätsfunktion.
- Nach erfolgreichem Server-Write darf ein Decode-/Decrypt-/Refreshfehler keine zweite Erstellung
  anbieten: `committedButRefreshFailed`, Draft schließen, stale markieren und Sync verlangen.
- Während Save deaktiviert das Sheet Cancel und interaktives Dismiss: eine eingereichte Mutation
  gehört dem Repository und ist nicht durch UI-Cancellation rückgängig zu machen. Programmatischer
  Dismiss darf weder einen Ersatz-Draft schließen noch den bestätigten Repository-Commit verhindern.
- Ein Syncfehler behält den letzten lesbaren in-memory Stand. Wenn Organisation-Crypto bereits
  verändert wurde, sperrt der Adapter Mutationen bis zum nächsten erfolgreichen Sync.
- Vorschläge entstehen erst nach Cache-Commit derselben Revision. Cache-/OS-Fehler lassen den
  Servererfolg bestehen und erzeugen eine sichtbare reparierbare Warnung.
- Lock schließt das Repository dauerhaft, leert die UI sofort und joint seinen Cleanup. Der
  Identity-Publisher drainiert alte OS-Writes vor dem abschließenden Entfernen. Routine-Clear ist
  davon getrennt, damit ein späterer Sync die Projektion reparieren kann.

## Übergang zur vorhandenen Extension

`autofill-cache.json` und sein UUID-Invocation-Fence bleiben erhalten. `AutoFillData.LegacyAutoFillCacheCodec`
übersetzt das encrypted-only Envelope in das vorhandene Format und ergänzt `projectionRevision`.
Vollständige Account-/Serveridentität wird beim Lesen geprüft; vorhandene Revisionen werden als
Startwert übernommen. Die Datei enthält keine neuen Plaintext-Secrets.

App-Projektion und Extension-Upsert nehmen denselben Prozess-Lock wie Shared-Grant-Widerruf.
App-Writes verlangen den bei Komposition aufgenommenen festen Unlock-Proof und aktiven Runtime-
Zugriff. Extension-Upsert verlangt ihren ursprünglichen Proof und Cache-UUID. Ein älterer Prozess
darf weder den Cache eines neuen Unlocks schreiben noch bei seinem Cleanup entfernen.
Der Extension-Reader und Upsert liegen in `AutoFillData.LegacyAutoFillCacheStore`. Die Composition
injiziert den App-Group-Pfad und `AutoFillContract.AutoFillCacheMutationAuthorizing`; der konkrete
SharedToken-Adapter prüft Proof und gebundene Tokens im selben Prozess-Lock.
SharedToken- und SharedUnlock-Persistenz liegen in Data, mit injizierter Keychain und Container-URL.
Wire-Namen und SDK-freie Account-Metadaten liegen in AutoFillContract; SDK-KDF-Konvertierung im
Adapter. App-Group-Konfiguration liegt in `Composition/SharedAppGroup.swift`; VaultCore ist entfernt.
`Data.AuthenticatedSession` erhält HTTP explizit injiziert und hält die validierte persistierte
Account-/Serveridentität getrennt von normalisierten Domain-Transport-URLs. Die Cache-Projektion
verwendet diese exakte Speicheridentität, auch bei vorhandenen URLs mit abschließendem Slash.
URI-Matching und die gepinnte Suffix-Liste liegen ebenfalls in AutoFillData; SDK-URI-Modi werden
im SDK-Adapter auf den eigenen Vertrag abgebildet. Kein App-/Extension-Target importiert mehr
`VaultFeature`.
Beim Cross-process-Revisionskonflikt wird keine alte Projektion als erfolgreich bestätigt;
die App zeigt Reparaturbedarf und verlangt Sync. Keine automatische Merge-/Retry-Schleife.

Weil das alte Format keine Collection-Permissions trägt, exportiert die neue App-Projektion nur
Logins mit nachgewiesener aktueller Secret-View-Berechtigung. Unaufgelöste/gesperrte/malformed
Datensätze werden nicht durch die Extension wieder sichtbar gemacht.

## Anhänge

Das Repository besitzt verschlüsselte Arbeitsdateien und gibt ausschließlich geschützte Preview-
URLs zurück. Der Adapter hält security-scoped Zugriff nur während lokaler Verschlüsselung,
prüft Cipher-Kontext/Berechtigungen und lässt nur bestehende gleich-origin Transfer-URLs zu.
Die UI nimmt verspätete Downloads nur für die ursprüngliche Auswahl/Revision an. Abgewiesene
Downloads und abgelöste Previews werden bereinigt; Cleanupfehler nennen Lock als Reparaturaktion.

## Bewusst offen / nicht als Done zählen

- Keine serverseitigen Conditional Writes: Änderungen anderer Geräte können zwischen Prüfung und
  Server-Write liegen. Netzwerkabbruch nach unbekanntem Commit bleibt mehrdeutig.
- Passkey Registration bleibt ein eigener Extension-Serverpfad; keine atomare Kopplung von Server,
  Cache und OS-Identitäten. X-604 bleibt offen. Ihr Upsert ist nur lineage-/cache-gefenced.
- Die Extension liest weiter das bestehende verschlüsselte Wireformat, jetzt über den live
  verwendeten AutoFillData-Reader. SDK-geprägte Callback-Modelle und Query-/Passkey-Orchestrierung
  verbleiben in der Extension; Actor-Zerlegung und reale Integrationsprüfung stehen aus.
- Vault-, Send- und Settings-UI/Models und ihre Tests liegen in den jeweiligen AppModules-
  Presentation-Targets. Die drei alten Feature-Manifeste und ungenutzten Vault-Service-/Alias-
  Implementierungen sind entfernt. Auth-/Core-Pakete und reale Lifecycle-Prüfungen bleiben offen.
- Anhänge laden Ciphertext weiterhin vollständig in RAM. Streaming/F-701 bleibt offen.
- Keine neue Haupt-App-Offline-Persistenz. Kein durables Recovery-Journal. Keine Zeroization-Zusage.
- Alte SyncService-/Attachment-/Identity-Service-Typen sind gelöscht; ihre wesentlichen
  Regressionen prüfen jetzt den produktiven SDKVaultSessionSource-/IdentityMapper-Pfad.
- VaultModel-/State-Tests sind auf Repository-Fakes und Domain-Snapshots portiert und bestanden.
  Gated Repository-/Identity- und Live-Source-Tests ersetzen keine signierte Cross-process-Matrix,
  echte Serverprüfungen oder OS-Context-Integration.

## Lokale Verifikation und offene Gates

Nachreview: eingereichte Mutationen laufen in einer repository-eigenen Task bis zum Commit;
Cancellation eines UI-Consumers überspringt nach bestätigtem Write weder Projektion noch die
Bestätigung des Ergebnisses. Runtime-Widerruf bleibt wirksam. Bestätigte Creates schließen ihren
gleichen Draft vor der UI-Cancellation-Prüfung. Fehler-Cleanup von Attachment-Verzeichnissen
wird nicht mehr verschluckt; bestätigter Upload mit Cleanupfehler ist vom Refreshfehler getrennt
und zeigt ausdrücklich Lock statt erneutem Upload als Reparatur. Ohne Projektionsport werden
alte System-Identitäten entfernt. Deterministische Task-Race- und Mutations-Fixtures bestehen
jetzt, einschließlich fünf Wiederholungen der 27 zentralen Pipeline-/Publisher-/AppModel-/Auth-
Tests. Tatsächliche parallele App-/Extension-Prozesse und OS-Store-Calls sind nicht damit geprüft.

Der Testlauf hat außerdem fail-closed Auth-Cleanup und veraltete Attachment-Bestätigungen
korrigiert. Die frühere Gesamtbaseline umfasste neun lokale Pakete mit 459 Tests und beide unsigned
App-Builds. Spätere Migrationen verschieben Tests zwischen Paketen; die aktuellen betroffenen
Prüfläufe stehen in der verlinkten Verifikationsliste. Die FFI-Smoke-Fixture ist in der Baseline
enthalten, eine echte SDK-/Server-Sitzung nicht.

Die konkrete ausführbare Prüfliste steht in [Verification.md](../Verification.md).
App-Kompilierung ist kein Nachweis der Cross-process-, Keychain-, OS-Store- oder Server-Semantik.
V-401/V-402/V-403 bleiben bis zu dieser Verifikation und der Extension-Pipeline teilweise offen.
