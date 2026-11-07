# Verifikation und verbleibende Release-Prüfungen

> Datierter Nachweisverlauf; historische Ergebnisse gelten für ihren jeweiligen Stand.
> Aktuelle Reviewergebnisse und alle Restaufgaben ausschließlich in [RemainingReleaseWork.md](RemainingReleaseWork.md).

Stand: 2026-09-29. Nach der erneuten Freigabe des Nutzers wurden die veralteten Testquellen
portiert, sämtliche lokalen Paket-Testtargets gebaut und die Tests tatsächlich ausgeführt.
Offizielle SDK-/Vaultwarden-Quellen wurden dabei nicht verändert. Frühere Build-only-Einträge
im Implementierungsplan dokumentieren den damaligen Stand, nicht dieses Ergebnis.

## 1. Ausgeführte Prüfungen

### Repository-Struktur (2026-10-01)

Nur Verschiebungen/Umbenennungen und Referenzanpassungen, kein Verhaltenscode: Audit und Plan
nach `Docs/Planning/`, Lizenztexte nach `Docs/ThirdParty/`, dieses Protokoll als
`Verification.md`, gemeinsame App-Ressourcen nach `App/Resources`, Extension-Plists als
`VaultwardenAutoFill-Info.plist`/`VaultwardenIOSAutoFill-Info.plist`. Gleiche Toolchain wie unten.
Nach Neugenerierung des Projekts bestanden: Konfigurations- und Negativfixtures, SwiftFormat-Lint
(0/362), Architektur (204 Quellen + 6 Negativfixtures), Runner-Preflight, relative Markdown-Links
(46 Dateien, 0 defekt). `bash Scripts/test-integration.sh`, Exit 0, mit denselben Zahlen wie der
Integrationsblock: SDK-Smoke 1, AppModules 855 (854 bestanden, 1 übersprungen) + 2 XCTest,
macOS 17/17, iOS-Simulator 17/17; SERVER CONTRACT **NOT RUN**. Unsignierte Debug-/Release-Builds
beider Plattformen schlugen zuerst mit `No space left on device` auf dem Systemvolume fehl
(macOS-Teil gebaut, iOS-Teil abgebrochen) und bestanden danach mit `TMPDIR` auf einem Volume mit
ausreichend Platz; kein Quellfehler.

Danach: Das generierte Projekt heißt `Vaultwarden.xcodeproj` statt `VaultwardenMac.xcodeproj`
(nur XcodeGen-Projektname, Skripte, CI, README und Plan; Targets/Schemes unverändert). Ältere
Einträge dieses Protokolls nennen weiterhin den damals tatsächlich verwendeten Namen. Lokal, nicht
versioniert, wurden der optionale `sdk-internal`-Mirror und alte `.build`-Caches entfernt;
`build-sdk.sh` klont die gepinnte Revision dann direkt von GitHub, `.build/sdk-isolated` bleibt.
Auf dem neu generierten Projekt erneut bestanden: Konfiguration samt Negativfixtures, Format
0/362, Architektur 204 + 6, Preflight, `test-integration.sh` (SDK-Smoke 1, AppModules 855 davon 1
übersprungen + 2 XCTest, macOS 17/17, iOS-Simulator 17/17; SERVER CONTRACT **NOT RUN**) und
unsignierte Debug-/Release-Builds beider Plattformen.

### Integrationsblock: Composition, Auth-Handoff, Serververtrag (2026-09-29)

Basis: Commit `4e3098a` plus dieser Block (lokal committet, siehe Git-Log). Xcode 27.0 (27A266a),
Apple Swift 6.4 im Swift-5-Sprachmodus, macOS 27.0 (26A428), iOS-Simulator iPhone 17e iOS 27.0
(24A434). Keine offiziellen SDK-/Subrepo-/Binding-Änderungen. Fallliste und Grenzen:
[Runbook](IntegratedAcceptance.md), Handoff-Abweichung: [ADR 028](ADR/028-session-handoff-and-integrated-acceptance.md).

```sh
bash Scripts/test-integration.sh
```

Ein zusammenhängender Lauf am finalen Stand, Exit 0:

- Architektur: 204 eigene Quellen bestanden.
- VaultwardenSDK: echter FFI-Smoke **1 bestanden**.
- AppModules: **855 Swift-Testing-Methoden in 107 Suites, davon 854 bestanden und 1
  übersprungen** (`LiveServerContractTests.existingServerFlows`, ohne Freigabe deaktiviert),
  plus **2 XCTest bestanden**. Das Framework-Summary zählt den Skip mit; er ist kein Servernachweis.
  Neu gegenüber 852: vier offline ausgeführte Live-Konfigurations-/Referenzmethoden (eine davon
  mit 21 parametrisierten Fällen, nicht als Methoden gezählt) und die übersprungene Live-Methode.
- `VaultwardenMacIntegration` (macOS): **17 bestanden, 0 fehlgeschlagen, 0 übersprungen**.
- `VaultwardenIOSIntegration` (iPhone 17e Simulator): **17 bestanden, 0 fehlgeschlagen, 0 übersprungen**.
- SERVER CONTRACT: **NOT RUN** – keine freigegebene Instanz, Version oder Credentials.

Dieselben 17 Methoden laufen je Plattform; der zweite Plattformlauf ist kein zusätzlicher
Testfall. Während der Arbeit schlugen zwei Entwürfe fehl und wurden korrigiert, nicht entfernt:
Eine Fixture rief Restore vor dem Speichern des Accounts auf, und die erwartete Send-Fehlerart nach
Logout war falsch (die widerrufene Runtime verweigert zuerst mit `CancellationError`). Auslesen
sichtbaren Texts über den Accessibility-Baum lieferte in hostlosen macOS-Bundles nichts; diese
Assertions wurden durch Lifecycle-Effekte (Model-Start, Sync-Request über die Composition) ersetzt.

Weitere Prüfungen am finalen Stand: `git diff --check` ohne Befund; Format-Lint **0/362**
Dateien; sechs negative Architektur-Fixtures verweigert; Debug/Release-Konfiguration für vier
App-/Extension-Targets plus beide hostlose, nicht entitlete Integrationsbundles, drei negative
Konfigurationsfixtures verweigert; `bash Scripts/test-integration-preflight.sh`: 3 positive und
5 negative Simulator-Fixtures sowie 13 Runner-Verweigerungen vor jedem Build ohne Wertausgabe.
Secret-Muster-Check und dessen Negativfixture nach Staging des Blocks bestanden. Direkt nach dem
integrierten Lauf bestanden `bash Scripts/build-unsigned.sh Debug` und
`bash Scripts/build-unsigned.sh Release`: beide Apps samt Extensions, macOS und generischer
iOS-Simulator, ohne Signierung. Kein Archive, Codesign oder Remote-CI-Lauf.

Defekte in eigenen Guard-Skripten: `test-configuration.sh`, `test-source-secrets.sh` und
`update-public-suffix-list.sh` riefen `rg` auf, das auf macOS nicht standardmäßig existiert.
Ohne `rg` scheiterten die Negativfixtures als „unclear failure“, und der Leak-Check
`if rg -q 'AKIA…'` wäre stillschweigend nie ausgelöst worden. Jetzt `grep -F`/`grep -E`.

Die ursprünglichen macOS-/iOS-Läufe aus Workspace-DerivedData hingen vor dem ersten Test beim
Bundle-Laden (Sample: CFBundle-Verzeichnisöffnung, kein Projektcode). Mit temporärem DerivedData
unter `${TMPDIR:-/tmp}` trat das nicht mehr auf. Die Ursache ist nicht bewiesen; der Pfad bleibt über
`VW_INTEGRATION_DERIVED_DATA_ROOT` konfigurierbar.

### Zusammenhängender Auth-/Recovery-/Defekt-Abschlussblock (2026-09-28)

Implementiert: getrennte Network-Refresh-Lease über HTTP/Commit, durable nonsecret Intent vor
Request, Winner-Adoption nach Lock-Erwerb, Epoch-Fences auch für wartende App-Provider, Restart-
Recovery ohne blindes Replay und throwing Auth-Fehler bis eigener UI/Extension-Registration.
429 bleibt wiederholbar; 408/409/5xx, Transportverlust und malformed Success verlangen explizite
erneute Anmeldung, ohne automatischen Logout. Fresh-Login-Commit bestätigt nach Write ohne
Consumer-Cancellation-/Epoch-Read-Reinterpretation. SDK-Feldpräsenz/Kardinalität und KDF-Kosten
werden vor Crypto-/Write-/AutoFill-Nutzung abgesichert. Feste synthetische Cache-Goldens ergänzen
vorherige/current Wire-Shapes. Keine offiziellen SDK-/Subrepo-/Binding-Änderungen.
[ADR 027](ADR/027-refresh-request-recovery-and-decryption-integrity.md).

**30 neue Testmethoden**, keine neuen Serverfeatures. Die bisherige Fixture, die UInt32.max
KDF-Iterationen als unterstützt behauptete, prüft nun den tatsächlichen lokalen Budgetrand und
die explizite Ablehnung darüber; keine Reduktion von Negative-/Permission-/Cancellation-Assertions.
Ein erwarteter Send-Fehlertyp wurde entsprechend dem neuen typed Auth-Port präzisiert. Neue
SDK-Fixtures erhielten die erforderlichen Cipher-Daten statt deren Mappingprüfung zu umgehen.
Die abschließende Regression blieb vollständig, nicht nur die ausgewählten neuen Suites.

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/VaultwardenSDK
```

Vollständige tatsächliche Ausführung: **850 Swift-Testing-Methoden in 106 Suites + 2 XCTest =
852 AppModules-Tests bestanden**. Separater echter SDK-FFI-Smoke: **1 bestanden**, also 853
unterschiedliche Methoden über beide Packages. Parameterized Cases sind keine zusätzlichen
Methoden; die mehrfach ausgegebene XCTest-Gesamtsumme wird nicht mehrfach gezählt.

Die bereits unten dokumentierten macOS-arm64-/generic-iOS-Simulator-Befehle wurden für den
finalen Produktcode sowohl Debug als auch Release mit `CODE_SIGNING_ALLOWED=NO` tatsächlich
wieder ausgeführt; alle vier App-/Extension-Builds bestanden. Kein signed Archive oder UI-Test
daraus. Eigener Code behält complete strict concurrency und warnings-as-errors.

Format-Lint: **0/357** eigene Swift-Dateien. Architektur: **204** eigene Sources; alle sechs
negativen Fixtures erwartungsgemäß verweigert. Debug/Release-Konfiguration für vier Targets
und drei negative Konfigurationsfixtures bestanden. `git diff --check` ohne Fehler.
Tracked Secret-Scanner und dessen negatives synthetisches Fixture wurden nach Staging des
Abschlussblocks ausgeführt; weiterhin ein Mustercheck, kein vollständiges History-/Asset-Audit.

Unabhängige Store-Instanzen benutzen echte FDs in temporären Verzeichnissen, aber synthetische
Keychains innerhalb eines Testprozesses. Recreate-Tests ersetzen keinen echten Process-kill.
SDK-Integritätsfixtures prüfen Struktur, keine neuen echten Crypto-Vektoren. Vollständige
App-/Extension-UI-/Apple-Controller-Smokes, echter Server, signierte Geräte/Entitlements, Remote-
CI/Fresh-Machine und Owner-Freigaben bleiben unbelegt. Aktuell kompakt:
[Restarbeiten](RemainingReleaseWork.md). Frühere Abschnitte sind historische Zwischenstände.

### Cipher-Payload-Schreibschutz (2026-09-28)

Unbekannte Cipher-Felder können nicht mehr still aus dem SDK-Modell verschwinden und danach
einen ersetzenden Write autorisieren. Bekannte Inhalte bleiben lesbar, inkompatible Payloads
werden explizit read-only. Root-/Nested-/Array-Shape, immutable Fence, Cache-Encode/Decode,
Data-Permissions unabhängig vom SDK-Flag und Passkey-Selection-Recheck: [ADR 026](ADR/026-unsupported-cipher-write-fence.md).

Elf neue Methoden (sieben Cipher-Payload, zwei VaultSource, ein CredentialQuery, ein
CipherService); vorhandene Race-Methode um Payload-Wechsel nach Crypto-Suspension ergänzt.
Alle bestehenden unterstützten Typ-/Wire-/Permission-Assertions bleiben erhalten.
Gezielter tatsächlicher Lauf: **56 Methoden in fünf Suites bestanden**:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel \
  --filter 'CipherPayloadSafetyTests|SDKVaultSourceTests|CipherWireContractTests|CredentialQueryTests|SDKCipherServiceTests'
```

Der erste sandboxed SwiftPM-Start scheiterte vor dem Manifest-Build am nicht schreibbaren
Compiler-ModuleCache; mit freigegebenem Xcode-/Cache-Zugriff bestanden die tatsächlichen Targets.
Ein Formatter-Aufruf konnte seine atomaren Datei-Writes im Sandbox-Modus nicht ausführen;
derselbe gepinnte Formatter bestand mit freigegebenem Zugriff, ohne SDK-Dateien zu formatieren.

Der erste vollständige PTY-Lauf bestand mit **820 Swift-Testing-Methoden/103 Suites plus
2 XCTest = 822 AppModules-Tests**; beide unsigned Debug-App-/Extension-Builds bestanden.
Nachreview verstärkte zusätzlich den Encoder: selbst ein gesetztes öffentliches Edit-Flag darf
bei vorhandenem Fence keinen editierbaren Cache für ältere Leser schreiben. Ein lokaler
OlderReader ignoriert den Zusatzmarker und muss trotzdem `edit=false` erhalten.

**Finaler Encoder-Stand tatsächlich bestanden:** derselbe vollständige PTY-Paketbefehl ohne
Filter, **820 Swift-Testing-Methoden/103 Suites plus zwei XCTest = 822**. Separater realer FFI-
Smokebefehl `env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/VaultwardenSDK`: ein Test
bestanden, insgesamt 823 unterschiedliche Methoden über beide Packages. SDK-Quellen unverändert.
Alle vier unsigned Debug-/Release-App-/Extension-Builds bestanden mit den unten bereits
protokollierten macOS-arm64-/iOS-Simulator-Befehlen und DerivedData-Pfaden. Formatter-Lint
0/351; Architektur-Guard 201 eigene Swift-Sources bestanden. Keine Produktcode-Änderung nach
diesem finalen Lauf.
Alle sechs negativen Architektur-Fixtures wurden erwartungsgemäß abgewiesen; synthetischer
Secret-Fixture-Test bestand ohne Ausgabe des Inhalts. Der echte tracked-source Scanner bestand
nach Staging der neuen Dateien (423 ausgewählte Textdateien); weiterhin nur ein Mustercheck,
kein History-/Asset-/Security-Audit.

Keine neue Interpretation/Byte-Erhaltung unbekannter Werte, keine SDK-/Subrepo-Änderung und
kein realer Server-/Apple-Controller-/signierter Prozess-/Upgrade-Nachweis. Frühere Caches können
bereits unbekannte Felder verloren haben; ein lokales Update rekonstruiert diese nicht.

### Vorheriger File-Send-/Cleanup-/FIFO-Block (2026-09-28)

Domain/SDKAdapter/Data übertragen File Sends als geschützte Dateien statt zusätzlicher Swift-
Whole-file-Data; Direct und Azure nutzen HTTPClient.upload(fromFile:). Scoped Access endet nach
SDK-Dateiverschlüsselung. Metadata/Create/Upload/Cleanup bleiben getrennt klassifiziert, Send-
Operationen FIFO und bestätigte Drafts bei UI-Cancellation geschlossen. Limit-/Date-Validation
und fehlerhafte `(action)`-Anzeige korrigiert. [ADR 025](ADR/025-send-file-transport-and-cleanup.md).

27 neue Methoden (13 Repository, sieben SDKAdapter, sieben Presentation); vollständiger gleicher
PTY-Paketbefehl wie im Architekturblock: **809 Swift-Testing/102 Suites + 2 XCTest = 811 bestanden**.
Ein erster Compilerlauf fand ein versuchtes Mutieren des immutable SDK-Send in der neuen Fixture;
Fixture auf Rekonstruktion korrigiert, ohne SDK-Sources zu ändern, vollständiger Lauf danach grün.
Der bestehende SDK-Smoke wurde im vorherigen Neubau-/Architekturblock separat bestanden: 812
unterschiedliche Methoden über beide Packages, kein neuer realer Send-Crypto-Vektor daraus.

Alle bisherigen Direct-/Azure-/Bearer-/Redirect-/Postcommit-Assertions bleiben erhalten und sind
um tatsächlichen File-Port, body-nil, UInt64-Content-Length, 0600 und Datei-Cleanup ergänzt.
13 neue Repository-Methoden prüfen Scoped Access vor HTTP, 16-MiB-Multipart ohne Whole-body-
Fixture-Read, Preparation/Protection/Cleanup-Fehler, acknowledged malformed Ticket, Cancellation,
late Runtime-Revoke, malicious filename und FIFO. Queue-Tests beobachten den tatsächlichen
internen Waiter vor Gate-Freigabe, kein zeitabhängiger Sleep als Reihenfolge-Nachweis.
SDKAdapter nutzt 6-GiB-Sparsefile nur für Größenmetadaten; synthetische Crypto-Fixtures sind keine
Messung des echten SDK-Heaps. Eigene iOS-Dateierzeugung/-Protection kompilierte; nicht auf
signiertem/gesperrtem Gerät ausgeführt.

Der erste vollständige File-Send-Lauf bestand mit 808 Tests. Nachreview ergänzte drei echte
Presentation-Race-Methoden für late Picker/Edit gegen laufenden/bestätigten Save und Dismiss/neue
Intention. Ein darauffolgender voller Lauf wurde beim bestehenden
`cancellingOneConsumerDoesNotCancelTheSharedSync` angehalten. Die Fixture konnte nach bloßem
Task-Start einen noch nicht angeschlossenen Consumer als späteren zweiten Request endlos blockieren.
Beide vorhandenen Sync-Consumer-Methoden warten jetzt auf den tatsächlichen internen Join-Zähler;
die Source-Fixture vervollständigt auch unerwartete Requests, sodass Count==1 weiterhin einen
Regression-Fail liefert. Keine Assertions entfernt. Vollständiger finaler Lauf danach: 811 grün.
Das ist keine pauschale Ursache/Freigabe aller früheren non-PTY-/OS-Races.

Unsigned macOS-arm64-/iOS-Simulator-Debug-App-/Extension-Builds bestanden nach dem endgültigen
Produktcode mit den unten protokollierten Befehlen/DerivedDataPaths; beide entsprechenden
unsigned Release-App-/Extension-Builds bestanden ebenfalls. SDK-interner Heap, echter Server, Disk-full,
Crash-/OS-/Device-/Protection-Matrix und Auth-Operation-/Refresh-Recovery bleiben offen.

### Vorheriger Architektur-/SDK-Abschlussblock (2026-09-28)

Die vier Presentation-Source-Ordner entsprechen nun ihren Target-Namen. Gemeinsame AutoFill-
Picker-/Registration-Views liegen in AutoFillFeature und beziehen nur Contract-Metadaten und
Callbacks, keinen Data-Port. AppComposition injiziert den einen expliziten HTTPClient in
Auth/Vault/Send/Settings; implizite Send-/Settings-Live-Factories sind entfernt. ADR 024.

Nach allen endgültigen UI-/Contract-/Composition-Moves tatsächlich gebaut und ausgeführt:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel
```

**782 Swift-Testing-Methoden/102 Suites + 2 XCTest = 784 bestanden**. Der Aufruf erfolgte mit
Terminal/PTY. Vor den letzten AutoFill-Moves hatten zwei non-PTY-Aufrufe desselben vollständigen
Testsatzes nach dem Build gehangen. Nur die identifizierten eigenen Test-/Helper-Prozesse wurden
beendet. Der vermutete TOTP-Block bestand separat; unveränderter vollständiger Testsatz mit PTY
bestand anschließend und nach den finalen Moves erneut. Die Ursache ist nicht bewiesen und
wurde nicht durch Entfernen von Tests oder ein behauptetes Produkt-Race-Fix geschlossen.
Native SwiftPM meldet seine Backend-Deprecation; kein eigener Target-Compiler-Warning ignoriert.

Der isolierte gepinnte SDK-Neubau aller fünf Slices und **ein realer FFI-Smoke gegen den neuen
SDK-Binary** bestanden lokal: [genauer Ablauf und Grenzen](SDKRebuildVerification.md).
Die bestehenden installierten SDK-Bindings/Binaries und offiziellen Checkouts blieben unverändert.
Das sind weiter 785 unterschiedliche Testmethoden über beide Packages, keine zusätzliche
Abdeckung durch das zweimalige Ausführen derselben SDK-Methode.

Source-Guard: 200 eigene Source-Dateien, sechs absichtlich verbotene negative Fixtures bestanden.
Nach den endgültigen Moves bestanden außerdem alle vier unsigned App-/Extension-Builds:
macOS arm64 und iOS Simulator, jeweils Debug und Release, mit den unten protokollierten
`xcodebuild`-Befehlen/DerivedDataPaths. Keine Source-Änderung während dieses finalen Buildsatzes.
Remote-CI, anderer Fresh-Clone-Rechner, tatsächliche Apple-Controller-/UI-/Signed-/Server-/Crash-
Prüfungen bleiben offen. Diese Ergebnisse schließen nicht sämtliche Planphasen.

### Quellcode-Veröffentlichungsunterlagen (2026-09-28)

Owner entschied damals MIT für eigenen Code, Source-only-Lernprojekt und den privaten Meldeweg
welcome@temmi.land; die Lizenzentscheidung wurde am 2026-11-07 auf GPL-3.0-only für eigene
Dateien geändert. Fremdmaterial bleibt unter seinen Upstream-Lizenzen.
Keine Testmail und keine Veröffentlichung/Remote-Mutation ausgeführt.
README/Notices/Architecture/ThreatModel/Contributor/Security/Changelog/Freigabecheckliste vorhanden.

Tatsächlich bestanden: Formatter-Lint 0/349 Dateien; Secret-Guard nach Staging einschließlich
neuer Dokumente (419 ausgewählte Textdateien); synthetische positive/negative Secret-Fixture
mit Inhalt-Unterdrückung; positive Debug-/Release-Konfigurationsmatrix aller vier Targets plus
drei negative Fixtures; YAML-Parsing; 41 lokale Dokumentlinks. SDK-Altinventar read-only geprüft:
76 Dateien, historischer Hash unverändert. Die drei kopierten Lizenztexte stimmen mit der
gepinnten Upstream-Revision überein (nur EOF-Newline normalisiert); keine rechtliche
Kompatibilitätsfreigabe daraus ableiten.

Private Mail-Erreichbarkeit, History-/Assets-/Notice-Owner-Review und ein grüner Remote-CI-Lauf
bleiben vor der tatsächlichen Quellcode-Veröffentlichung in der Checkliste. Ausführbare Signing-
Apps sind ausdrücklich nicht die gewählte erste Veröffentlichung.

Die folgende Gesamttabelle dokumentiert die frühere Baseline vor den anschließenden Modul-
Migrationen. Aktuelle betroffene Paketläufe sind darunter separat aufgeführt; verschobene Tests
werden nicht als neue Funktionsabdeckung oder erneut gelaufene Gesamtbaseline gezählt.

Umgebung: arm64 macOS, Swift 6.4 / Xcode 27. Die Zahlen stammen aus dem abschließenden
Swift-Testing-Ergebnis; die zusätzliche XCTest-Ausgabe „Executed 0 tests“ ist nicht die Anzahl
der ausgeführten Swift-Testing-Tests. Parametrisierte Argumentfälle werden nicht doppelt gezählt.

| Lokales Paket | Tests | Ergebnis |
| --- | ---: | --- |
| AppModules | 143 | bestanden |
| AuthFeature | 109 | bestanden |
| VaultFeature | 114 | bestanden |
| VaultCore | 29 | bestanden |
| SendFeature | 29 | bestanden |
| SettingsFeature | 28 | bestanden |
| AppArchitecture | 5 | bestanden |
| NetworkingKit | 1 | bestanden |
| VaultwardenSDK | 1 | bestehender Swift/Rust-FFI-Smoke-Test bestanden; keine Quelländerung |
| **Gesamt** | **459** | **bestanden** |

Die 27 Tests aus `VaultMutationPipelineTests`, `CredentialIdentityPublisherTests`,
`AppModelTests` und `DefaultAuthRepositoryTests` wurden zusätzlich fünfmal hintereinander
ausgeführt: alle Durchläufe bestanden. Explizite Task-Gates statt zeitabhängiger Sleeps prüfen
unter anderem FIFO, verspätete Writes, UI-Cancellation, Lock und OS-Write-Drain. Das ist kein
Nachweis aller möglichen Schedules oder echter paralleler App-/Extension-Prozesse.

macOS-App und iOS-Simulator-App einschließlich eingebetteter Extensions bauen anschließend
ohne Signing erfolgreich. `git diff --check` ist sauber. Es wurde kein signiertes Gerät und
kein echter Vaultwarden-Server getestet; es wurden keine Xcode-UI-Testtargets ausgeführt.

### Vorheriger Modul-Prüflauf: AutoFill ohne VaultFeature

Nach der Migration von Reader/Upsert, URI-Matcher/PSL und Cipher-HTTP-Service sind die betroffenen
Testtargets mit `--no-parallel` gebaut und vollständig ausgeführt:

| Paket | Aktueller ausgeführter Testsatz | Ergebnis |
| --- | ---: | --- |
| AppModules | 212 Swift-Testing-Tests + 2 XCTest-Filtertests | bestanden |
| VaultCore | 31 Swift-Testing-Tests | bestanden |
| VaultFeature (nur verbleibendes Legacy-Paket) | 82 Swift-Testing-Tests | bestanden |

Matcher-, Cache- und Passkey-Factory-Tests liegen jetzt bei AppModules. Neue Dateistore-Fixtures
prüfen Mutationserfolg und unveränderte Bytes bei veraltetem Unlock/Cache, fremdem Server,
Revision-Overflow, fehlender Datei und Autorisierungsfehler. Der reale SharedToken-Adapter prüft
den aktuellen Proof und gebundene Tokens unter dem bisherigen Prozess-Lock; seine neuen Tests
verweigern die Operation bei falschem Unlock, fehlenden Tokens und widerrufenem Grant.

XcodeGen wurde aus `project.yml` erneut ausgeführt. Der erzeugte App-/Extension-Graph enthält
kein VaultFeature mehr. macOS-arm64- und iOS-Simulator-App inklusive Extension bauen unsigned.
Die gepinnte PSL ist bytegleich verschoben; ihre dokumentierte SHA-256 stimmt weiterhin.
Dieser gezielte Prüflauf ersetzt keine erneute Ausführung der Gesamtbaseline, keinen signierten
OS-Context-Test und keine echte Server-/Cross-process-Matrix.

### Vorheriger Modul-Prüflauf: Vault-/Send-/Settings-Pakete aufgelöst

Die Model-/State-/Live-SDK-/Cipher-Tests und erforderlichen Fixtures liegen jetzt im
AppModules-Testtarget. Die vorher nur gegen ungenutzte Sync-/Attachment-/Identity-Services
laufenden Regressionen prüfen den produktiven Adapter statt einer parallelen Implementierung:

- `SDKVaultSyncTests`: SDK-Decryption, Org-Key-Initialisierung vor Decryption, HTTP-/Tokenfehler,
  partielle Antworten, fehlende Decryption-Ergebnisse und doppelte Cipher-/Org-IDs.
- `SDKVaultSourceTests` und `SDKVaultAttachmentSafetyTests`: verschlüsselte Metadata/Bytes,
  V2-/Download-/Delete-Endpunkte, Bearer-/Redirect-Policy, relative URLs, fremde Origins,
  fehlende Tokens und Multipart-Dateinamen. Bereits vorhandene Commit-/Revision-/Permission-
  Regressionen bleiben erhalten.
- `SDKVaultIdentityExportTests`: Password-/TOTP-/Passkey-Identitäten werden für normale Logins
  erzeugt, bei Re-Prompt oder versteckten Secrets aber bereits am SDK-Export ausgeschlossen.

Send-/Settings-Sources und ihre bestehenden Model-Tests wurden unverändert in
`SendPresentation`/`SettingsPresentation` eingeordnet. Die drei alten Feature-Manifeste,
ungenutzten Vault-Services und Legacy-Aliases sind gelöscht; `project.yml`, Testscript und
README verwenden den aktuellen Graphen. Es verbleiben sechs lokale Pakete, nicht das finale
Ziel von zwei. Auth-/Core-Migration und die übrigen Release-Gates bleiben offen.

Ausgeführt: **315 Swift-Testing-Tests in 41 Suites plus zwei XCTest-Filtertests**, alle bestanden.
Die höhere AppModules-Zahl ist überwiegend zusammengeführte Abdeckung, kein entsprechender
Zuwachs neuer Funktionen. Der erste Compilerlauf erforderte eine Korrektur der portierten
Initializer-Argumentreihenfolge. Anschließend scheiterte das standardmäßige SwiftPM-Xcode-Backend
bei der Archivierung an `errno=28` (Speicherplatz); der native Backend-Prüflauf baute und führte
den vollständigen betroffenen Testsatz erfolgreich aus. Das ist keine neue Gesamtbaseline.

Verwendeter ressourcenschonender lokaler Befehl:

```sh
swift test --package-path Packages/AppModules --build-system native \
  --scratch-path ${TMPDIR:-/tmp}/vault-feature-cleanup-native --no-parallel
```

Das native Backend ist in der installierten Swift-Version als deprecated markiert; es dient
hier nur als lokale Speicherplatz-Umgehung. Das Repository-Testscript behält den Standard.
Die eigens angelegten temporären Prüfordner werden nach den Läufen entfernt.

XcodeGen wurde erneut ausgeführt. `xcodebuild -list -json` bestätigt beide App-Targets und beide
Extensions. Der neue Graph enthält VaultPresentation, SendPresentation und SettingsPresentation,
aber keines ihrer alten Feature-Produkte. **macOS arm64 und generischer iOS-Simulator einschließlich
Extensions bauen unsigned erfolgreich**; `git diff --check` und die Syntaxprüfung des Testscripts
sind sauber. Offizielle SDK-/Vaultwarden-Subrepos sind unverändert.

```sh
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ${TMPDIR:-/tmp}/vault-feature-cleanup-macos CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ${TMPDIR:-/tmp}/vault-feature-cleanup-ios CODE_SIGNING_ALLOWED=NO build -quiet
```

Keine signierten Geräte, realen Server oder Cross-process-/UI-Testtargets wurden in diesem
Modulblock ausgeführt. Die entsprechenden Release-Gates bleiben offen.

### Vorheriger Modul-Prüflauf: Shared-Auth-Persistenz aus VaultCore gelöst

SharedTokens, SharedTokenStore/Transaction/Provider und SharedAutoFillUnlock/Store liegen jetzt
in Data. Ihre bisherigen Core-Tests sind nach AppModules verschoben. SharedAccountInfo und die
gleichen Keychain-Wire-Namen liegen SDK-frei in AutoFillContract; das KDF-/Environment-Mapping
liegt im BitwardenSDKAdapter. Keychain und Container werden explizit injiziert. VaultCore behält
für diesen Pfad nur die Übergangs-Komposition; Auth-Presentation/Bootstrap ist noch nicht migriert.

| Betroffenes Paket | Tatsächlich ausgeführter Testsatz | Ergebnis |
| --- | ---: | --- |
| AppModules | 350 Swift-Testing-Tests in 44 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature | 109 Swift-Testing-Tests in 11 Suites | bestanden |
| VaultCore | vier verbliebene Swift-Testing-Tests in zwei Suites | bestanden |

Neue Tests prüfen fehlenden Container vor jedem Keychain-Zugriff, den echten injizierten
Lock-Dateipfad mit 0600-Rechten, unveränderte v2-Wire-Namen/Envelope-Felder, Widerruf, SDK-KDF-
Grenzen/Defaults, unbekannte KDF-Typen, fehlenden Server und redigierte Beschreibungen.
27 bisherige Core-Tests wurden verschoben, nicht als neue Abdeckung gezählt. Acht neue Test-
Methoden ergänzen sie; parametrisierte Argumentfälle zählen nicht zusätzlich.

Eine vorhandene Biometrie-Testfixture verschluckte Setupfehler und erzeugte eine Compilerwarnung.
Sie ist jetzt throwing und verlangt eine persistierte Session; der Auth-Lauf wurde danach
inkrementell mit allen 109 Tests erneut ausgeführt und bestand ohne diese Warnung.
Die Tests liefen mit dem nativen SwiftPM-Backend als lokaler Speicherplatz-Umgehung; kein neues
Backend-/CI-Requirement und keine neue gesamte Paketbaseline.

```sh
swift test --package-path Packages/AppModules --build-system native \
  --scratch-path ${TMPDIR:-/tmp}/vw-shared-persistence-tests --no-parallel --quiet
swift test --package-path Packages/AuthFeature --build-system native \
  --scratch-path ${TMPDIR:-/tmp}/vw-shared-persistence-auth --no-parallel --quiet
swift test --package-path Packages/VaultCore --build-system native \
  --scratch-path ${TMPDIR:-/tmp}/vw-shared-persistence-core --no-parallel --quiet
```

Nach XcodeGen bauen beide App-/Extension-Schemes unsigned erfolgreich: macOS arm64 und
generischer iOS-Simulator. Auch der Produktionspfad von AuthKeychainStore ohne VaultCore-Import
und beide Extension-Targets mit direkter Data-Abhängigkeit sind damit kompiliert.
`git diff --check` und die Syntaxprüfung des Testscripts sind sauber. Offizielle SDK-/Vaultwarden-
Subrepos wurden nicht verändert; sämtliche eigens angelegten temporären Prüfordner sind entfernt.
Kein signiertes Gerät, echter Server oder paralleler App-/Extension-Prozess wurde damit verifiziert.

```sh
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath ${TMPDIR:-/tmp}/vw-shared-persistence-macos CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ${TMPDIR:-/tmp}/vw-shared-persistence-ios CODE_SIGNING_ALLOWED=NO build -quiet
```

### Vorheriger Modul-Prüflauf: Auth-Observation und Legacy-Package-Cleanup

Die fünf Auth-Screens und ihr typed Flow Controller verwenden Observation statt generischer
Store-/Processor-Wrapper. AuthFlowView enthält die Darstellung; die App injiziert eine gemeinsame
AuthServices-Konfiguration für Screens, Repository und PIN-Einstellungen. AuthSession sowie
AuthDependencies.live/liveKeychainStore und PinEnrollment.live sind entfernt. Navigation/UI Exit
retiriert Modelle, cancelt screen-eigene Tasks und leert Passwort/PIN/TOTP-Eingaben. Zwei-Faktor-
Secrets liegen nicht mehr im beobachteten State; Back-Callbacks halten nur die Serverumgebung.

AppArchitecture und das seit längerem nicht mehr verwendete NetworkingKit sind vollständig aus
Quellen, Manifesten, project.yml und Testscript entfernt. Der bestehende HTTP-Smoke-Test ist auf
den produktiven Networking.URLSessionHTTPClient portiert, mit unveränderlicher URLProtocol-
Response statt globalem mutable Handler. Die fünf Tests des gelöschten generischen Stores haben
keinen Produktionsgegenstand mehr; direkte State-/Observation-/Retained-Model-Invarianten sind
durch Tests der produktiven Auth-Models abgedeckt. Vier lokale Pakete verbleiben.

| Betroffenes Paket | Tatsächlich ausgeführter Testsatz | Ergebnis |
| --- | ---: | --- |
| AppModules | 351 Swift-Testing-Tests in 45 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature | 126 Swift-Testing-Tests in 13 Suites | bestanden |

17 neue Auth-Methoden prüfen caller-/route-owned Cancellation und Duplicate Suppression mit
expliziten Gates, Secret Clearing vor Navigation, ignorierte verspätete Fehler, Retry und direkte
Observation. Weitere Fixtures prüfen sauberen Coordinator-Restart, geteilte injizierte Speicher-
Konfiguration und Provider-Ownership nach akzeptiertem Handoff. Ein konkreter Nachreview-Fix:
Ein nicht kooperativer PIN-Crypto-Call konnte nach Cancellation einen anderen Fehler werfen und
dadurch einen falschen PIN-Versuch zählen. Jetzt werden Cancellation/Retirement vor dem Counter-
Write geprüft; der gated Test bestätigt unverändertes Budget und erhaltenes Enrollment. Die
höhere AppModules-Zahl ist ein portierter Test, keine neue Kompatibilitätsfunktion.

Die erste Kompilation korrigierte einen Biometrie-Testdouble von struct zu class entsprechend dem
vorhandenen AnyObject-Port. Der neue PIN-Kompositionstest benötigt ein echtes scoped Enrollment
inklusive Accountflag statt nur eines isolierten Fixture-Key-Writes. Die Assertions dieses
Kompositionstests bleiben erhalten; der abschließende vollständige Auth-Lauf besteht mit 126 Tests.

```sh
swift test --package-path Packages/AuthFeature --scratch-path .build/auth-observation-tests \
  --build-system native --no-parallel --quiet
swift test --package-path Packages/AppModules --scratch-path .build/appmodules-refactor-tests \
  --build-system native --no-parallel --quiet
```

Die ignorierten Build-Caches liegen jetzt auf dem Workspace-Volume mit ausreichend Speicher,
nicht auf der fast vollen Systempartition. Sie bleiben für inkrementelle Folgeprüfungen erhalten.
Das native SwiftPM-Backend bleibt eine lokale, deprecated Prüfoption, kein Repository-/CI-Standard.
VaultCore- und SDK-Testtargets wurden in diesem Block nicht erneut ausgeführt; ihre Quellen sind
unverändert. Die zuvor aufgeführte Gesamtbaseline wurde nicht als erneut bestanden ausgegeben.

Nach XcodeGen bestehen beide unsigned App-/Extension-Builds, einschließlich des abschließenden
PIN-/Cancel-Nachreviews. Kein AppArchitecture-/NetworkingKit-Produkt verbleibt im Projektgraphen;
die App-Targets deklarieren Networking und den SDK-Adapter jetzt direkt für die Komposition.
`git diff --check`, Shell-Syntax und die Source-Importsuche sind sauber. Offizielle SDK-/Vaultwarden-
Subrepos wurden nicht verändert. Keine signierten Geräte, realen Server, Xcode-UI-Testtargets oder
parallelen App-/Extension-Prozesse wurden in diesem Block geprüft.

```sh
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

U-506 ist erledigt; U-504/S-303 bleiben teilweise. Auth credential execution und SDK-geprägte
Contexts/Session-Callbacks liegen weiterhin im Übergangspaket, nicht hinter den finalen Domain-
Commands. Cancellation garantiert keinen Rollback bereits bestätigter Persistenz und keine
Zeroization nicht kooperativer SDK-/Swift-Buffer. Die realen Release-Gates bleiben offen.

### Vorheriger Modul-Prüflauf: VaultCore entfernt und Session-/Servergrenzen vereinheitlicht

VaultCore ist vollständig aus Quellen, Manifesten, project.yml und Testscript entfernt. Drei
lokale Pakete bleiben. Alle vier App-/Extension-Targets verwenden die gemeinsame Konfiguration
in Composition/SharedAppGroup.swift. Data.AuthenticatedSession erhält einen Domain-Account,
eine opaque SDK-Resource und den validierten persistenten Token-Scope; kein öffentlicher raw
Client/Token-Callback oder impliziter HTTP-Client bleibt. Die Projektion behält die exakte
persistierte Serveridentität trotz Domain-URL-Normalisierung, einschließlich alter trailing slashes.
Domain besitzt das einzige Servermodell und die Credential-Server-Policy mit validierendem Decode.
Session-Assembly und AutoFill-SDK-Bootstrap weisen unsichere Credential-Server zurück.

| Betroffenes Paket | Tatsächlich ausgeführter Testsatz | Ergebnis |
| --- | ---: | --- |
| AppModules | 364 Swift-Testing-Tests in 48 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature | 128 Swift-Testing-Tests in 13 Suites | bestanden |

Vier verbleibende Core-Testmethoden wurden portiert und tatsächlich ausgeführt, einschließlich
des realen Keychain-Add/Update/Read/Delete-Smokes mit ausschließlich synthetischem Test-Service
und eigener UUID. Das verifiziert keine signierten Shared-Keychain-Entitlements. Elf neue Methoden
prüfen Server-URL-/Decode-Policy, falsche Session-Scopes, exakte Legacy-Storage-Identität,
Widerruf über Session-Kopien, Ablehnung bereits widerrufener Ressourcen, injizierten HTTP-Zugriff
und kein HTTP nach Widerruf sowie ServerSetup-Normalisierung/Denial. Parametrisierte Fälle sind
Testargumente, nicht zusätzliche Testmethoden.

Die erste vollständige AppModules-Prüfung mit dem neuen HTTP-Test scheiterte an einer neuen
Assertion, die den vorhandenen Sync-Query `excludeDomains=true` ausgelassen hatte. Die Assertion
wurde auf den unveränderten produktiven Request korrigiert; der abschließende vollständige Lauf
mit 364 Tests besteht. Assertions wurden nicht entfernt und kein produktiver Query geändert.

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AuthFeature \
  --scratch-path .build/auth-observation-tests --build-system native --no-parallel --quiet
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
xcodegen generate
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

Beide unsigned App-/Extension-Builds bestehen mit regeneriertem Drei-Paket-Projektgraph.
Die ignorierten Workspace-Caches wurden inkrementell wiederverwendet und bleiben erhalten.
Das native SwiftPM-Backend ist eine lokale deprecated Prüfoption, kein CI-Standard.
Der SDK-FFI-Smoke und die historische Gesamttabelle wurden nicht erneut ausgeführt; offizielle
Bitwarden-/Vaultwarden-Quellen wurden nicht verändert. Keine realen Server, signierten Geräte,
Xcode-UI-Testtargets oder parallelen App-/Extension-Prozesse wurden in diesem Block geprüft.

S-303/U-504 bleiben teilweise: Auth-interne SDK-Contexts und Credential-Orchestrierung sowie der
Data-session Callback benötigen Domain-only Command-/Handoff-Ports. Stand dieses früheren Blocks: P-801 blieb offen;
SharedAppGroup behält den bisherigen persönlichen Team-Fallback und Bundle-/Entitlement-
Validierung fehlt. Release-/ATS-Matrix, Cross-process-Refresh und durables Recovery bleiben offen.
Keine neue Kompatibilitätsfunktion, Schema-Migration oder Zeroization-/Rollback-Zusage.

### Vorheriger Prüfblock: Contributor-Konfiguration und fail-closed Startup

Shared Base-/Debug-/Release-xcconfig liefert jetzt alle vier Bundle-IDs, App Group, private/shared
Keychain-Namen, expliziten App-ID-Prefix und Version. Local.example ist committed, Local.xcconfig
ignoriert. Persönliche Team-ID und Swift-Fallback sind entfernt. AppStartup/instance-based
AppComposition validieren Konfiguration und Container vor Credential-Stores/Repository/Model;
Main und Settings zeigen bei Fehlern eine stabile Recovery ohne Login oder Credential-Cleanup.
Extension-Factories scheitern ebenfalls vor Keychain-Zugriff. Der Cache und sein Autorisierungs-
Store verwenden dieselbe einmal aufgelöste Container-URL.

| Ausgeführte Prüfung | Ergebnis |
| --- | --- |
| AppModules: 374 Swift-Testing-Tests in 49 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature: 128 Swift-Testing-Tests in 13 Suites | bestanden |
| XcodeGen; unsigned macOS-arm64-App/Extension; generische iOS-Simulator-App/Extension | bestanden |
| Debug/Release, alle vier Targets: Default-IDs mit synthetischem Team | bestanden |
| Debug/Release, alle vier Targets: eigene Bundle-/Group-/Service-IDs und abweichender App-ID-Prefix | bestanden |
| Leeres Team; Prefix ohne abschließenden Punkt | beide erwartungsgemäß Exit 1 mit Diagnose |

Zehn neue Testmethoden mit parametrisierten Fällen prüfen die Default-Bundle-Familie, alternative
Contributor-Identifier, exakte Prefix-Separierung, fehlende/unexpandierte/kaputte Werte, fremde
Bundles, getrennte Services, aufgelöste/verweigerte Container und wertfreie Diagnosen. Nachreview:
Ein ursprünglich tolerierter Prefix ohne Punkt könnte Runtime und Entitlements verschieden
adressieren. Beide akzeptieren jetzt nur denselben expliziten Prefix mit Punkt; der neue negative
Test und das Settings-Prüfscript weisen die falsche Konfiguration ab. Der vollständige Lauf nach
dieser Korrektur besteht; keine Assertion wurde dafür abgeschwächt.

Das neue Script liest die tatsächlich expandierten Xcode-Settings, die Info.plist-/Entitlement-
Templates und DEBUG-Compilerbedingungen für beide Konfigurationen. Synthetische Command-line-
Overrides ändern keine Local-Datei und signieren nichts. Die positiven Prüfungen waren:

```sh
swift Scripts/verify-configuration.swift DEVELOPMENT_TEAM=AB123CDE45
swift Scripts/verify-configuration.swift DEVELOPMENT_TEAM=AB123CDE45 \
  VW_BUNDLE_ID_PREFIX=org.example.vault VW_APP_GROUP_IDENTIFIER=group.org.example.credentials \
  VW_SHARED_KEYCHAIN_SERVICE=org.example.shared-credentials \
  VW_PRIVATE_KEYCHAIN_SERVICE=org.example.private-credentials VW_KEYCHAIN_PREFIX=ZZ987ZYX65.
```

Die beiden negativen Aufrufe mit `DEVELOPMENT_TEAM=` bzw. mit Team und
`VW_KEYCHAIN_PREFIX=AB123CDE45` wurden ausgeführt und scheiterten mit der erwarteten Prefix-
Diagnose. Diese Fehlercodes sind bestandene Denial-Prüfungen, keine fehlgeschlagenen Builds.
Die tatsächlich erzeugten Debug-Produkt-Info.plists beider Apps und beider eingebetteten
Extensions wurden auf je acht Bundle-/Storage-/Versionswerte geprüft; alle Werte stimmen überein.
Ohne lokale Team-ID ist der
expandierte Prefix `.` und die Runtime verweigert Startup; genau dieser Fall ist unit-getestet.

Pakettests und finale Builds verwenden die inkrementellen Workspace-Scratch-/DerivedData-Pfade
und die Befehle aus dem vorherigen Prüfblock. Alle betroffenen Testtargets wurden ausgeführt,
nicht nur gebaut. Der SDK-FFI-Smoke wurde nicht erneut ausgeführt. `git diff --check`, plist-
Validierung und Source-Konfigurationssuche sind sauber; offizielle Subrepos unverändert.

Kein UI-Launch, Release-Produkt-Build, signierter Prozess, registrierter Identifier, Provisioning-
Profil, realer Server oder paralleler App-/Extension-Prozess wurde geprüft. Container-Auflösung
und Werteformat belegen keine Shared-Keychain-Berechtigung. Konfigurationscode ist lokal fertig,
aber P-801 bleibt mit vorgelagertem Quality Gate 5 und signierter Geräte-/Entitlement-Matrix
teilweise. P-803 und sämtliche realen Release-Gates bleiben offen. Keine Credential-Migration
oder neue Kompatibilitätsfunktion. Siehe [Contributor-Anleitung](ContributorConfiguration.md)
und [Entscheidung](ADR/008-build-configuration.md).

### Vorheriger Prüfblock: Auth-Transporte und gemeinsame KDF-Grenze

Prelogin und Passwort-/TOTP-HTTP samt Wire-Modellen, Form-Builder und Device-Metadaten sind aus
AuthFeature nach Data verschoben. Domain definiert SDK-freien Prelogin-Port, KDF-Parameter und
stabile Auth-Fehler. Ein SDK-Mapper validiert App-/Extension-Konversionen; Stored-/Shared-Mapping
und alle drei Returning-Unlock-Methoden verwenden dieselbe Grenze. HTTP prüft Credential-URL-
Policy und Cancellation vor Requests sowie nach nicht kooperativen Responses. Bestehende
Endpoints, Wire-Namen, connector und 2FA-Provider-Decodierung sind erhalten.

| Ausgeführte Prüfung | Ergebnis |
| --- | --- |
| AppModules: 405 Swift-Testing-Tests in 54 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature: 117 Swift-Testing-Tests in 12 Suites | bestanden |
| unsigned macOS-arm64-App samt AutoFill-Extension | bestanden |
| unsigned generische iOS-Simulator-App samt AutoFill-Extension | bestanden |

Insgesamt 524 Tests: 15 vorhandene Prelogin-/Identity-Transport-Testmethoden sind nach AppModules
portiert; 20 Methoden sind neu. Kein künstlicher Zuwachs durch doppelte Zählung portierter Tests.
Die gesamte historische Baseline und der SDK-FFI-Smoke wurden nicht erneut ausgeführt.

Neue Regressionen prüfen fehlende algorithmusspezifische Defaults, negative/nullgroße/überlaufende
Zahlen, unbekannte KDFs, direkt konstruierte ungültige Domain-Werte, Token-/Stored-/Shared-Mapping,
redigierte Beschreibungen, HTTP-Denial ohne Request und kontrollierte Cancellation. Auth-Fixtures
verwenden den echten Data-Prelogin-Adapter und den AuthUnlockFlow, aber SDK-Clients ohne FFI-
Handle: ungültiges Prelogin verhindert Token-Requests; ungültige Token-Metadaten verhindern
Crypto/Commit. Returning Unlock
verweigert vor Transition/Client/Crypto/Biometrie-Prompt; Eingaben werden geleert, PIN-Zähler und
Enrollment/Keys bleiben unverändert. Diese Tests führen keine echten Hash-/Unlock-Operationen aus.

Behoben sind Int->UInt32-Traps/stiller Unknown-KDF-Fallback, falsche nächste Unlock-Parameter
bei fehlenden Token-KDF-Feldern und Argon2-Shared-Freigabe mit PBKDF2-Iterationsdefault. Explizite
Token-Metadaten müssen vor Crypto/Persistenz zum Prelogin-KDF passen. Fehlende Felder übernehmen
die tatsächlich verwendeten Parameter; neue Logins speichern diese explizit im bisherigen Schema.
Legacy-Records werden nicht beim Lesen umgeschrieben. Zahlenvalidierung ist kein vollständiger
KDF-Kostenlimit- oder realer Interoperabilitätsnachweis.

Ein erster Auth-Testbuild scheiterte an einem fehlenden Data-Import in EnableBiometricsModelTests;
der Import ist korrigiert, ohne Kompatibilitäts-Re-Export. Ein erster AppModules-Lauf mit 404 Tests
fand einen bestehenden Cache-Testfehler: Die Assertion verglich JSON-Bytes nach Decode/Re-Encode
und hing damit an nicht garantierter Objekt-Key-Reihenfolge. Sie vergleicht jetzt das vollständige
JSON-Objekt einschließlich aller verschlüsselten Werte. Ein zusätzlicher absichtlich umsortierter
Fall prüft denselben Erhaltungsvertrag. Produktiver Cache-Code ist unverändert. Der finale gesamte
Lauf mit 405 Tests besteht; keine Assertion gelöscht und kein Zufalls-Retry als Verifikation.
Der abschließende Auth-Lauf nach Entfernen ungenutzter Imports besteht ebenfalls mit 117 Tests.

Tatsächlich ausgeführte finale Befehle aus dem Hauptverzeichnis:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AuthFeature \
  --scratch-path .build/auth-observation-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

Die bereits vorhandenen ignorierten Workspace-Caches bleiben erhalten. Der lokale native-SwiftPM-
Backend-Schalter ist deprecated und keine neue CI-Voraussetzung. Keine Projekt-/Manifest-Änderung,
deshalb kein erneutes XcodeGen nötig. `git diff --check` und Prüfung der offiziellen SDK-/Subrepo-
Pfade sind sauber; keine Änderungen dort.

S-303/U-504 bleiben teilweise: Keychain-Komposition, SDK-Token-Provider, Client-Erstellung,
Credential-Sequencing, Commit und pending SDK-Contexts liegen noch in AuthFeature. Data-Token-
Wirewerte im Übergangsflow sind keine Domain-only Command-/Presentation-Ergebnisse.
AuthPresentation bleibt Domain/SharedUI-only; die drei Pakete bleiben bis zur restlichen Migration.
Kein UI-Launch, Release-Produkt-Build, echter Server, signierte Biometrie/Keychain-/Container-Prüfung
oder paralleler App-/Extension-Prozess in diesem Block. Durables Recovery und reale Runtime-/
Commit-Races bleiben offen. Keine Zeroization-/Rollback-Zusage, kein vollständig geschlossenes
Release-Gate und keine neue Kompatibilitätsfunktion. Siehe [Entscheidung](ADR/009-auth-transports-and-kdf.md).

### Vorheriger Prüfblock: Data-Credential-Autorität und sessiongebundene PIN-Settings

Stand 2026-09-28: AuthCredentialStore, AppAuthTokenProvider/Bootstrap und StoredAccount->Domain-
Mapping liegen jetzt in Data statt AuthFeature. AppComposition erzeugt den Credential-Store nach
Konfigurationsvalidierung einmal und injiziert ihn direkt in Lifecycle-Repository und AuthServices.
Data.SessionPinUnlockSettings implementiert den Domain-Port gegen denselben Store und Runtime;
die Feature-eigene PinEnrollment und die Lifecycle-/PIN-Kompositionsadapter sind entfernt.
Keychain-Namen, Schema, Schutzklassen, Lock-Datei und exakte persistierte Serveridentität bleiben gleich.
Data braucht keine SDK-Imports; die SDK-Token-Konformität liegt im SDKManagedTokenAdapter.

| Ausgeführte Prüfung | Ergebnis |
| --- | --- |
| AppModules: 477 Swift-Testing-Tests in 62 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature: 63 Swift-Testing-Tests in acht Suites | bestanden |
| unsigned macOS-arm64-App samt AutoFill-Extension | bestanden |
| unsigned generische iOS-Simulator-App samt AutoFill-Extension | bestanden |

Insgesamt 542 Tests. 54 vorhandene Methoden aus vier Speicher-/Token-Suites sind portiert, nicht
als neue Coverage gezählt. 18 Methoden sind neu: Shared-Publikation, sessiongebundene PIN-
Einstellungen, SDK-Token-Callback und Bootstrap-Authority. Die finalen vollständigen Testtargets
wurden ausgeführt. Der SDK-FFI-Smoke und die historische Neun-Pakete-Baseline wurden nicht wiederholt.

Die erste Portierungsrunde baute den SDK-Token-Adapter als Struct; das SDK-Protokoll ist class-bound.
Korrigiert zu einer finalen Klasse mit unveränderbarer Sendable-Funktion, ohne SDK-Änderung.
Die erste neue Test-Kompilierung verlangte Equatable für PersistedAuthSession; stattdessen prüfen
die Fixtures explizit alle Felder (Schema, Account, Scope, Tokens). Keine Produktions-Konformität
nur für Tests und keine Assertion entfernt. Die finalen Läufe nach diesen Korrekturen bestehen.

Der KDF-Nachreview fand eine reale Lücke: Der Producer lieferte korrekt normalisierte Argon2-
Legacy-Werte, der Shared-Write verglich aber noch rohe PBKDF2-/Nil-Defaults und konnte sie ablehnen.
Die Speicherung vergleicht nun die gleiche kanonische Abbildung. Tests gehen durch den echten
AuthCredentialStore-/SharedAutoFillUnlockStore-/SharedTokenStore-Pfad: fehlender KDF-Typ bzw.
PBKDF2/Argon2-Defaults und teilweise vorhandene Argon2-Metadaten publizieren Grant plus passend
gebundene Tokens; der private Record einschließlich Legacy-Trailing-Slash bleibt unverändert.
Veränderte User-/Mail-/Server-/Wrapped-Key-/Algorithmus-/Kostenwerte verändern keinen gültigen
Grant; invalides Stored-KDF und eine alte Publikations-Epoch autorisieren keinen neuen Grant.
Das beweist lokale Speicherung, nicht reale SDK-Crypto oder signierte Extension-Berechtigungen.

PIN-Settings validieren vor Derivation und nach Suspension. Continuation-Gates halten den
echten Data-Flow kontrolliert an, während Runtime, Storage-Epoch oder Sign-in-Lineage widerrufen
wird; ein nicht kooperatives Crypto-Ergebnis kann danach kein Enrollment schreiben. Enrollment/
Removal vergleichen den vorab erfassten Epoch im Write-Lock. Weitere Fälle prüfen normalen
Enroll/Read/Remove, Cryptofehler, Counter-Write-Rollback, abgebrochene Consumer und dass eine
obsolete Settings-Instanz aktuelle Keys/Flags nicht entfernen kann. Separate Items sind weiter
keine atomare Keychain-Transaktion; OS-/Cross-process-Races sind dadurch nicht vollständig geprüft.

Bootstrap prüft Server-Policy vor Storage-Proof-Erfassung sowie Account/Server/Scope/Epoch beim
Returning-Provider. Ein frischer Provider liefert keine alten Tokens und startet bei Commit eine
neue Lineage. Der SDK-Callback hält keine eigene Autorität; Cancellation vor bzw. während einem
nicht kooperativen Lookup verweigert Token-Ausgabe. Neue Mocks sind synchronisiert und halten
keinen Mutex über Await. Alle Gate-/Crypto-Fixtures verwenden synthetische Werte, kein SDK-FFI.

Finale Befehle aus dem Hauptverzeichnis, vorhandene ignorierte Caches wiederverwendet:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AuthFeature \
  --scratch-path .build/auth-observation-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

Kein Projekt-/Manifest-Umbau, daher kein neues XcodeGen. Der lokale native-SwiftPM-Schalter
ist keine CI-Voraussetzung. Diff-/Import-Grenzprüfungen sind sauber; offizielle SDK-/Subrepos
unverändert. Kein UI-Launch, Release-Produkt-Build, signierter Prozess, realer Server oder Geräte-/
Cross-process-Test. AuthFeature sequenziert weiter Login/TOTP/Unlock, erzeugt rohe SDK-Clients,
hält pending SDK-Contexts und initiiert Data-Commit/Handoff. Die Presentation konsumiert noch
Data-Payloads/Storage-Fehler, keine finalen Domain-only Ergebnisse. Durables Recovery und
operation-eigene Commit-/Cancellation-Semantik bleiben offen; kein Release-Gate geschlossen.
Siehe [Entscheidung](ADR/010-auth-credential-authority.md).

### Vorheriger Prüfblock: Login-/TOTP-Commands und opaque Auth-Capabilities

Stand 2026-09-28: Data.PasswordSignInService sequenziert frischen Login/TOTP inklusive Crypto und
privatem Commit. Domain definiert Command-/Challenge-/Pending-Ports und stabile Rejection-Ergebnisse.
LoginModel, TwoFactorModel und EnableBiometricsModel erhalten nur Domain-Ports; ihre alten
raw SDK-/Credential-Route-Contexts und AuthUnlockFlow sind gelöscht. Returning UnlockModel bleibt
der nächste Übergangspfad. SDKAuthCredentialCryptography kapselt dieselbe opaque Ressource von
Hash bis Handoff, ohne Client-/Token-/Key-Properties im UI-Kontext.

| Tatsächlich ausgeführte finale Prüfung | Ergebnis |
| --- | --- |
| AppModules: 496 Swift-Testing-Tests in 64 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature: 62 Swift-Testing-Tests in acht Suites | bestanden |
| unsigned macOS-arm64-App samt AutoFill-Extension | bestanden |
| unsigned generische iOS-Simulator-App samt AutoFill-Extension | bestanden |

Insgesamt 560 Tests. Vier vorhandene Methoden sind nach AppModules portiert (JWT und Token-KDF),
nicht als neue Coverage gezählt. 18 neue Methoden prüfen produktive Data-Orchestrierung und
Domain-only Model-Callbacks. Die vollständigen Testtargets wurden ausgeführt, nicht nur gebaut.
Synthetische Tokens/Keys, synchronisierte In-Memory-Stores, no-handle SDK-Ressourcen und
Continuation-Gates ersetzen keine echten Hash-/FFI-/Server-/OS-Tests.

Geprüfte neue Invarianten:

- Fresh-Proof entsteht vor der Device-/Prelogin-Suspension. Nach jedem Prelogin-/Hash-/Token-/
  Unlock-Await führen Caller-Cancellation, Lock bei gleicher Lineage und neuer Account zu Denial
  ohne nächsten Stage/privaten Commit. Ein vorhandener bzw. ersetzter Record bleibt unverändert.
- TOTP-Retry behält ursprüngliche Autorität; parallele Submits duplizieren keinen Grant. Provider
  0 ist die einzige ausführbare 2FA-Art. Widerruf während nicht kooperativem Token-Request verhindert
  Crypto/Commit. Nach Erfolg bleibt dieselbe Attempt-ID, Retry-Credentials werden entfernt und
  Retirement/Widerruf der alten Challenge kann die Nachfolge-Session nicht beenden.
- Ungültiges Token-KDF, leerer Subject/Refresh/Wrapped-User-Key und invalide Expiry erreichen keinen
  SDK-Unlock. Unbekannte Wire-Diagnosen werden nie als Domain/UI-Text weitergereicht.
- AutoFill-Publikation erfolgt erst explizit; late Key-Derivation nach Lock publiziert/enrollt nicht.
  Der Handoff ist single-use, verwendet dieselbe Resource und installiert Expiry vor Rückgabe.
  Auch Fehler vor Runtime-Erstellung widerrufen den Kandidaten in Data. Wiederholung ersetzt keinen
  Expiry-Handler. Definitiver Refresh-Reject revokiert genau den übergebenen Runtime/Resource.
- Domain-only Modell-Fixtures belegen Secret-Clearing vor Login-/TOTP-Callback sowie Widerruf später
  Login-Capabilities nach Retirement. Der vorhandene Coordinator-Test erhält accepted Provider
  nach UI-Teardown. Kein Assert aus den portierten Tests entfernt.

Zwischenstände hatten einen versehentlich duplizierten Coordinator-Block und veraltete Context-
Fixtures; korrigiert vor den erfolgreichen vollständigen Targets. Ein neuer Testfixture verwendete
zunächst einen nicht existierenden Refresh-Enum-Fall bzw. fehlenden Networking-Import. Die finale
Kompilierung/Läufe enthalten alle Korrekturen; keine SDK- oder Produktions-Konformität nur für Tests.

Finale Befehle aus dem Hauptverzeichnis mit wiederverwendeten ignorierten Workspace-Caches:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AuthFeature \
  --scratch-path .build/auth-observation-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

Kein Manifest-/Projekt-Umbau und kein neues XcodeGen. Der lokale native-SwiftPM-Schalter ist keine
CI-Voraussetzung. Import-/Diff-Prüfungen bestehen; offizielle SDK-/Subrepos unverändert.
Returning-Unlock, Data-shaped Restore/Root-Handoff und die AuthFeature-Paketauflösung bleiben
offen. Private bestätigte Writes werden bei anschließender UI-Cancellation nicht rückgängig gemacht;
operation-eigene Cancellation-/Commit-Semantik und durables Recovery sind noch unvollständig.
Kein SDK-FFI-Smoke, echter Server, signiertes Gerät/Entitlement, UI-Launch, Release-Produkt-Build
oder Cross-process-Lauf in diesem Block. Keine Zeroization-/Rollback-Zusage, kein Release-Gate
geschlossen und keine neue Kompatibilitätsfunktion.
Siehe [Entscheidung](ADR/011-auth-command-capabilities.md).

### Neuester Prüfblock: Returning-Unlock-Commands und epochgebundene Mutationen

Stand 2026-09-28: Passwort-/PIN-/Biometrie-Returning-Unlock läuft in Data.ReturningUnlockService.
UnlockModel/State und alle Auth-Routen konsumieren nur Domain-Werte/Commands; keine Wrapped Keys,
raw Client, TokenScope oder Credential-Store im Screen. Die SDKClientFactory und Storage-/SDK-
Aliases sind entfernt. AuthFeature hat keine direkten SDK/AutoFillContract/SecurityStorage-
Produktabhängigkeiten mehr; Testfixtures bleiben explizit als Testabhängigkeiten. Restore/root
Service-Komposition bleiben transitional; AuthFeature ist noch nicht entfernt.

| Tatsächlich ausgeführte finale Prüfung | Ergebnis |
| --- | --- |
| AppModules: 510 Swift-Testing-Tests in 65 Suites + zwei XCTest-Filtertests | bestanden |
| AuthFeature: 65 Swift-Testing-Tests in acht Suites | bestanden |
| unsigned macOS-arm64-App samt AutoFill-Extension nach Manifestbereinigung | bestanden |
| unsigned generische iOS-Simulator-App samt AutoFill-Extension nach Manifestbereinigung | bestanden |

Insgesamt 577 Tests. 14 neue Data- und drei neue Model-Methoden ergänzen die bisherigen Assertions;
keine bestehenden Methoden/Assertions als neue Coverage gezählt oder entfernt. Die neuen Data-
Fixtures verwenden synthetische In-Memory-Stores, no-handle SDK-Ressourcen und Continuation-
Gates, die neuen Model-Fixtures nur Domain-Ports. Die kompletten Testtargets wurden ausgeführt.

Geprüft sind normale Passwort/PIN/Biometrie-Transfers und AutoFill-Publikation, alte Command-
Retirement ohne Nachfolger-Widerruf, Crypto-Cancellation/Lock bei gleicher Lineage, late nicht-
Cancellation-PIN-Fehler ohne Budgetverbrauch, unavailable-biometry nach Lock ohne Enrollment-
Cleanup, Ersatzaccounts, persistierte Budgetprüfung ohne UI-Availability, akzeptierter PIN bei
fehlgeschlagenem Reset, Counter plus Cleanupfehler, finaler Publikationsabbruch sowie Begin-Port-
Cancellation-Reconciliation. Vier Mutation-Arten verweigern einen alten Epoch innerhalb der
Storage-Transaktion. UI-Fixtures belegen beide Callbackpfade mit geleerten Secrets, Revocation
später Capabilities und PIN-Recovery allein anhand Domain-State/-Failure.
Ein übrig gebliebener Biometrie-Key mit deaktiviertem Account-Flag autorisiert keinen OS-/Crypto-
Unlock; der neue negative Data-Fall verweigert bereits vor dem Prompt.

Sichtbare Scope-Lücke gefixt: Sign-in-Scope überlebt Lock; Counter/Reset/PIN-/Biometrie-Cleanup
brauchen zusätzlich den vor Suspension erfassten Epoch unter dem Write-Lock. Die Produktion hat
keinen scope-only Bypass mehr. Separate Keychain-Items und konkurrierende Settings-/Key-Replacement-
Writes sind damit nicht vollständig transaktional oder als signierte Multi-Scene-Race verifiziert.
Der Service erhält MainActor-Isolation für Plattform/Gate und ruft asynchrone SDK-Adapter auf;
das ist kein Performance- oder echtes OS-Prompt-Verhalten-Nachweis.

Finale Befehle aus dem Hauptverzeichnis, vorhandene Workspace-Caches erhalten:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AuthFeature \
  --scratch-path .build/auth-observation-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

Xcode löst das geänderte lokale Manifest auf; project.yml/Projektprodukte bleiben gleich, kein
XcodeGen erforderlich. Der lokale native-SwiftPM-Schalter ist keine CI-Voraussetzung. Diff-/
Importprüfungen bestehen, offizielle SDK-/Subrepos unverändert. Restore/root factory/handoff und
finales AuthPresentation-/Package-Cleanup, durable Recovery, volle repository-/operation-eigene
Cancellation-/Commit-Semantik und reale Settings-/Server-/Geräte-/Prozess-Matrix bleiben offen.
Kein SDK-Crypto-/Server-Smoke, UI-Launch, signiertes Gerät/Entitlement, Release-Produkt-Build oder
Cross-process-Lauf in diesem Block; kein Zeroization-/Rollback-Versprechen und kein Release-Gate.
Keine neue Vaultwarden-Kompatibilitätsfunktion.
Siehe [Entscheidung](ADR/012-returning-unlock-commands.md).

### Reproduzieren

Aus dem Hauptverzeichnis baut und testet `./Scripts/test-packages.sh` die zwei verbliebenen
lokalen Pakete. Die neun Einträge der Gesamttabelle oben sind die historische Baseline.
Für die einzelnen Läufe wurde jeweils `swift test` im Paketverzeichnis verwendet; AppModules
verwendete wegen bestehender Build-Caches den expliziten Scratch-Pfad:

```sh
cd Packages/AppModules
swift test --scratch-path ${TMPDIR:-/tmp}/vw-refactor-tests
swift test --scratch-path ${TMPDIR:-/tmp}/vw-refactor-tests --skip-build \
  --filter 'VaultMutationPipelineTests|CredentialIdentityPublisherTests|AppModelTests|DefaultAuthRepositoryTests'
```

Der zweite Befehl wurde fünfmal ausgeführt. Der Scratch-Pfad ist eine lokale Optimierung,
keine Projektvoraussetzung. Die unsigned Builds sind auch über `Scripts/build-unsigned.sh`
reproduzierbar; die geprüften Einzelbefehle aus dem Hauptverzeichnis waren:

```sh
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'generic/platform=macOS' -derivedDataPath ${TMPDIR:-/tmp}/vw-auth-safe-errors \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath ${TMPDIR:-/tmp}/vw-auth-safe-errors \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

### Portierung und tatsächlich gefundene Defekte

- VaultProcessor-/State-Tests verwenden jetzt den aktuellen Repository-Port und Domain-Snapshots.
  HTTP-/Crypto-Assertions liegen bei `SDKVaultSourceTests` am **echten** `SDKVaultSessionSource`
  mit injiziertem Crypto-/HTTP-Fake, nicht in einem nachgebauten UI-Servicegraphen. Der produktive
  Crypto-Adapter ist unverändert; sein Port ist jetzt explizit `Sendable` und injizierbar.
- Neue `VaultMutationPipelineTests` prüfen den echten Repository-/Cache-/Identity-Verbund mit
  einem SDK-freien Source-Fake. Bestätigte Writes bleiben trotz UI-Cancellation konsistent;
  Projektionsfehler, committed-error, FIFO und verspätete Ergebnisse nach Lock sind abgedeckt.
- **Fehlgeschlagener Logout:** `restore()` konnte einen verbliebenen privaten Account erneut als
  locked übernehmen. `DefaultAuthRepository` merkt ausstehenden Cleanup, verweigert Restore/
  Unlock-Handoff und verhindert die Herabstufung eines ausstehenden Logout zu Lock. Ein explizit
  erfolgreicher Cleanup hebt die Sperre auf. Die Sperre ist noch nicht über Prozessneustarts durabel.
- **Veraltete Attachment-Bestätigung:** Ein alter Callback konnte eine Bestätigung ohne gültiges
  Ziel stehen lassen. Sie wird nun bei fehlendem, anderem, mehrdeutigem oder nicht mehr editierbarem
  Attachment verworfen. Verspätete Downloads nach Navigation werden ohne Preview bereinigt.
- Zusätzliche Regressionen prüfen Picker-Abbruch/-Fehler ohne Upload, Attachment-Cancel und
  Berechtigungsentzug, stabile Generatorfehler sowie lokale Revision-/Re-Prompt-/Permission-
  Änderungen während der Verschlüsselung vor dem HTTP-Write. Der echte Source-Export schließt
  Re-Prompt sowie versteckte, nicht auflösbare und mehrdeutige Collection-Permissions aus.
- Während Save sind Cancel und interaktives Sheet-Dismiss deaktiviert: eine eingereichte Mutation
  gehört dem Repository; die UI darf kein Rückgängigmachen eines möglichen Server-Commits versprechen.
  Programmatischer Dismiss, Ersatz-Drafts und Runtime-Widerruf behalten ihre Ergebnis-Guards.
- Swift-6-Testkompilierung korrigiert: fehlende Imports, MainActor-Defaultargumente, throwing
  Assertions, SDK-UUID-Fixture und asynchrone `#expect`-Aufrufe. Assertions wurden nicht entfernt,
  um fehlgeschlagene Tests grün zu machen.

### Neuester Prüfblock: Domain-only Restore/Handoff und vollständiges AuthPresentation

Stand 2026-09-28: Alle Auth-Produktquellen, Controller und RootView liegen in AppModules.AuthPresentation
mit ausschließlich Domain/SharedUI-Abhängigkeiten. Domain.AuthFlowCommands liefert Restore und
Prepared-Runtime-Capability; Data.DefaultAuthFlowService besitzt die konkrete Assembly. AppComposition
konvertiert allein zur konkreten Data.AuthenticatedSession für den bestehenden Adapter. Produktive AuthServices
und das AuthFeature-Manifest sind entfernt; AuthDependencies ist eine reine Testfixture.
project.yml/Testscript verwenden nur AppModules und VaultwardenSDK. Private Keychain-Namen
(einschließlich historischem .AuthFeature-Suffix) und persistierte Serveridentität bleiben unverändert.

| Tatsächlich ausgeführte finale Prüfung | Ergebnis |
| --- | --- |
| AppModulesArchitectureTests + AuthPresentationTests: 589 Swift-Testing-Methoden in 75 Suites | bestanden |
| AppModules: zwei bestehende XCTest-Filtertests | bestanden |
| XcodeGen-Regeneration und xcodebuild -list -json: zwei Apps, zwei Extensions | bestanden |
| unsigned macOS-arm64-App samt AutoFill-Extension mit AuthPresentation | bestanden |
| unsigned generische iOS-Simulator-App samt AutoFill-Extension mit AuthPresentation | bestanden |

591 Tests insgesamt. Die 65 bisherigen Auth-Methoden sind portiert, nicht als neue Coverage
gezählt. Zehn neue Data- und vier Domain-only Controller-Methoden sind hinzugefügt; keine bisherigen
Assertions entfernt. Die Store-/SDK-Fakes bleiben ausschließlich in Testtargets, und die neuen
Controller-Tests importieren weder Data noch SDK. Die vollständigen Targets wurden ausgeführt,
nicht nur kompiliert. Die erste neue Testkompilierung hatte falsche Fixture-Key-/Protection-Namen;
sie sind korrigiert und im finalen vollständigen Lauf enthalten.

Geprüft: First Run, exakte Legacy-Serveridentität, keine Unlock-Transition durch bloße Anzeige,
Split-Record-Migration ohne Tokenimport, unsichere Legacy-URLs, Read-/Decodefehler und Account-
Mismatch. Nichtkooperative Repository-Hops sind an Restore und Snapshot gated; Task-Abbruch,
Lock/Logout und Accountreplacement verweigern stale Ergebnisse. Single-use Handoff erhält dieselbe
Ressource und installiert Expiry vor Rückgabe; Repository wird vor App-Benachrichtigung markiert.
Ein obsoleter UI-Restore revokiert late Commands, obsoleter UI-Handoff revokiert late Runtime,
accepted UI-Teardown revokiert die übertragene Session nicht. Diese Checks behaupten keinen
atomaren Snapshot über mehrere Keychain-Reads oder echte OS-/SDK-Crypto-Ausführung.

Finale Befehle aus dem Hauptverzeichnis, Workspace-Caches erhalten:

```sh
bash Scripts/generate-xcodeproj.sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -list -json
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

Der native-SwiftPM-Schalter ist nur die lokale Cachewahl. Die entfernten AuthFeature-Testmethoden
laufen jetzt im expliziten AuthPresentationTests-Target, nicht in einem verlassenen Paketcache.
Die alten Paket-/Build-Berichte oben sind datierte Historie und kein aktueller Consumergraph.

C-902 lokal erfüllt; S-303/U-504/C-901/C-903 bleiben teilweise für den finalen Repository-
Observationsworkflow, konkreten App-Adapter, operation-eigene Commit-/Cancellation-Semantik,
durable Recovery und Extension-Orchestrierung. Signierte Geräte/Entitlements, Multi-Window-/Key-
Replacement-/Server-/Cross-process-Matrix, Release-Produkt-Build, UI-Launch und SDK-FFI-Smoke wurden
in diesem Block nicht ausgeführt. Offizielle SDK-/Subrepos unverändert; kein Release-Gate,
Zeroization-/Rollback-Versprechen oder neue Vaultwarden-Kompatibilitätsfunktion.
Siehe [Entscheidung](ADR/013-auth-presentation-and-handoff.md).

### AutoFill query/assertion and invocation assembly (2026-09-28)

AutoFillVaultStore contains composition only; AutoFillData owns the invocation assembly and
CredentialQuery/PasskeyService actors. SDK configuration/mapping and assertion JSON stay in
BitwardenSDKAdapter; AutoFillData has no direct SDK import/dependency. Metadata-only picker
summaries replace password/seed-bearing state. Lists expose partial-item warnings; fulfilment
resolves secrets afresh. Assertion binds the current exact RP and unique selected credential,
checks late authorization/cancellation and rejects a different returned credential ID.

| Actually executed final check | Result |
| --- | --- |
| Complete AppModulesArchitectureTests + AuthPresentationTests: 612 Swift-Testing methods, 78 suites | passed |
| AppModules: two existing XCTest filter tests | passed |
| unsigned macOS-arm64 app + AutoFill extension | passed |
| unsigned generic iOS-Simulator app + AutoFill extension | passed |

614 tests total; 23 new methods (nine query, nine passkey, five session assembly). No existing
assertions removed. Explicit continuation gates test cancellation/lock/policy after suspension,
partial errors, duplicate identities, fresh secrets, exact assertion request bytes, concurrent
assertion exclusion and retained-query resource revocation. Synthetic SDK models and no-handle
resources do not execute SDK cryptography. The full test targets ran, not just compilation.
Intermediate compile failures involved fixture initializers, an incorrect contract import and
the adapter's optional SDK username; these were corrected before the final complete run. The
project was regenerated to include the new platform assertion source; no build caches deleted.

Final commands, from the repository root:

```sh
bash Scripts/generate-xcodeproj.sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

The native SwiftPM backend is the local cache choice, not a CI requirement. X-601/X-602/X-603
remain partial: SDK-shaped FIDO/registration bridges, silent SDK field degradation, controller/
OS-context coverage and concrete-request fallbacks are not completed here. X-604 registration
cache/identity projection and confirmed-write recovery remain open. No SDK FFI smoke, server
smoke, signed devices/entitlements, Release product build, UI launch or concurrent-process run
was executed in this block. Official SDK/subrepos remain unchanged. No release gate or new
Vaultwarden compatibility flow is claimed. See [the decision](ADR/014-autofill-query-and-passkey-orchestration.md).

### Identified AutoFill request follow-up (2026-09-28)

Direct OS passkey identities now resolve only their selected cipher/exact credential; list matching
is not invoked on that path. Three new parameterized PasskeyService methods prove that an unrelated
damaged item is not decrypted, no other credential substitutes an invalid/missing/ambiguous
identity, exact RP is required and late cancellation/lock/policy changes deny output.

Failed identified password/TOTP fulfilment now cancels rather than opening an unscoped vault
picker. Identifier-free manual browsing remains confined to explicit list entry points. This
controller path was reviewed and built for both platforms, not executed in an OS-context harness.
The identified-request debug log also no longer includes the record identifier.

Executed again with the same complete-target/build commands above: 615 Swift-Testing methods in
78 suites plus two XCTest tests, **617 total**, and both unsigned macOS-arm64/iOS-Simulator app/
extension builds passed. SDK/subrepos unchanged. Existing assertions retained; no Release/signed/
server/SDK-crypto/process gate inferred. The broader controller/context and error matrix remain open.

### Passkey registration mutation/journal and app-sync recovery (2026-09-28)

The live extension callback now submits through an operation-owned AutoFillData writer and
reserves a persistent mutation ID/public credential metadata before HTTP. The App Group journal
uses the shared grant/token transaction lock, atomic replacement, file synchronization and 0600
permissions. Unknown/confirmed writes remain nonretryable; rejection cleanup failure retains the
marker. Cache/confirmation failure after success produces repair rather than an ignored `try?`.
The SDK's wrapped callback/post-commit error cannot silently reopen Save actions.

The actual app repository/composition now reconciles journal records only after full sync and
matching cache/OS projection. It requires the exact unique credential/RP/known cipher; absent
or ambiguous matches, storage failure and partial projection remain a visible Domain warning.
Ordinary CRUD cannot clear that warning; lock prevents late recovery snapshots.

| Actually executed final check | Result |
| --- | --- |
| Complete AppModulesArchitectureTests + AuthPresentationTests: 645 Swift-Testing methods, 81 suites | passed |
| Two existing AppModules XCTest filter tests | passed |
| unsigned macOS-arm64 app + AutoFill extension | passed |
| unsigned generic iOS-Simulator app + AutoFill extension | passed |

647 total, thirty new methods: ten mutation writer, seven real-file journal, four reconciler,
four SDK HTTP-classification, four repository pipeline, one presentation state. Existing assertions
remain. Explicit continuation gates cover UI cancellation versus runtime revocation, parallel
callbacks, ambiguous/rejected/confirmed outcomes, proof/account changes, recovery ordering and
late lock. Temporary-file tests verify recreation, foreign-account retention, future/corrupt/
duplicate records, restricted permissions and concurrent store reservations. Initial fixture
compilation found invalid async/throwing autoclosure expressions; values were materialized before
asserting, without removing the assertions. Final complete targets were executed, not just built.

Final commands from the repository root, existing workspace caches retained:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

No target graph or extension file list changed, so this block did not need project regeneration.
SDK FFI/actual callback wrapping, real server create/update/payload round-trips, signed entitlements/
devices, process termination/power-loss durability, cross-process OS races, UI launch and Release
product builds were not executed. Immediate extension-side system identity publication and an
explicit safe resolution workflow for unobserved outcomes remain open; the latter stays blocked
even after a sync without the recorded credential. No server idempotency/atomic multi-system
transaction, new compatibility feature or release gate is claimed. SDK/subrepos unchanged.
See [registration recovery decision](ADR/015-passkey-registration-write-recovery.md).

### Incremental registration identity projection (2026-09-28)

The live extension writer now awaits cache-first single-passkey system publication in its own
mutation Task. Exact proof/UUID/monotonic-revision/encrypted-record receipts are revalidated around
metadata/OS awaits. SDK-decoded bytes, RP and cipher policy select the new credential; the existing
Data descriptor mapper is reused. The sole platform adapter requires incremental capability and
strict metadata; no partial-vault replace-all fallback is permitted. Late invalidation or an
uncertain add error triggers targeted removal, with cleanup failure explicitly classified. The
writer returns durable repair rather than repeating HTTP, and the journal still needs full app sync.

| Actually executed final check | Result |
| --- | --- |
| Complete AppModulesArchitectureTests + AuthPresentationTests: 662 Swift-Testing methods, 84 suites | passed |
| Two existing AppModules XCTest filter tests | passed |
| XcodeGen from project.yml: PlatformServices in both extension targets | passed |
| unsigned macOS-arm64 app + AutoFill extension | passed |
| unsigned generic iOS-Simulator app + AutoFill extension | passed |

664 total; seventeen new methods: seven projection actor, three real encrypted-cache receipt,
two SDK metadata, three platform mapping/capability, two asynchronous mutation writer. Explicit
continuation gates cover metadata/OS awaits, runtime lock, cache changes, targeted removal and
cleanup failure, busy projection and UI cancellation during async projection. Receipts reject
changed proof, account, UUID, monotonic revision, encrypted DTO, missing/duplicate records and
ineligible DTOs. Legacy caches without a monotonic revision require full app repair. Initial
compiler checks found an optional UUID and actor accesses inside boolean autoclosures; these
were corrected without dropping assertions. Final complete targets were executed, not just built.

Final commands from the repository root, caches retained:

```sh
bash Scripts/generate-xcodeproj.sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

No actual OS-store call, SDK crypto/FFI smoke, real server, signed device/entitlements, process
kill/power-loss, UI launch or Release build was executed here. There is no cross-process OS-write
queue or atomic file/OS/HTTP transaction. App replacement/clear can overlap extension add and
late compensation can remove the same identity a newer sync published; full sync must repair
that. Process termination can skip compensation. These signed matrix cases and explicit safe
resolution of unobserved journal outcomes remain open. Official SDK/subrepos unchanged; no
compatibility feature or release gate claimed. See [ADR 016](ADR/016-passkey-registration-incremental-identities.md).

### Explicit reviewed abandonment of unresolved registration tracking (2026-09-28)

The actual vault warning now offers a metadata-only review sheet with inspection/risk acknowledgment
and a destructive local-tracking action. Same-unlock and legacy-origin reviews cannot abandon.
New reservations bind the actually authorized originating unlock ID. Older optional-field-free v1
records still decode and reconcile when the exact credential is observed; no origin is guessed.

The live Data actor keeps one ephemeral review and its exact journal record; new review/sync
invalidates prior consent. The repository FIFO requires a fresh complete sync with current cache/
OS projection, no stale snapshot or unavailable items. CRUD/failed sync/lock invalidates readiness.
The store compares and removes only the exact reviewed record inside the shared authorization
transaction, requiring a known different originating unlock and preserving foreign records.
Acknowledgment submits a repository-owned local Task, never HTTP. UI cancellation after submission
does not skip its result; already-cancelled submissions do nothing and lock denies late publication.

| Actually executed final check | Result |
| --- | --- |
| Complete AppModulesArchitectureTests + AuthPresentationTests: 684 Swift-Testing methods, 85 suites | passed |
| Two existing AppModules XCTest filter tests | passed |
| unsigned macOS-arm64 app + AutoFill extension | passed |
| unsigned generic iOS-Simulator app + AutoFill extension | passed |

686 total; twenty-two new methods: three journal-store, seven recovery-service, six repository
pipeline and six model. Real temporary files/continuation gates verify fresh/same/legacy unlocks,
forged origins, exact compare/phase changes, foreign accounts, future schema/proof/runtime failure,
one-shot consent, partial/stale/cache/OS/CRUD guards, zero server writes, canceled submissions,
post-commit UI cancellation, lock, late prompts, duplicate taps and redacted errors. Existing
assertions remain. Initial tests exposed a concrete synchronous actor method being shadowed by
the protocol's negative async default; explicit async implementations fix dispatch. Tests were
kept and the final complete targets executed, not just compiled.

Final commands, workspace caches retained:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

No project graph/extension-file-list change; package sources are discovered automatically. No
actual review-sheet UI launch, SDK crypto/FFI smoke, real server, signed device/entitlement,
process kill/power-loss, cross-process OS ordering or Release build was executed. Fresh unlock
revokes old local authority but cannot recall HTTP already sent: a request may commit after
inspection/sync/abandonment. The explicit prompt accepts that uncertainty/duplicate risk and does
not recommend registration retry. Only local tracking is removed; no server data or passkey is
deleted. Legacy-origin markers remain blocked unless exact automatic reconciliation succeeds.
Atomic file replacement can precede a later reported storage failure; sync, not another HTTP write,
repairs ambiguous local acknowledgment. No server idempotency, rollback, audit ledger, compatibility
feature or release gate claimed. Official SDK/subrepos unchanged. See
[ADR 017](ADR/017-passkey-registration-reviewed-abandonment.md).

### Typed SDK callbacks and registration ports (2026-09-28)

The extension's raw SDK FIDO callbacks, creation JSON and cipher backing now belong to
BitwardenSDKAdapter. AutoFillData owns typed registration crypto/HTTP persistence and
whole-operation single-flight/receipt validation. PlatformServices supplies device-owner
verification via Domain. The Apple adapter composes those ports; it no longer imports BitwardenSdk
or declares a direct SDK product dependency. XcodeGen was rerun from project.yml. The upstream
SDK package and official subrepos are unchanged; no new compatibility flow introduced.

26 new methods, not 26 new features:

- Eight direct SDK callback methods cover decoded RP/ID/userHandle matching, duplicate/foreign/
  empty metadata, propagated decode failures, scoped owner/edit save, unambiguous authentication
  selection, exact creation RP and late verification cancellation/lock.
- Three request/delta contract methods check byte-preserving Base64URL/envelope/defaults,
  rejected invalid request and exactly one added decoded credential on the same eligible target.
- Four fake-platform-context methods check unavailable/no prompt, boolean/error mapping,
  repeated evaluation without cached success, cancelled submission and late success/error.
- Five typed persistence methods check reserve-before-create/update, originating unlock,
  stale cache/lock/cancellation after decrypt, invalid mutation, retained projection repair and
  mutation-owned projection after cancellation of the HTTP consumer.
- Six coordinator methods check missing receipt, exact result ID/nonempty attestation,
  FFI-wrapped write classification, whole-registration busy exclusion, pre/post-submit cancellation,
  post-confirmation failure and revocation. Confirmed markers survive denied output.

Complete executed AppModules targets: **710 Swift-Testing methods in 90 suites plus two XCTest
tests (712 total), all passed**. Existing tests/assertions retained. Parameter arguments do not
multiply this method count. Executed with TMPDIR=${TMPDIR:-/tmp}, the existing local scratch path,
native SwiftPM backend and --no-parallel; this is not a CI-backend change or a fresh SDK FFI smoke.
Both regenerated macOS arm64 and generic iOS Simulator app/extension builds passed unsigned,
using the existing derived-data paths and CODE_SIGNING_ALLOWED=NO.

These tests use explicit gates, synthetic SDK structs and direct Swift callback methods, not
real FIDO crypto/UniFFI invocation, server accounts, OS prompts/completion, UI launch, signed
devices/entitlements, process termination, power-loss or Release builds. Global app/extension
identity ordering, controller-context/error coverage, real creation response preservation and
the ADR 015–017 recovery limits remain open. No release gate or completed plan claimed.
See [ADR 018](ADR/018-autofill-sdk-callback-and-registration-ports.md).

### Shared app/extension OS-identity mutation ordering (2026-09-28)

Both live roots inject a Domain mutation-coordination port backed by the same stable App Group
file, .autofill-identities.lock. An FD-owned flock spans a whole async OS batch without holding
the grant/token NSLock. Contended acquisition uses nonblocking checks/cancellable async waits;
waiting timeout cannot expire an acquired lease. Missing/unsafe/unavailable coordination never
runs an unguarded OS mutation. App publisher checks live authorized cache revision before/after
replacement, compensates within the same batch, and checks current unlock before clearing.
Extension rechecks its cache receipt after acquisition and holds the batch through add/recheck/
targeted cleanup, preventing cleanup after a newer participating app publication.

18 new methods: seven real async file-lock, two pure owner/revision/unlock policy, five publisher
guard and four combined app/extension ordering methods. Independent descriptors and real temp
files verify exclusion over awaits, throwing release, cancellation while owner remains active,
waiting timeout without forced lease expiry, acquired consumer cancellation, 0600 permissions,
missing container and invalid/symlink/directory/FIFO files. Explicit contention probes and gates
verify add-cleanup-before-new-replace, lock clear after extension drain, stale app replacement
after incremental cache commit and stale incremental waiter before any OS call. New publisher
guards verify denied old-unlock clear, late/uncertain replacement cleanup and visible cleanup/
coordination failures. Existing fixtures explicitly inject a test-only coordinator, preserving
their assertions; there is no production process-only default.

Complete AppModules targets executed with the existing native SwiftPM scratch path, TMPDIR=
${TMPDIR:-/tmp} and --no-parallel: **728 Swift-Testing methods in 94 suites plus two XCTest tests
(730 total), all passed**. Parameter arguments are not multiplied into the method count.
XcodeGen regenerated the project. Both macOS-arm64 and generic iOS-Simulator app/extension
builds passed unsigned using the existing derived-data paths. Official SDK/subrepos unchanged.
No new compatibility behavior, credential schema or server endpoint was introduced.

The first new-test compiler run needed splitting actor-property assertions and evaluating a
throwing cache read outside the require macro; no production guards or assertions were weakened.
The ordering tests run separate descriptors in one process with fake OS callbacks, not actual
signed app/extension processes or ASCredentialIdentityStore. No server/FFI smoke, real OS prompts,
UI launch, signed devices/entitlements, process kill/power-loss or Release builds executed here.
Process death releases the FD but cannot recall work submitted to the OS daemon; old binaries
or other uncoordinated writers remain outside the batch contract. Missing container/coordination
can leave stale suggestions needing repair; grants still deny fulfilment. Cache/Keychain/journal/
HTTP/OS completion and returned health are not one durable transaction. X-604/V-403 and release
gates remain partial. See [ADR 019](ADR/019-shared-credential-identity-mutation-ordering.md).

### Live terminal context and typed cancellation/error policy (2026-09-28)

The controller now uses AutoFillData.AutoFillRequestCompletion for every password/TOTP/passkey
output and cancellation. A synchronous MainActor context port makes invocation/cancellation,
current access, capability/mandatory-field validation, one claim and immediate platform dispatch
one non-suspending sequence. Teardown follows dispatch only if the old invocation remains current.
The sole Apple adapter starts the callback APIs, not async convenience wrappers. Confirmed
registration checks its proof rather than its own obsolete original cache revision.

The error policy provides route-specific typed cancellation without generic error descriptions;
unsupported types no longer enter the password/assertion default. Unknown registration errors
disable the same Save action. Explicit LA userCancel is sticky through SDK callback wrapping or
returned output, rather than becoming preferred-verification=false. Confirmed/uncertain writer
states take priority and retain recovery even after typed verification cancellation.

Complete AppModules execution with native backend, TMPDIR=${TMPDIR:-/tmp}, --no-parallel and --quiet:
**749 Swift-Testing methods in 97 suites plus two XCTest tests = 751 total, passed**. 21 new methods
(10 terminal, 4 query/context, 4 policy, 2 SDK callback cancellation, 1 platform error mapping);
existing postcommit coverage adds verification cancellation after confirmation. Parameterized
arguments do not inflate counts. Both regenerated unsigned macOS-arm64 and generic iOS-Simulator
app/extension builds passed. Existing assertions preserved; official SDK/subrepos unchanged.

Fake contexts exercise the actual live terminal component; real CredentialQuery compositions
use explicit decrypt gates and synthetic SDK views. Tests cover exactly-once all output/cancel
kinds, stale IDs, lease denial, task cancellation, unsupported/malformed output, reentrant context,
selected-only failure and lock before fill. Fake verification ports cover exact error-domain
mapping and sticky typed cancellation. No actual Apple controller/UI/context, biometric prompt,
FIDO crypto/FFI callback, server/signed-device/Release/process-kill/power-loss run was executed.
TOTP is generated after selection, but the SDK code-only adapter still discards its period; this
does not test an expiry boundary. Final grant check and OS acceptance are not atomic, and issued
credentials cannot be recalled. X-602/X-603/X-604 and prior release/recovery gates remain partial.
Next bounded step: preserve TOTP timing metadata and test generation/dispatch at period rollover
with an injected clock, without adding picker secret state. See [ADR 020](ADR/020-autofill-terminal-context-and-error-policy.md).

### AutoFill TOTP timing fence (2026-09-28)

Domain.TimeBasedOneTimeCode preserves SDK period and explicit generation date through the live
query and terminal context. The SDK receives that exact date; validity uses epoch-aligned buckets
and denies backward clock jumps. One bounded regeneration may repair local generation rollover;
expiry after query/final access checking cancels before claim, never fills old code. Seven new
methods with an injected clock cover this without sleeps. Complete targets: **756 Swift-Testing
methods/98 suites + 2 XCTest = 758 passed**, both regenerated unsigned app/extension builds passed.
No actual FFI crypto vectors or signed OS completion/acceptance; those gates remain open.
See [ADR 021](ADR/021-autofill-totp-expiry-boundary.md).

## 2. Weitere Unit-/Composition-Abdeckung und reale Race-Matrix

### Auth-Cleanup, Strict Concurrency und Format (2026-09-28)

Die neuen `AuthCleanupRecoveryTests` prüfen 11 Methoden mit synthetischen Keychain-Stores und
`.processOnly`-Lock: deny über Store-/Repository-Recreation, Checkpoint-Replay, korrupte/future
Marker, fehlgeschlagene Reads/Writes/Removes, unabhängiger Widerruf, Erhalt neuerer Rotation und
kein Löschen der Nachfolgesession. Kein echter Prozessneustart/Keychain-Daemon-/Power-loss-Nachweis.
`ServerDateConcurrencyTests` prüft den NSLock-geschützten Formatter mit 100 parallelen Tasks.
Shared static nicht-Sendable Formatter wurden entfernt; Apple-Request-/NSApp-Grenzen explizit
MainActor-isoliert; Hotkey-Deinit überträgt keine opaken Any-Tokens zwischen Executoren.

Tatsächlich ausgeführt:

```sh
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/AppModules \
  --scratch-path .build/appmodules-refactor-tests --build-system native --no-parallel --quiet
env TMPDIR=${TMPDIR:-/tmp} swift test --package-path Packages/VaultwardenSDK \
  --scratch-path .build/sdk-release-tests --build-system native --quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/auth-observation-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/auth-observation-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
bash Scripts/swiftformat.sh --lint
```

**768 Swift-Testing/100 Suites + 2 XCTest = 770 AppModules-Tests bestanden**, dazu **1 echter
SDK-FFI-Smoke** (771 über beide Packages). Eigene Package-/App-/Extension-Targets: Strict
Concurrency complete und Warnungen als Fehler, Swift-5-Sprachmodus. Upstream-Warning-Policy
unverändert. Globale `-warnings-as-errors` wären mit dem SDK-Flag `-suppress-warnings` unvereinbar;
deshalb eigene Targets statt generierte Bindings verschärft.

Nach mechanischer Formatierung bestanden die Pakete; beide App-Builds fanden zusätzlich zwei
entfernte `self` in OSLog-Autoclosures. Explizites `self` wiederhergestellt und über `--selfrequired`
in der Formatter-Konfiguration geschützt; erneute macOS-/iOS-Debug-Builds bestanden. Lint:
0/345 Dateien zu formatieren. Kein OS-/UI-/Server-/Signed-Gate daraus ableiten. ADR 022.

Die Liste ist keine pauschal abgeschlossene Matrix. Einzelne Grenzen sind bereits durch die
oben genannten Fixtures geprüft; Mehrfenster-, Prozess-, OS- und echte Dateifehler-/Recovery-
Kombinationen müssen noch separat charakterisiert werden. Gated Fakes benötigen explizite
Freigabe, keine zeitabhängigen Sleeps. Für jede noch fehlende Kombination einen benannten Test
oder einen protokollierten manuellen Lauf ergänzen:

1. Observer erhält initialen Stand; mehrere Fenster sehen dieselbe Revision nach CRUD.
2. Zwei Sync-Consumer → ein Request; Cancellation eines Consumers stoppt den anderen nicht.
3. Sync/Save/Delete/Attachment-Mutationen laufen FIFO; stale Drafts und Permissions-Änderungen
   verhindern Server-Writes. Doppel-Save erzeugt keinen zweiten Request.
4. Erfolgreicher Server-Write mit nachfolgendem Decode-/Decrypt-/Snapshotfehler: committed-error,
   kein retrybarer Create-Draft, stale State, Cache/Identitäten ungültig bis Sync.
   Zusätzlich nur den UI-Consumer während eines erfolgreichen Create/Delete abbrechen: der
   Repository-Commit/Cache-Write endet trotzdem, und der gleiche Create-Draft ist nicht retrybar.
5. Lock während Fetch/Encrypt/HTTP/Projection/OS-Store: sofort leerer UI-Stand, keine späte
   Veröffentlichung. Zwei Cleanup-Aufrufer warten beide auf denselben Abschluss.
6. Identity-Replacement blockieren, Lock starten, Replacement freigeben: abschließender OS-Call
   entfernt alles. Routine-Clear erlaubt nachfolgende erfolgreiche Veröffentlichung.
7. Encoding/Datei-Replace/Datei-Remove/OS-Clear schlägt fehl: Warnung ohne doppelte Servermutation;
   bei Remove-Failure Shared-Capability-Widerruf prüfen. Neuer Unlock bleibt unangetastet.
8. Zwei Accounts mit gleichem User-ID auf verschiedenen Servern: kein fremder Cache/Revision.
   Alte App-/Extension-Aufgaben verwenden niemals den neuen Unlock-Proof.
9. Extension-Upsert gegen neueren UUID-Cache oder Grant: wird verweigert. Monotone Revision,
   Overflow, beschädigtes Legacy-JSON, fehlende/alte Felder und OS-disabled prüfen.
10. Collection-hidePassword, unresolved/ambiguous Permissions, Re-Prompt und malformed Ciphers:
    keine erfüllbaren Cache-Records/System-Identitäten; lesbare übrige Einträge bleiben sichtbar.
11. TOTP-/Passkey-Ergebnisse nach Auswahl-/Revision-/Permissionswechsel verwerfen.
12. Editor-Dismiss/Reopen während `makeDraft` oder Save schließt/überschreibt keinen anderen Editor.
13. Download nach Navigation/Lock: kein Preview, temporäre Dateien entfernt; Cleanupfehler sichtbar.
    Original-importierte Datei bleibt unverändert. Cancellation und security-scoped Access prüfen.

## 3. Contract- und echte Server-Prüfungen (offen)

Stand 2026-09-29: Ein opt-in Live-Vertragstest für Login/TOTP, Handoff, Refresh, Cipher-CRUD/TOTP,
Attachment, Text-/Datei-Send und Passkey-Lesen liegt vor ([Runbook](IntegratedAcceptance.md)).
Er lief **nie** gegen einen Server; Status NOT RUN bis zur Owner-Freigabe von Instanz, Version
und synthetischem Account. Die folgenden Punkte bleiben entsprechend offen.

### Eigener Attachment-Dateitransport (2026-09-28)

Nach ADR 023: Multipart-Assembly mit 64-KiB-Chunks, file-upload/file-download, UInt64-Größen,
same-origin/reject-redirect unverändert. 14 neue Methoden (8 Multipart, 4 real-filesystem
Installer, 2 Source-HTTP-/late-policy). Bestehende Assertions erhalten und um tatsächlichen
File-Port-/Content-Length-/body-nil-Nachweis erweitert. Vollständiger gleicher AppModules-
Testbefehl wie oben: **782 Swift-Testing/102 Suites + 2 XCTest = 784 bestanden**. Beide unsigned
Debug-App-/Extension-Builds mit denselben Befehlen/DerivedDataPaths bestanden. Initiale Runs
fanden Test-UInt64-Cast, leere/Punkt-Namen und eine falsch platzierte Fixture-Property; korrigiert,
danach stabiler vollständiger Lauf. Keine ignorierten Testfailures.

Der Large-File-Test nutzt eine 16-MiB-Sparsefile und kleine Suffix-I/O, keine Whole-file Data-
Inspektion; er misst nicht den gesamten SDK-Heap. SDK-intern bleiben std::fs::read/eigene
Send-Data-Port-Grenzen, daher D-016/F-701/F-703 weiter teilweise. Keine Disk-full-/echte Server-
oder signierte UI-/Lifecycle-Matrix damit bestanden.

Zusätzlich tatsächlich ausgeführte **unsigned Release-Builds, beide erfolgreich**, nach finalem
Attachment-Code. App-/Extension-Code behandelt eigene Swift-/C-Warnungen als Fehler. Kein Archive,
Codesign oder Notarization ausgeführt:

```sh
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenMac -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/source-release-macos \
  CODE_SIGNING_ALLOWED=NO build -quiet
xcodebuild -project VaultwardenMac.xcodeproj -scheme VaultwardenIOS -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/source-release-ios \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

- Bestehende Typen Login/Card/Identity/Note/SSH lesen, bearbeiten, erstellen und löschen.
- Custom Fields, History, URI-Match/Checksum, Attachment-Metadaten und Passkeys bleiben erhalten.
- Organisationen/Collections, gemischte malformed Items und erneuter Sync nach Teilfehler.
- Attachment upload/download/delete gegen den für das Release festgelegten Serverstand.
- 401/invalid_grant vs. Offline/Timeout/429/5xx: nur fataler Authfehler beendet die Sitzung.
- Konfliktmarker für Cipher-Updates (`lastKnownRevisionDate`) ist implementiert und mit
  synthetischem Vaultwarden 1.37.5 geprüft: ein mehr als eine Sekunde veralteter Write wurde
  abgelehnt. Die erste Reproduktion und die Korrektur sind unter F-35 dokumentiert. Die kurze
  Server-Toleranz, andere Serverversionen und sichtbare UI-Recovery bleiben offen; keine
  konfliktfreie Zusammenführung behaupten.

## 4. Signierte macOS-/iOS-Prüfungen (offen)

- App Group/Keychain/AutoFill aktiviert und deaktiviert, kein Container, gesperrtes Gerät.
- App und Extension gleichzeitig: Refresh, App-CRUD, Passkey-Upsert, Lock und neuer Unlock.
- QuickType nach Create/Rename/URI-Change/Delete; Cache-Fehler und OS-Store-Fehler sichtbar.
- Mehrere macOS-Fenster/iPad-Szenen; vorhandene Clipboard-/Timeout-/Preview-Sicherheitsregeln.
- App-Abbruch zwischen temp/fsync/replace und Lock; Neustart-Cleanup und Recovery prüfen.

Weitere Ergebnisse einzeln mit Plattform/Serverstand und bestanden/fehlgeschlagen dokumentieren.
Erst danach die entsprechenden Plan-Gates abhaken. Die grünen lokalen Tests schließen weder
die Extension-Migration noch Streaming, echte Prozess-/Geräteprüfungen oder Release-Gates ab.

## 5. Nativer Vaultwarden-Serververtrag (2026-11-03)

Auf die Erlaubnis, selbst eine Testinstanz aufzusetzen, wurde eine kurzlebige lokale Docker-
Instanz mit synthetischem Account und vorbereitetem Passkey-Cipher verwendet. Image:
`ghcr.io/dani-garcia/vaultwarden:1.37.5`, Digest
`sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f`. Keine Produktions-
Adresse oder Produktions-Credentials wurden verwendet. Der gefilterte `LiveServerContractTests`-
Lauf endete mit `SERVER CONTRACT: all stages passed`: Login/Handoff, Refresh, Sync/Passkey-Read,
Cipher-Create/Update/TOTP/Delete, Attachment-Upload/Download/Delete und Text-/File-Send-
Create/Update/Delete. Fünf Tests in der Suite bestanden. Der Login erforderte keine TOTP-Challenge;
Login-TOTP ist daher **nicht ausgeübt**, nicht bestanden. Device Revocation und die übrigen F-13-
Grenzen bleiben offen.

Der Live-Lauf fand Server-Vertragsabweichungen, die danach in DTO-/Payload-/Transportcode behoben
und durch Regressionstests festgehalten wurden:

- Cipher-Writes an 1.37.5 benötigen `encryptedFor`; vorhandene Responses können es zurückgeben.
  Der AutoFill-Registrierungspfad reicht dafür die User-ID der verifizierten Extension-Session
  weiter.
- Vaultwarden 1.37.5 spiegelt die erste Login-URI als `login.uri` und liefert optionale Typfelder
  `bankAccount`, `driversLicense` und `passport` als `null`; nur diese konkreten sicheren Formen
  werden toleriert.
- Die v2-Attachment-Uploadantwort enthält eine root-relative URL. Der Client erhält beim Auflösen
  sowohl `/api` als auch einen vorhandenen Reverse-Proxy-Prefix.
- Encrypted File-Send-Namen können `/` enthalten; der Multipart-Builder bewahrt diese Bytes im
  Send-Pfad. Nutzernamen für gewöhnliche Attachment-Uploads werden weiter bereinigt.

Primärquellen für den getesteten Serverstand: [Vaultwarden v1.37.5 Cipher API](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/api/core/ciphers.rs),
[Cipher-Modell](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/db/models/cipher.rs).
Die temporären Container, das Netzwerk, synthetische Daten/Credentials und rohe Live-Testlogs
wurden nach dem Lauf entfernt. Dieser Lauf ist kein Nachweis für die Version
oder Kompatibilität der Produktionsinstanz und ersetzt weder den ausstehenden Owner-Smoke-Test
noch Geräte-/OS-Abnahmen.

## 6. Abschließende lokale Quell- und Plattformprüfung (2026-11-03)

Nach den Server-Fixes und dem AutoFill-Registrierungsaufruf mit verifizierter Session-User-ID:

- `bash Scripts/test-packages.sh`: Exit 0. VaultwardenSDK-Smoke 1; AuthPresentation 69 Tests/9
  Suites; AppModulesArchitecture 830 Tests/100 Suites plus 2 XCTest; alle bestanden.
- `bash Scripts/build-unsigned.sh Debug` und `Release`: jeweils Exit 0; macOS-App und generischer
  iOS-Simulator samt Extensions in beiden Konfigurationen gebaut. Diese Builds sind unsigniert.
- `bash Scripts/test-integration.sh`: Exit 0; macOS 17/17 und iOS-Simulator 17/17, jeweils ohne
  Fehler oder Skips. Der Runner-Live-Serverfall war bei diesem Aufruf mangels `VW_TEST_*`-
  Variablen NOT RUN; der getrennte lokale Live-Serverlauf ist in Abschnitt 5 dokumentiert.
- `bash Scripts/swiftformat.sh --lint`: Exit 0, 0/366 Dateien zu formatieren.
- `swift Scripts/check-source-secrets.swift`: 481 getrackte, nicht ignorierte Textdateien geprüft, keine
  erkannten Muster. `bash Scripts/test-source-secrets.sh` verweigerte die synthetischen
  Negativfälle ohne Inhaltsausgabe.
- `swift Scripts/check-source-materials.swift`: 29 Drittmaterial-Dateien samt Hashes verifiziert;
  keine privaten/generierten Artefakte im getrackten Quellbestand.
- Markdown-Ziellinks auf lokale Dateien aufgelöst; `git diff --check` sauber.

Kein signierter Build, echtes Gerät, ExtensionContext/QuickType, Provisioning, Notarisierung,
Remote-CI oder Produktionskonto wurde in dieser Verifikation verwendet.
