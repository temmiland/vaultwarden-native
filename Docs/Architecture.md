# Architektur des Quellcode-Lernprojekts

Stand: 2026-09-29. Diese Beschreibung zeigt den tatsächlich vorhandenen Graphen, keine
behauptete abgeschlossene Migration. Verbindliche Restarbeiten: [Umsetzungsplan](Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md).

## Struktur und Abhängigkeitsrichtung

Es gibt zwei lokale Swift Packages: `AppModules` für eigenen Code und `VaultwardenSDK` für
generierte Upstream-Bindings/FFI. Beide Plattformen verwenden dieselben Domain-/Data-/UI-Module.
Die Apps und Credential Provider Extensions bleiben eigene Xcode-Targets; `project.yml` ist
deren Quelle. Plattformunterschiede gehören in Shells/Adapter, nicht in Vault-/Auth-Regeln.

| Target | Aufgabe | Direkte eigene Dependencies |
| --- | --- | --- |
| Domain | IDs, Werte, Commands/Capabilities, Repository-/Plattformports | keine; nur Foundation |
| Networking | HTTP, geschützter File-Transfer/Chunk-Multipart, sichere Redirect-Policy | keine (Foundation und Darwin-Datei-I/O) |
| SecurityStorage | Keychain, App-Group-/Dateilocks, sensitive Temp-Dateien | keine |
| AutoFillContract | versionierte verschlüsselte Austauschwerte und Proofs | keine |
| BitwardenSDKAdapter | SDK-Mapping, Crypto, SDK-Callbacks und serverseitige Vault-Payloads | Domain, Networking, AutoFillContract; einziges Modul mit rohem SDK |
| Data | Auth-/Vault-/Send-/Settings-Repositories, Session, Token-/Unlock-Persistenz | Domain, Networking, SecurityStorage, AutoFillContract, BitwardenSDKAdapter |
| PlatformServices | Apple-Biometrie, Clipboard, Identity Store, File Import, URLs | Domain |
| SharedUI | gemeinsame UI-Komponenten/Environment-Ports | Domain |
| Auth/Vault/Send/SettingsPresentation | Observation-Models, Actions, State und Views | Domain, SharedUI |
| AppFeature | App-Session-Zustand, Timeout-/Lifecycle-Übergänge | Domain und vier Presentation-Targets |
| AutoFillData | Query, URI-Matching/PSL, Cache, Assertion/Registration/Recovery/Completion | Domain, Contract, Networking, Storage, SDKAdapter |
| AutoFillFeature | gemeinsame Credential-Picker-/Registration-Views | Domain, AutoFillContract, SharedUI |

Die vier Presentation-Targets liegen auch physisch in `Sources/*Presentation`, ohne Legacy-
Manifestpfad oder Feature-zu-Feature-Rückkante. Das Package-Manifest ist für die genaue Kantenliste
maßgeblich. Keine Credential-Keychain-Namen wurden durch diese Source-Umbenennung geändert.

## Composition Roots und Zustandsbesitz

- `App/Sources/Shared/AppComposition.swift` validiert Contributor-Konfiguration und komponiert
  HTTP, Storage, Auth, Session-Repositories und Plattformclients. Die konkrete Data-Session wird
  ausschließlich hier aus einer Domain-Capability übernommen; kein SDK-/Token-Handoff durch UI.
  `AppSessionAdapter` ist ein Composition-Adapter, keine Legacy-Feature-Brücke; HTTP wird explizit
  in Vault-/Send-/Settings-Repositories injiziert statt dort implizit live erzeugt. Ein zweiter
  Initializer nimmt Credential-Store, HTTP, Biometrie, Gerätename, Timeout-Settings und Datei-
  Lifecycle entgegen; nur hostlose Integrationsbundles nutzen ihn. Der Live-Initializer validiert
  weiterhin zuerst die Storage-Konfiguration. Die einmalige Capability-Übergabe statt eines
  observation-only Handoffs ist eine dokumentierte Planabweichung ([ADR 028](ADR/028-session-handoff-and-integrated-acceptance.md)).
- `AppFeature.AppModel` besitzt den App-Lifecycle, nicht den Vault. Data-Repositories besitzen
  autoritative Snapshots/Mutation-Reihenfolgen; Presentation besitzt Auswahl, Drafts und Busy-State.
- `AutoFillExtension` übersetzt Apple-Requests und baut invocationgebundene Ports. Der synchrone
  terminale Apple-Dispatch liegt in `SystemAutoFillExtensionContext`; die Prüfpolicy in AutoFillData.
  Der Controller ersetzt gehostete Inhalte mit vollständigem UIKit-Containment; sein
  `sessionLoader` ist produktiv immer der validierte Shared Store, Tests injizieren synthetische Sessions.
- `AutoFillFeature` besitzt die plattformübergreifenden Picker-/Registration-Views und erhält
  Metadaten und Callbacks. `AutoFillContract.AutoFillLoginSummary` ist ein transienter, redigierter
  UI-Wert, kein neuer persistierter Cache-/Wire-Typ. Das UI importiert AutoFillData nicht.
- Kein globales Service-Locator-Pattern und keine `.live()`-Factory in Presentation. Testfixtures
  injizieren dieselben Protokolle statt eine zweite produktive Implementierung zu verwenden.
- Die Cipher-Wire-Grenze erkennt nicht abbildbare Felder und bewahrt eine read-only-Schreibsperre
  über SDK und encrypted Cache hinweg. Data-Berechtigungen und AutoFill-Registration prüfen sie
  unabhängig von SDK-decrypted Flags. Keine blinde Rückübertragung unbekannter Felder; siehe
  [ADR 026](ADR/026-unsupported-cipher-write-fence.md).

## Wesentliche Datenflüsse

```text
View → Observation-Model → Domain-Port → Data-Repository → SDK-/HTTP-/Storage-Adapter
                              ↑                 ↓
                         typisierte Werte ← autoritativer Snapshot/Commit

App-Sync → encrypted-only AutoFill-Projektion → invocationgebundener Extension-Reader
       └→ koordinierter System-Identity-Store   → frische Secret-Auflösung → Terminal-Dispatch
```

Fresh Login/TOTP und Returning Password/PIN/Biometry liefern widerrufbare Domain-Capabilities.
Die SDK-Ressource und Credentials bleiben privat in Data/Adapter. Token-Scope bindet Account,
Server und Sign-in-Lineage; Generation und Unlock-Proof verhindern die Übernahme fremder Tokens.
Das Shared-Unlock-Envelope verwendet Schema 4 und eine Boot-Session-ID aus SecurityStorage.
Uptime-Deadlines gelten nur innerhalb dieses Systemstarts; auch „never“ erlaubt nach Reboot keine
Wiederverwendung eines alten AutoFill-Grants. Fehlende Boot-Identität verweigert Zugriff, alte
Shared-Schemata werden nicht still migriert oder gelöscht. Private Account-Records bleiben unverändert.
Durables Lock-/Logout-Cleanup wird vor Restore wiederholt ([ADR 022](ADR/022-durable-auth-cleanup-intent.md)).
Ein separater async FD-Lock serialisiert die vollständige Refresh-Anfrage; der kurze Storage-Lock
bleibt für Lock/Logout verfügbar. Ein metadata-only Refresh-Intent verhindert blinde Wiederholung
nach Antwortverlust. App-Persistenz bleibt an die vor Unlock erfasste Epoch gebunden. Eigene
Repository-/UI-Grenzen erhalten throwing Token-Fehler; nur die SDK-Callback-Grenze bleibt optional.
KDF-Konvertierung begrenzt untrusted Aufwand; der SDK-Decrypt-Adapter verweigert erkennbar verlorene
Felder vor Write/Cache/AutoFill. Siehe [ADR 027](ADR/027-refresh-request-recovery-and-decryption-integrity.md).

Vault-Sync/CRUD/Attachment-Mutationen laufen repository-eigen in FIFO. UI-Cancellation ist nicht
Server-Rollback; bestätigte Writes dürfen keinen erneut einreichbaren Create-Draft erzeugen.
Runtime-Widerruf verhindert späte Veröffentlichung. Eine partielle/fehlgeschlagene Projektion
bleibt Repair-Zustand und wird nicht als gesunder Sync ausgegeben.

Send-Load/Create/Update/Delete verwenden ebenfalls einen gemeinsamen FIFO-Slot. File Sends
teilen SensitiveTemporaryFileStore, 64-KiB-Multipart und die HTTP-File-Ports mit Attachments;
Scoped Access endet nach SDK-encryptFile, nicht erst nach HTTP. Cleanup-/Upload-/Postcommit-
Fehler bleiben typisiert, bestätigte Drafts schließen vor der UI-Cancellation-Prüfung (ADR 025).

Registration verwendet ein persistentes Metadata-only Write-Journal. Unklare Writes werden
nicht automatisch neu gesendet. App/Extension ordnen teilnehmende OS-Identitätsmutationen über
einen gemeinsamen async FD-Lock; das ist keine atomare Server/Keychain/Cache/OS-Transaktion.
Secrets liegen nicht in Picker-Listen. TOTP wird frisch mit expliziter Uhr und SDK-Periode
aufgelöst und vor Ausgabe nochmals auf denselben Zeitbucket geprüft.

## Regeln und Nachweis

Networking begrenzt tatsächliche Response-Bytes, nicht nur Content-Length. Datei-Downloads schreiben
64-KiB-Chunks in eine exklusiv angelegte geschützte Stage und publizieren erst nach vollständigem
Erfolg. Früher Abbruch cancelt den echten AsyncBytes-Task. Upload-Cancellation und Response-Completion
besitzen denselben synchronisierten Task-/Continuation-State. SDK-interne Whole-file-Allokationen
bleiben eine separate Grenze; Dateibyte-Limits sind kein Konstant-RAM-Nachweis.

`Scripts/check-architecture.swift` prüft Imports/Presentation-Dependencies und Live-Factories;
`Scripts/test-architecture-rules.sh` prüft absichtlich verbotene Imports in einer Wegwerf-Fixture.
Der Check ist ein Source-Guard, kein vollständiger AST-/Security-Beweis. Eigene Targets verwenden
vollständige Strict-Concurrency-Prüfung mit Warnungen als Fehler im Swift-5-Sprachmodus. Der
generierte SDK-Code behält seine Upstream-Warning-Policy. SwiftFormat wird mit Version/Hash
gepinnt und schließt Upstream-Code aus.

Hostlose macOS-/iOS-Integrationsbundles führen die echte App-/Extension-Composition, das Hosting
und den Apple-Controller mit isolierter Infrastruktur aus ([Runbook](IntegratedAcceptance.md)).
Offen bleiben End-to-End-Auth-/Refresh-Recovery-Abnahmen mit echten Prozessen/Servern, signierte
UI-/OS-Controller-Abnahmen, echte signierte Prozess-/OS-/Crash-Races und ein tatsächlich
ausgeführter Server-Contract. Der SDK-Datei-Crypto-Pfad liest
intern ganze Dateien; der Umbau garantiert keinen konstanten Gesamt-Heap. Details:
[Threat Model](ThreatModel.md), [Verifikation](Verification.md),
[ADR-Verzeichnis](ADR), [Freigabecheckliste](RemainingReleaseWork.md).
Der kompakte aktuelle [Reststand](RemainingReleaseWork.md) grenzt diese Abnahmen vom bereits
implementierten lokalen Pflichtcode ab; nicht alle ursprünglichen Planphasen sind abgeschlossen.


### Scoped biometric Keychain authorization

`BiometricClient.performAuthenticated` runs a protected operation only after successful biometric
verification. The platform adapter supplies the same authenticated LocalAuthentication context to
SecurityStorage through a task-local opaque handle; Domain and UI never receive Apple context types.
Further interaction is disabled for that context, and it is invalidated when the operation ends,
including errors. SecurityStorage still enforces the Keychain access-control policy. PlatformServices
therefore depends on SecurityStorage as well as Domain; no presentation dependency is added.
