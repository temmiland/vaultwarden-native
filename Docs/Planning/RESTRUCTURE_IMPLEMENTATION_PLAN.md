# Restructure-, Hardening- und Release-Plan

> Eingefrorene Umsetzungsspezifikation und datierte Implementierungshistorie.
> Die einzige aktuelle Arbeitscheckliste ist [RemainingReleaseWork.md](../RemainingReleaseWork.md).
> Alte Status-/Resttabellen unterhalb sind Historie; vor erneuter Umsetzung dort abgleichen.

## 1. Auftrag und verbindlicher Scope

Dieses Dokument ist die eingefrorene Umsetzungsspezifikation für den Umbau des Projekts.
Die konsolidierten Befunde und aktuellen Restarbeiten stehen in
[RemainingReleaseWork.md](../RemainingReleaseWork.md). Bei einem Widerspruch
gilt folgende Priorität:

1. Sicherheits- und Datenintegrität
2. der in diesem Dokument eingefrorene Release-Scope
3. aktuelle Befunde in `Docs/RemainingReleaseWork.md`
4. bestehende Implementierungsdetails

Ziel ist ein veröffentlichbares, klar als Lernprojekt gekennzeichnetes Universal-App-Projekt für
macOS, iOS und iPadOS. Es soll die **bereits vorhandenen** Funktionen zuverlässig, sicher und
architektonisch sauber ausführen. Es werden keine neuen Vaultwarden-/Bitwarden-Funktionen mehr
entwickelt.

### 1.1 Was „keine neuen Funktionen“ bedeutet

Nicht mehr implementieren:

- weitere 2FA-Verfahren neben dem bereits vorhandenen TOTP-Verfahren,
- neue Cipher-Typen oder Editoren für bisher nicht editierbare Typen,
- Custom-Field-, Folder-, Collection-, Trash-, Restore- oder Archive-Verwaltung,
- Multi-Account,
- Offline-Vault für die Haupt-App,
- Background Sync,
- AutoFill-„Passwort speichern“,
- PIN-/Biometrie-Unlock innerhalb der Extension,
- Admin Console, Provider Portal, Reports, Watchtower oder Organisationsverwaltung,
- zusätzliche Send-Varianten oder Vaultwarden-Endpunkte,
- neue Vaultwarden-Versionen oder Server-Sonderfälle ohne reproduzierten Fehler im Release-Scope.

Erlaubt und erforderlich sind dagegen Änderungen, die vorhandenes Verhalten korrekt, sicher und
benutzbar machen. Dazu gehören unter anderem manuelles Wiederholen/Refresh, verständliche
Fehlermeldungen, Accessibility, sichere Dateiübertragung, vollständige Tests sowie das Bewahren
nicht dargestellter Serverfelder.

### 1.2 Bereits vorhandene Funktionen werden nicht einfach aufgegeben

Folgende Bereiche bleiben im Polishing-Scope und ihre Defekte müssen behoben werden:

- Server Setup und Login,
- TOTP-Zwei-Faktor-Anmeldung,
- Token Refresh und Session Expiry,
- Entsperren per Master-Passwort, PIN und Biometrie,
- Vault Sync, Lesen, Suchen, Filtern und bestehende CRUD-Aktionen,
- Passwortgenerator und TOTP-Anzeige,
- Attachments,
- Text- und File-Sends,
- Vault Timeout, Lock und Logout,
- Geräteliste und Device Revocation,
- Password AutoFill, TOTP AutoFill und die bereits implementierten Passkey-Flows,
- macOS-Menüleiste, Quick-Access-Hotkey und Launch at Login.

Eine Ausnahme gilt für Cipher-Typen, für die nie ein vollständiger Editor existierte. Diese werden
sichtbar und lesbar gehalten, aber eindeutig als read-only behandelt. Sie bekommen keinen neuen
Editor. Das ist eine Sicherheitsgrenze gegen Datenverlust, kein Entfernen einer funktionierenden
Funktion.

## 2. Arbeitsregeln für Luna

Luna soll dieses Dokument nicht in einem einzigen großen Patch umsetzen.

1. Immer genau eine Task-ID oder ein ausdrücklich zusammen genanntes, kleines Task-Paket
   bearbeiten.
2. Vor jeder Task deren Voraussetzungen prüfen. Fehlt eine Voraussetzung, nicht improvisieren.
3. Vor Änderungen `git status --short` prüfen. Fremde Änderungen niemals zurücksetzen oder
   überschreiben.
4. Keine Dateien unter `Packages/VaultwardenSDK/Sources/BitwardenSdk/` manuell ändern. Sie sind
   generiert.
5. `Vaultwarden.xcodeproj` nicht manuell bearbeiten. Quelle ist `project.yml`; danach
   `./Scripts/generate-xcodeproj.sh` ausführen.
6. Keine neue Dependency ohne eine explizite Task in diesem Plan.
7. Keine neue API-Funktion, kein neuer Screen und kein neuer Vaultwarden-Endpunkt „bei der
   Gelegenheit“ ergänzen.
8. Öffentliche Typen nur hinzufügen, wenn eine echte Modulgrenze sie benötigt.
9. Sicherheitsrelevante Fehler nicht mit `try?` verschlucken. Bewusstes Best-Effort-Verhalten muss
   geloggt, getestet und im Code kommentiert werden.
10. Nach jeder Task nur die direkt relevanten Tests ausführen; am Ende jedes Meilensteins die volle
    Testmatrix ausführen.
11. Eine Task ist erst erledigt, wenn Code, Tests und Dokumentation derselben Änderung konsistent
    sind.
12. Falls ein bestehender Test der hier festgelegten Semantik widerspricht, den Test nicht einfach
    an das aktuelle Verhalten anpassen. Zuerst den Widerspruch berichten.

### 2.1 Format der Übergabe nach jeder Task

Luna berichtet immer:

```text
Task: <ID und Titel>
Geändert: <Dateien und Verhalten>
Tests: <exakte Befehle und Ergebnis>
Offen: <nichts oder konkrete Blocker>
Risiken: <nur neu entstandene oder verbleibende Risiken>
```

### 2.2 Stop-Bedingungen

Luna stoppt und fragt nach, wenn:

- eine Änderung einen neuen Vaultwarden-Endpunkt oder ein neues Server-Datenmodell benötigt,
- Lizenz, Distribution, Signing-Team oder App-Store-Strategie entschieden werden muss,
- eine Migration gespeicherte Keychain-Daten nicht verlustfrei lesen kann,
- ein Passkey nach Servererfolg lokal nicht sicher bestätigt werden kann,
- ein Fix einen vorhandenen, im Scope gelisteten Flow entfernen würde,
- ein Test nur mit echten Zugangsdaten ausführbar wäre,
- das generierte SDK oder `sdk-internal` verändert werden müsste.

### 2.3 Entscheidungen, die beim Owner bleiben

**Historische Owner-Freigaben (2026-09-28, Lizenzwahl später ersetzt):** O-02 = MIT für eigenen
Code. Am 2026-11-07 wurde dies auf GPL-3.0-only für eigene Dateien geändert; Fremdmaterial bleibt
unter seinen jeweiligen Upstream-Lizenzen. Erste Veröffentlichung = nur Quellcode als Lernprojekt,
keine signierten Apps/Binaries. Andere Upstream-Lizenzen bleiben separat; dies ist keine Prüfung
der GPL-Pflichten des gekoppelten Werks oder späterer App-Distribution. O-03/O-04/O-05 bleiben
für signierte Apps bzw. echte Server-Contracts offen. Siehe `Docs/RemainingReleaseWork.md`.

Diese Entscheidungen sind absichtlich nicht an Luna delegiert:

| Gate | Entscheidung | Spätestens benötigt |
| --- | --- | --- |
| O-01 | initialer Commit/Recovery-Branch des derzeit unversionierten Stands | vor R-001 |
| O-02 | Lizenz des eigenen Projektcodes | vor L-1101 |
| O-03 | macOS App Sandbox plus Store-Tauglichkeit oder notarized Direct Distribution | bei P-803 |
| O-04 | endgültige Bundle IDs, App Group, Signing Team und Zertifikate | vor Real-Device-Gate |
| O-05 | konkret unterstützte/gepinnte Vaultwarden-Testversion | vor T-1003 |

Luna darf Optionen mit Vor- und Nachteilen dokumentieren, aber keine dieser Entscheidungen durch
einen stillen Default vorwegnehmen.

## 3. Eingefrorene Produktmatrix

### 3.1 Für Release unterstützt

| Bereich | Unterstütztes Verhalten am Ende |
| --- | --- |
| Server | benutzerdefinierte HTTPS-Vaultwarden-URL; HTTP nur Loopback in Debug |
| Login | E-Mail, Master-Passwort, Prelogin/KDF, TOTP-2FA |
| Session | Refresh, eindeutige Offline-/temporär-/abgelaufen-Unterscheidung |
| Unlock | Master-Passwort, PIN mit Attempt Limit, Touch ID/Face ID/Passcode-Fallback |
| Vault | Sync, Liste, Suche, vorhandene Filter, Detailansicht |
| Bearbeiten | Login, Card, Identity, Secure Note und SSH Key gemäß bestehendem Editor |
| Read-only | alle synchronisierten, aber nicht vollständig editierbaren Cipher-Typen |
| Mutationen | Create, Update und Delete für tatsächlich unterstützte Typen |
| Secrets | Passwort kopieren, TOTP erzeugen/kopieren, lokaler Passwortgenerator |
| Attachments | bestehendes Upload-, Download-, Preview- und Delete-Verhalten, gehärtet |
| Sends | bestehende Text-/File-Send-Flows, gehärtet |
| Settings | PIN, Timeout, Lock, Logout, Web-Vault-Link, Devices/Revoke |
| AutoFill | Passwort, TOTP, QuickType/Identity Store, URI-Match-Modi |
| Passkeys | vorhandene Assertion und Registration, atomare Cache-Aktualisierung |
| macOS | Window, Settings Scene, MenuBarExtra, Quick Access, Launch at Login |
| iOS/iPadOS | adaptive Navigation, Privacy Shield, AutoFill Extension |

### 3.2 Explizit nicht unterstützt

Die README muss diese Liste später sichtbar ausweisen:

- Email-, Duo-, YubiKey- und WebAuthn-Login-2FA,
- neuer Account und Account Recovery,
- Multi-Account,
- vollständige Editoren für Bank Account, Driver's License, Passport und zukünftige Cipher-Typen,
- Bearbeiten von Custom Fields,
- Folder-/Collection-Verwaltung,
- Trash/Restore/Archive,
- Offline-Nutzung des Haupt-Vaults,
- Background Sync und Konfliktauflösung zwischen mehreren Clients,
- AutoFill „neues Passwort speichern“,
- Entsperren direkt in der AutoFill-Extension,
- Vaultwarden-Administration und Bitwarden-Premium-/Enterprise-Oberflächen.

Nicht unterstützte Serverdaten dürfen trotzdem niemals beim Anzeigen oder Bearbeiten unterstützter
Felder beschädigt werden.

## 4. Historischer Ausgangszustand und ursprüngliches Defektregister

Der folgende Zustand ist die historische Audit-Baseline vor dem Umbau; heutige Defektzuordnung: `Docs/RemainingReleaseWork.md`:

- Unsigned Builds für macOS und iOS Simulator funktionieren.
- 178 Package-Tests bestehen.
- alle vier `AppArchitecture`-Store-Tests schlagen fehl,
- AutoFill und Passkeys besitzen kaum echte Integrationsabdeckung,
- der Branch besitzt noch keinen initialen Commit; Projektdateien sind unversioniert,
- `LICENSE`, Third-Party-Notices, CI und Security Policy fehlen,
- das generierte SDK-Artefakt ist ungefähr 860 MB, der lokale SDK-Build ungefähr 7 GB.

### 4.1 Defektregister

Jeder Eintrag muss durch mindestens einen Regressionstest geschlossen werden.

| ID | Defekt | Erforderliches Ergebnis |
| --- | --- | --- |
| D-001 | `Store.state` wird verzögert aktualisiert | Action/Effect ist nach Rückkehr deterministisch sichtbar |
| D-002 | Cipher-Edit kann unsichtbare Felder löschen | unterstützte Typen roundtrip-sicher; andere read-only |
| D-003 | URI Match, Checksum und `autofillOnPageLoad` gehen beim Edit verloren | unveränderte Werte bleiben bitgenau erhalten |
| D-004 | App und Extension verwenden unterschiedliche OAuth Client IDs | eine zentrale, getestete Client-ID-Konstante |
| D-005 | rotierender Refresh Token kann zwischen App und Extension auseinanderlaufen | definierte autoritative Tokenquelle und Reconciliation |
| D-006 | 429/5xx werden wie endgültige Session-Ablehnung behandelt | nur `invalid_grant` beendet die Session |
| D-007 | AutoFill ignoriert Server-Match-Modi | vollständige Semantik für vorhandene Match-Modi |
| D-008 | kein AutoFill-Treffer zeigt wieder alle Credentials | bei konkreter Domain kein permissiver Fallback |
| D-009 | handgeschriebene Public-Suffix-Liste ist unvollständig | gebündelte, lizenzierte PSL und deterministische Tests |
| D-010 | Cache/Identity Store bleiben nach Mutation veraltet | jede Mutation aktualisiert Projektion atomar |
| D-011 | gelöschte Ciphers gelangen in AutoFill/Ansichten | zentral gefiltert und durch Tests gesichert |
| D-012 | Passkey-Registration ist direkt danach nicht sichtbar | Server-, Cache- und Identity-Revision stimmen überein |
| D-013 | Attachment-Bearer kann an fremden Host gehen | Token nur an erlaubte Origin, fremde URL abgewiesen |
| D-014 | serverseitige Dateinamen können Pfade beeinflussen | normalisierter reiner Dateiname oder sicherer Fallback |
| D-015 | entschlüsselte Temp-Dateien können liegen bleiben | zentral registriert; Cleanup bei Dismiss, Lock, Start |
| D-016 | Attachments/File Sends werden vollständig in RAM geladen | dateibasierte Upload-/Download-Pfade |
| D-017 | Release erlaubt unsicheres HTTP | Release nur HTTPS; Debug-Ausnahme nur Loopback |
| D-018 | Keychain `set` löscht vor erfolgreichem `add` | Update-in-place oder Add ohne Verlust des Altwerts |
| D-019 | wichtige Keychain-Fehler werden verschluckt | typisierte Fehler, sichere Recovery, Tests |
| D-020 | invalidierte Biometrie bleibt als aktiviert markiert | Enrollment zurücksetzen und verständlich neu anbieten |
| D-021 | macOS Sandbox/Distribution ist unentschieden | dokumentierte und getestete Release-Entscheidung |
| D-022 | Features bauen Live-Dependencies selbst | ausschließlich Composition Roots erzeugen Live-Graphen |
| D-023 | `SettingsFeature` importiert `AuthFeature` | keine Feature-zu-Feature-Abhängigkeit |
| D-024 | AutoFill importiert `VaultFeature` | versionierter `AutoFillContract` statt Feature-Import |
| D-025 | leere Processor-Defaults verschlucken Actions | Observation-Modelle oder exhaustives Reducer-System |
| D-026 | Root Views reichen Access Tokens weiter | Tokens bleiben vollständig im Data/Auth-Layer |
| D-027 | Persistenz-/Best-Effort-Fehler sind unsichtbar | privacy-sicheres Logging und modellierte Degradation |

## 5. Verbindliche Zielarchitektur

### 5.1 Migrationsstrategie

Kein Rewrite auf einer leeren Branch und kein gleichzeitiges Verschieben aller Dateien. Verwendet
wird eine Strangler-Migration:

1. aktuelles Verhalten durch Charakterisierungstests einfrieren,
2. unmittelbare Datenverlust-/Security-Defekte im Bestand schließen,
3. neue Modulgrenzen parallel anlegen,
4. genau einen vertikalen Flow nach dem anderen migrieren,
5. alte Typen erst löschen, wenn kein Produkt-Target sie mehr importiert,
6. Package-Manifeste erst am Ende konsolidieren.

Zu jedem Zeitpunkt sollen beide App-Schemes bauen. Temporäre Adapter sind erlaubt, müssen aber mit
`TODO(<Task-ID>)` markiert und in der angegebenen Cleanup-Task entfernt werden.

### 5.2 Ziel-Targets in `Packages/AppModules`

| Target | Aufgabe | Erlaubte direkte Dependencies |
| --- | --- | --- |
| `Domain` | IDs, Models, Fehler, Repository-/Client-Protokolle | Foundation |
| `Networking` | HTTP-Transport, Retry-Information, Datei-Transfers | Foundation/URLSession |
| `SecurityStorage` | Keychain, sichere Dateien, atomare Persistenz | Foundation, Security, LocalAuthentication |
| `AutoFillContract` | versioniertes App-Group-Austauschformat | Foundation |
| `BitwardenSDKAdapter` | Mapping und Krypto/SDK-Grenze | Domain, VaultwardenSDK |
| `Data` | Auth/Vault/Send-Repositories, Sync und Session Runtime | Domain, Networking, SecurityStorage, AutoFillContract, BitwardenSDKAdapter |
| `PlatformServices` | Clipboard, Biometrics, File Picker, Open URL, Identity Store | Domain plus Apple Frameworks |
| `SharedUI` | kleine gemeinsame SwiftUI-Komponenten und Styles | SwiftUI, Domain falls nötig |
| `AuthPresentation` | Auth-/Unlock-Presentation | Domain, SharedUI |
| `VaultPresentation` | Vault-Presentation | Domain, SharedUI |
| `SendPresentation` | Send-Presentation | Domain, SharedUI |
| `SettingsPresentation` | Settings-Presentation | Domain, SharedUI |
| `AppFeature` | Root Session State, Tabs und typed Navigation | Domain und Feature-Targets |
| `AutoFillData` | Cache lesen, Matchen, SDK-/Token-Zugriff der Extension | AutoFillContract, Networking, SecurityStorage, BitwardenSDKAdapter |
| `AutoFillFeature` | Extension UI und Request-Orchestrierung | Domain, AutoFillContract, AutoFillData, SharedUI |

`Packages/VaultwardenSDK` bleibt separat. Der generierte Swift-Wrapper und das XCFramework werden
nicht in `AppModules` kopiert.

Die vier UI-Targets heißen bewusst `*Presentation`, nicht `*Feature`: Während der Strangler-Migration
existieren gleichnamige Legacy-SwiftPM-Module bereits in eigenen Packages. SwiftPM erlaubt doppelte
Target-Namen im gemeinsamen Paketgraphen nicht; nach Entfernen der Legacy-Packages kann die
Namensgebung konsolidiert werden, falls sie dann noch Mehrwert hat.

### 5.3 Verbindliche Abhängigkeitsregeln

```text
iOS App ─┐
         ├─> App Composition ─> AppFeature/Features ─> Domain
macOS App┘          │
                    ├─> Data ─> Infrastructure/SDK Adapter ─> Domain
                    └─> PlatformServices ───────────────────> Domain

AutoFill Extension ─> Extension Composition ─> AutoFillFeature
                                  ├─> AutoFillData
                                  └─> AutoFillContract
```

Verboten:

- Feature A importiert Feature B,
- Feature importiert `Networking`, `SecurityStorage`, `BitwardenSdk`, AppKit oder UIKit,
- `Domain` importiert SwiftUI, URLSession, Keychain oder SDK,
- AutoFill importiert `VaultFeature`,
- `.live()` wird in einer View oder einem Feature-Model aufgerufen,
- Access-/Refresh-Tokens sind Teil eines View-Initializers oder UI-State-Modells.

### 5.4 Verbindliches State-Modell

Die bestehende generische `StateProcessor`-/`Store`-Hierarchie wird nach der Übergangsstabilisierung
entfernt.

- Jedes Feature hat ein `@MainActor @Observable final class <Feature>Model`.
- Der State besteht aus einfachen Values und typisierten Loading-/Error-Zuständen.
- Dependencies kommen vollständig über den Initializer.
- User-Aktionen sind benannte Methoden, keine überschreibbaren leeren Basismethoden.
- Nebenläufige Operationen werden in Tasks gehalten und bei Ersatz/Abbruch gecancelt.
- State wird ausschließlich auf dem Main Actor geändert.
- Repositories und mutable I/O-Komponenten sind Actors.
- Navigation nutzt typisierte Routen; Coordinator nur bei einem echten mehrstufigen Flow.

### 5.5 Session- und Datenmodell

`Domain.AccountSession` enthält nur nicht geheime Metadaten:

```swift
public struct AccountSession: Sendable, Equatable {
    public let accountID: AccountID
    public let email: String
    public let environment: ServerEnvironment
}
```

SDK `Client`, Tokens und entschlüsselte Schlüssel sind kein Domain-/UI-State. Im Data-Layer teilen
sich die Default-Repositories einen `SessionRuntime actor`:

```text
DefaultAuthRepository ─┐
DefaultVaultRepository ├─> SessionRuntime actor
DefaultSendRepository ─┘       ├─ SDK Client
                               ├─ Token Provider
                               └─ aktueller Account/Environment
```

Der Haupt-Vault bekommt im Rahmen dieses Projekts **keinen neuen Offline-Snapshot**. Autoritativ
ist während einer entsperrten Sitzung der in-memory Snapshot des `VaultRepository actor`. Die
bereits nötige AutoFill-Projektion bleibt verschlüsselt und separat.

### 5.6 AutoFill-Vertrag

Die App schreibt ein versioniertes Envelope in den App-Group-Container:

```swift
public struct AutoFillCacheEnvelope: Codable, Sendable {
    public let schemaVersion: Int
    public let accountID: String
    public let revision: UInt64
    public let generatedAt: Date
    public let encryptedLoginRecords: [EncryptedLoginRecord]
    public let encryptedOrganizationKeys: [String: String]
}
```

`EncryptedLoginRecord` enthält ID, Deleted-Metadaten und den für die SDK-Entschlüsselung nötigen
verschlüsselten Payload, aber keine entschlüsselten Secrets. Das Schema wird atomar geschrieben.
Die Extension unterstützt genau die aktuelle und unmittelbar vorherige Schema-Version, damit ein
App-Update nicht in einem laufenden Extension-Prozess scheitert.

## 6. Test- und Build-Kommandos

Die tatsächlichen Scheme-Namen bleiben `VaultwardenMac` und `VaultwardenIOS`, bis eine eigene Task
sie ändert.

### 6.1 Schnelle Package-Tests

Vor der Konsolidierung:

```sh
(cd Packages/AppArchitecture && swift test)
(cd Packages/NetworkingKit && swift test)
(cd Packages/VaultCore && swift test)
(cd Packages/AuthFeature && swift test)
(cd Packages/VaultFeature && swift test)
(cd Packages/SendFeature && swift test)
(cd Packages/SettingsFeature && swift test)
(cd Packages/VaultwardenSDK && swift test)
```

Nach der Konsolidierung:

```sh
(cd Packages/AppModules && swift test)
(cd Packages/VaultwardenSDK && swift test)
```

### 6.2 Projekt generieren und unsigned bauen

```sh
./Scripts/generate-xcodeproj.sh

xcodebuild \
  -project Vaultwarden.xcodeproj \
  -scheme VaultwardenMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project Vaultwarden.xcodeproj \
  -scheme VaultwardenIOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Builds nacheinander ausführen. Der Audit hat bei einem parallelen macOS-Build bereits einen
transienten Header-Fehler gesehen.

## 7. Umsetzungsphasen und Tasks

Die Reihenfolge innerhalb einer Phase ist verbindlich, sofern `Abhängigkeiten` nichts anderes
erlaubt. Eine Phase endet mit einem grünen Quality Gate.

---

## Phase 0 – Repository absichern und Baseline reproduzierbar machen

### R-000 – Recovery-Punkt vor dem Umbau

**Verantwortlich:** Repository Owner, nicht autonom durch Luna.

**Ziel:** Der aktuelle Stand darf während des Umbaus nicht verloren gehen.

**Schritte:**

1. `.DS_Store` und lokale Logs aus dem Arbeitsbaum entfernen beziehungsweise ignoriert lassen.
2. Sicherstellen, dass `sdk-internal`, `.build` und das große XCFramework ignoriert bleiben.
3. Quellcode, `project.yml`, Scripts, Audit und diesen Plan in einen initialen privaten Commit
   aufnehmen.
4. Tag oder Branch `pre-restructure-baseline` anlegen.

**Done:** `git status --short` ist nach dem Commit leer; der Recovery-Punkt ist lokal vorhanden.

### R-001 – Baseline-Script anlegen

**Abhängigkeiten:** R-000

**Ziel:** Ein günstiges Modell kann mit einem Befehl denselben Zustand prüfen.

**Änderungen:**

- `Scripts/test-packages.sh`: führt alle aktuellen lokalen Package-Tests strikt sequenziell aus,
  bricht beim ersten Fehler ab und verändert keine Sources.
- `Scripts/build-unsigned.sh`: generiert das Projekt und baut beide Schemes sequenziell unsigned.
- Beide Scripts verwenden `set -euo pipefail`, bestimmen das Repository relativ zu ihrem eigenen
  Pfad und schreiben Derived Data in einen projektspezifischen temporären Ordner.
- README erhält zunächst nur einen kurzen Verweis auf die Scripts.

**Tests:** beide Scripts ausführen. Der Test-Script darf aktuell ausschließlich wegen D-001
fehlschlagen und muss das betroffene Package nennen.

**Done:** Build reproduzierbar; Testfehler präzise sichtbar; keine zufällige Parallelität.

### R-002 – Statusmatrix und Nicht-Ziele dokumentieren

**Abhängigkeiten:** R-000

**Ziel:** Während des Umbaus entsteht kein Feature Creep.

**Änderungen:**

- `Docs/FeatureStatus.md` aus Abschnitt 3 erzeugen.
- Spalten: Funktion, Status (`supported`, `read-only`, `not supported`), Plattform, Testart.
- In der README früh sichtbar auf diese Datei verlinken.
- „Not security audited“ und „do not use for irreplaceable production credentials“ klar nennen.

**Done:** Jede UI-Funktion lässt sich einer Zeile der Matrix zuordnen.

### R-003 – Charakterisierungstests vor Datei-Moves

**Abhängigkeiten:** R-001

**Ziel:** Vor dem Umbau kritisches aktuelles Verhalten absichern.

**Tests ergänzen:**

- Login Request Body inklusive Client ID und TOTP-Submission,
- Token Refresh mit rotiertem und nicht rotiertem Refresh Token,
- Lock versus Logout und betroffene Keychain-Einträge,
- Vault Sync Mapping für Login, Card, Identity, Secure Note, SSH und unbekannte Typen,
- Send List/Create/Update/Delete für Text und File,
- Attachment Create/Upload/Download/Delete,
- Timeout `.immediately`, Zeitwert und `.never`,
- AutoFill-Cache Encoding/Decoding ohne echtes Entitlement.

**Regel:** Tests dürfen fehlerhaftes Verhalten nur dann als erwarteten Failure markieren, wenn sie
D-001 bis D-027 referenzieren. Keine pauschalen Skip-Markierungen.

**Done:** Jede spätere Datei-Migration kann gegen eine bekannte Semantik geprüft werden.

### Quality Gate 0

- Beide unsigned App-Builds erfolgreich.
- Alle bekannten grünen Tests weiterhin grün.
- Die vier D-001-Tests sind der einzige bekannte rote Testblock.
- Feature-Scope ist dokumentiert.

---

## Phase 1 – Unmittelbare Datenverlust- und Security-Defekte schließen

Diese Fixes geschehen noch in der aktuellen Struktur, weil weitere Arbeit sonst auf einer unsicheren
Basis aufbaut. Regressionstests werden später mit in die neuen Targets verschoben.

### H-101 – Store deterministisch machen

**Deckt ab:** D-001

**Dateien:**

- `Packages/AppArchitecture/Sources/AppArchitecture/Store.swift`
- `Packages/AppArchitecture/Tests/AppArchitectureTests/StoreTests.swift`

**Umsetzung:**

- State-Weitergabe nicht erneut mit `DispatchQueue.main.async` verzögern.
- `send` und das abgeschlossene `perform` müssen den neuesten Processor-State sehen.
- Keine RunLoop-/Sleep-basierte Testlösung.
- Processor-Lifetime und Binding-Semantik beibehalten.

**Tests:** alle vier bestehenden Store-Tests plus ein Test für zwei direkt aufeinanderfolgende
Effects.

**Done:** `AppArchitecture` vollständig grün; keine „Publishing during view update“-Warnung im
App-Smoke-Test.

### H-102 – Editierbarkeit explizit begrenzen

**Deckt ab:** erster Teil von D-002

**Dateien:** Vault-State, `ItemDetailView`, Kontextmenüs und `ItemDraft`.

**Umsetzung:**

- Eine zentrale Funktion `EditCapability.for(cipher:)` einführen.
- Nur Typen mit vorhandenem, getesteten Editor liefern `.editable`.
- Bank Account, Driver's License, Passport, unbekannte/zukünftige Typen und `edit == false`
  liefern `.readOnly(reason:)`.
- Edit Buttons, Swipe Actions und Kontextmenüs verwenden ausschließlich diese Capability.
- Read-only Detailansicht bleibt verfügbar und erklärt knapp, dass der Typ in diesem Lernclient
  nicht sicher bearbeitet werden kann.

**Tests:** Capability Matrix für alle SDK-Cipher-Typen; UI-State testet, dass kein Edit-Sheet für
read-only geöffnet werden kann.

**Done:** Kein unvollständig unterstützter Cipher kann `ItemDraft.toCipherView` erreichen.

### H-103 – Verlustfreies Cipher-Roundtrip

**Deckt ab:** D-002, D-003

**Dateien:** `ItemDraft.swift`, DTO-/Test-Fixtures, `VaultProcessorTests`.

**Umsetzung:**

- `ItemDraft` bewahrt eine unveränderte Existing-Payload-Basis.
- Beim Speichern werden ausschließlich im Formular editierbare Felder ersetzt.
- Login bewahrt pro URI `match` und `uriChecksum`, `passwordRevisionDate`,
  `autofillOnPageLoad` und FIDO2 Credentials.
- Identity bewahrt Title, Middle Name, alle Address-Felder, Company, SSN, Passport- und
  License-Nummern.
- Gemeinsame Cipher-Felder wie Fields, Password History, Attachments, Reprompt, Permissions,
  Local Data, Organization/Collection IDs und Datumswerte bleiben erhalten.
- `revisionDate` darf aktualisiert werden; `creationDate` nicht.
- Wechsel des Cipher-Typs beim Editieren ist nicht erlaubt.

**Tests:** Fixture pro unterstütztem Typ mit gesetzten sichtbaren und unsichtbaren Feldern;
`draft -> edit one field -> CipherView` vergleicht alle nicht editierten Felder.

**Done:** Kein Fixture verliert ein Feld; Create-Fixtures bleiben servergültig.

### H-104 – Deleted-/Archived-Grenze zentralisieren

**Deckt ab:** D-011

**Umsetzung:**

- Eine zentrale `isVisibleInActiveVault`-/`isEligibleForAutoFill`-Policy definieren.
- `deletedDate != nil` immer aus aktivem Vault, Suche, Cache und Identity Store entfernen.
- Archivierte Einträge entsprechend dem eingefrorenen bestehenden UI-Verhalten behandeln; kein
  neuer Archive-Screen.
- Doppelte Filter aus Views entfernen.

**Tests:** aktive, gelöschte und archivierte Fixtures durch Sync, State, Cache und Identity Mapper.

**Done:** Gelöschte Daten erscheinen weder in der App noch in System-Suggestions.

### H-105 – Attachment-Origin sofort absichern

**Deckt ab:** D-013, D-014

**Dateien:** `AttachmentService.swift` und dessen Tests.

**Umsetzung:**

- Relative URLs weiterhin gegen `environment.apiURL` auflösen.
- Absolute URLs nur akzeptieren, wenn normalisierte Scheme/Host/Port-Origin exakt der erlaubten
  API-Origin entspricht.
- Vor Redirects verhindern, dass `Authorization` an eine andere Origin weitergereicht wird.
- Fremde Origin mit typisiertem Security-Fehler ablehnen.
- Server-Dateiname mit `lastPathComponent` normalisieren; leere, `.`, `..`, Slash, Backslash,
  Control Characters und NUL abweisen beziehungsweise durch eine lokale neutrale Anzeige ersetzen.
- Multipart Header darf keine unescaped Quotes/CRLF aus dem Dateinamen übernehmen.

**Tests:** relative URL, gleiche Origin, andere Subdomain, anderes Scheme, anderer Port,
Protocol-relative URL, CRLF-Dateiname und Traversal-Dateiname.

**Done:** Kein Bearer Token kann den konfigurierten Server verlassen.

### Quality Gate 1

- Alle aktuellen Package-Tests grün.
- Cipher-Roundtrip-Fixtures grün.
- Attachment-Origin-Tests grün.
- Beide Apps bauen unsigned.

---

## Phase 2 – Neue Modulgrenzen aufbauen

### A-201 – `AppModules`-Package als leeres Gerüst

**Abhängigkeiten:** Quality Gate 1

**Ziel:** Neue Grenzen schaffen, ohne alten Code sofort zu löschen.

**Umsetzung:**

- `Packages/AppModules/Package.swift` mit den Targets aus Abschnitt 5.2 anlegen.
- Deployment Targets bleiben macOS 14 und iOS 17, Swift Tools 5.10.
- Lokale Dependency auf `../VaultwardenSDK` nur im `BitwardenSDKAdapter` deklarieren.
- Für jedes Target einen passenden Test-Target anlegen.
- Zunächst nur Platzhalter-Dokumentationsdateien, keine duplizierte Business-Logik.
- `swift test` muss mit dem Gerüst grün sein.

**Done:** Target-Graph kompiliert und besitzt keine verbotene Rückkante.

### A-202 – Domain-Grundtypen migrieren

**Abhängigkeiten:** A-201

**Ziel:** Eigene, SDK-unabhängige Sprache der App.

**Neu in `Domain`:**

- typisierte `AccountID`, `CipherID`, `FolderID`, `CollectionID`, `SendID`, `AttachmentID`,
- `ServerEnvironment` mit normalisierten Base/API/Identity/Web-URLs,
- `AccountSession` ohne SDK Client und Token Closure,
- Domain-Modelle für die im Scope dargestellten Vault-/Send-Summaries und Details,
- `Loadable<Value>` oder äquivalenter typisierter Ladezustand,
- fachliche Fehler: `AuthenticationError`, `SessionError`, `VaultError`, `TransferError`,
- `Clock`-/UUID-Abstraktion nur dort, wo Tests deterministische Zeit/IDs benötigen.

**Regeln:**

- keine 1:1-Kopie sämtlicher Bitwarden-SDK-Typen,
- nur Felder modellieren, die UI/Use Cases benötigen; unbekannte Daten bleiben im Adapter/Data
  als erhaltener Payload,
- Secrets bekommen in Debug keine automatische `CustomStringConvertible`-Ausgabe.

**Tests:** URL-Normalisierung, ID-Gleichheit, Fehler-Mapping und `Sendable`-Kompilation.

**Done:** `Domain` importiert nur Foundation und kennt keinen FFI-Typ.

### A-203 – Repository- und Platform-Ports definieren

**Abhängigkeiten:** A-202

**In `Domain` definieren:**

```swift
public protocol AuthRepository: Sendable { /* login, submit TOTP, unlock, lock, logout */ }
public protocol VaultRepository: Sendable { /* observe/sync/create/update/delete/attachments */ }
public protocol SendRepository: Sendable { /* current Send flows */ }
public protocol SettingsRepository: Sendable { /* timeout, PIN, devices */ }
public protocol PasteboardClient: Sendable { /* copy secret with expiry */ }
public protocol BiometricClient: Sendable { /* availability and evaluation */ }
public protocol FileImportClient: Sendable { /* selected secured file URL */ }
public protocol OpenURLClient: Sendable { /* web vault */ }
```

**Semantik:**

- Repository-Protokolle drücken fachliche Resultate aus, keine HTTP-Statuscodes.
- Token und SDK Client kommen in keiner Signatur vor.
- Async Streams besitzen eine dokumentierte Cancellation-/Lifetime-Semantik.
- Keine Protokollmethode wird nur für einen einzelnen Mock erfunden.

**Done:** Feature-Targets können vollständig gegen diese Ports implementiert werden.

### A-204 – Networking migrieren und härten

**Abhängigkeiten:** A-201

**Ziel:** `NetworkingKit` in das neue `Networking` überführen.

**Umsetzung:**

- Bestehende Request-/Response-Typen migrieren.
- `HTTPStatusError` mit Status, Headern und begrenztem, redigiertem Diagnosebody.
- Transportfehler, Cancellation und HTTP-Fehler bleiben unterscheidbar.
- `URLSession` erhält ephemere, explizit konfigurierte Session Configuration; keine URLCache-
  Ablage sensibler Responses und kein Cookie Storage.
- Redirect Delegate entfernt `Authorization` bei Origin-Wechsel beziehungsweise lehnt den
  Redirect für authentifizierte Requests ab.
- Datei-APIs ergänzen: Download direkt in sichere Datei, Upload aus Datei.
- Retry wird nicht global automatisch ausgeführt. Repository entscheidet anhand idempotenter
  Operation und `Retry-After`.

**Tests:** Mock `URLProtocol` für Header, Cache Policy, Redirect, Cancellation, Datei-Upload und
Download; kein echter Netzwerkzugriff.

**Done:** Altes `NetworkingKit` hat nur noch einen temporären Adapter oder keine Consumer mehr.

### A-205 – SecurityStorage migrieren

**Abhängigkeiten:** A-201

**Deckt ab:** D-018, Teil von D-019

**Umsetzung:**

- `KeychainService` und Protection-Typen in `SecurityStorage` verschieben.
- Bis alle Legacy-Consumer migriert sind, `VaultCore.DefaultKeychainService` ausschließlich als
  markierten Übergangsadapter auf `SecurityStorage.KeychainStoring` belassen; keine zweite direkte
  `SecItem`-Implementierung pflegen.
- Bestehende Werte mit `SecItemUpdate` aktualisieren; bei `errSecItemNotFound` adden.
- Niemals den alten Wert löschen, bevor der neue sicher geschrieben ist.
- Reads unterscheiden `notFound`, `interactionCancelled`, `authenticationFailed`,
  `missingEntitlement`, `decodeFailed` und sonstigen OSStatus.
- Security-sensitive Stores geben `throws` zurück; UI entscheidet nicht anhand von `nil`, ob ein
  Wert fehlt oder beschädigt ist.
- `SensitiveTemporaryFileStore actor` hinzufügen: eindeutiges App-Präfix, Protection, registrierte
  Dateien, Cleanup bei Start/Lock/Logout und idempotentes Löschen.
- Unit Tests nutzen eine In-Memory-Implementierung; reale Keychain-Smokes bleiben separat.

**Tests:** Update erhält Altwert bei simuliertem Fehler, Add, Not Found, User Cancel, Biometrie
invalidiert, Temp Cleanup und fremde Temp-Dateien bleiben unberührt.

**Done:** Kein kritischer Keychain-Write folgt Delete-then-Add.

### A-206 – Bitwarden SDK Adapter einziehen

**Abhängigkeiten:** A-202

**Ziel:** Nur ein Target importiert das vendorte SDK für fachliche Operationen.

**Umsetzung:**

- bestehende Client-Erzeugung, Crypto-, Cipher-, Send-, TOTP- und FIDO2-Aufrufe in Adaptertypen
  verschieben,
- DTO -> SDK -> Domain Mapping zentralisieren,
- vorhandene rohe/verschlüsselte Payloads beim Edit erhalten,
- keine UI-Strings aus SDK-Fehlern direkt anzeigen,
- Adapterfehler in Domain-Fehler übersetzen und zugrunde liegenden Fehler nur privacy-sicher loggen,
- Fixture-basierte Contract-Tests für alle aktuell verwendeten Cipher-/Send-Typen übernehmen.

**Done:** Außer `BitwardenSDKAdapter`, der generierten SDK-Package selbst und technisch zwingendem
Extension-Bridge-Code importiert kein neuer Target `BitwardenSdk`.

### A-207 – AutoFillContract anlegen

**Abhängigkeiten:** A-201

**Deckt ab:** Teil von D-024

**Umsetzung:**

- Envelope und Record aus Abschnitt 5.6 implementieren,
- aktuelle Schema-Version als Konstante,
- Decoder für aktuelle und vorherige Version,
- unbekannte zukünftige Version liefert typisierten `unsupportedSchema`-Fehler,
- kein entschlüsseltes Passwort, TOTP-Seed oder privater Passkey im Codable-Graph,
- atomaren File Writer/Reader nicht hier, sondern in Data/AutoFillData implementieren.

**Tests:** Golden Files für aktuelle/vorherige Version, unbekannte Version, beschädigte Daten,
fehlende Datei und Secret-Leak-Snapshot.

**Done:** Contract ist Foundation-only und kann von App und Extension importiert werden.

### A-208 – PlatformServices definieren

**Abhängigkeiten:** A-203, A-205

**Umsetzung:**

- aktuelle Clipboard-Logik hinter `PasteboardClient`, inklusive local-only, concealed, Ablauf und
  `changeCount`-Guard,
- Biometrie hinter `BiometricClient`,
- Ermittlung des Gerätenamens hinter `DeviceNameClient`; der stabile Installations-Identifier bleibt
  Keychain-Verantwortung der Auth-Schicht,
- File Picker und security-scoped Resource Lifecycle hinter `FileImportClient`,
- Open URL hinter `OpenURLClient`,
- Credential Identity Store hinter einem injizierbaren `CredentialIdentityPublisher`,
- macOS Launch at Login und Hotkey bleiben App-Shell-Services, nicht Domain-Funktionen.

**Tests:** Fake Clients für Features; vorhandene Clipboard-Tests übernehmen; kein Feature-Test
importiert AppKit/UIKit.

**Done:** direkte Plattformaufrufe aus Processor/Feature-Models sind entfernt oder als klar
markierter Migrationsadapter erfasst.

### Quality Gate 2

- `AppModules` vollständig grün.
- Alte App baut weiterhin.
- Neue Core-Targets besitzen keine verbotenen Imports.
- Kein generierter SDK-Code wurde verändert.

---

## Phase 3 – Auth, Tokens, Session und Locking neu ordnen

### S-301 – Gemeinsame OAuth-Semantik

**Abhängigkeiten:** A-204

**Deckt ab:** D-004, D-006

**Umsetzung:**

- eine zentrale `OAuthClientConfiguration` im Data-Layer mit der aktuell funktionierenden Client
  ID `connector`,
- Password-, TOTP- und Refresh-Grant verwenden denselben Builder,
- Response klassifizieren in `success`, `twoFactorRequired`, `invalidCredentials`,
  `invalidGrant`, `rateLimited(retryAfter)`, `serverFailure`, `malformedResponse`,
- nur explizites `invalid_grant` beim Refresh beendet die Session,
- 401 ohne OAuth-Body, 429, 5xx, Timeout, Offline und TLS-Fehler behalten die Session und liefern
  einen retrybaren Fehler,
- Fehlertexte für Nutzer sind stabil und enthalten keine Response-Secrets.

**Tests:** Matrix aus Transport Error, Cancellation, 400 `invalid_grant`, 400 anderer OAuth Error,
401, 429 mit/ohne Retry-After, 500/503, malformed success und erfolgreicher Rotation.

**Done:** App und Extension besitzen keine unterschiedliche hardcodierte Client ID.

### S-302 – Autoritative Tokenablage und Reconciliation

**Abhängigkeiten:** A-205, S-301

**Deckt ab:** D-005, D-019

**Ziel:** App und Extension dürfen nach Token-Rotation nicht auseinanderlaufen.

**Semantik:**

- private App-Keychain-Ablage bleibt dauerhafte Quelle über Lock hinweg,
- Shared-Keychain-Ablage existiert ausschließlich während `unlocked`, weil die Extension sie für
  Passkey Registration benötigt,
- jeder Token-Datensatz trägt eine monotone `generation` und `updatedAt`,
- bei App-Aktivierung und vor jedem Refresh wird die neuere gültige Generation übernommen,
- Extension-Refresh schreibt atomar in Shared Store,
- Lock reconciled zuerst eine neuere Shared Generation zurück in Private und löscht danach Shared
  Key + Shared Tokens,
- Logout löscht Private und Shared vollständig,
- konkurrierende Refreshes werden in einem Actor dedupliziert,
- ein älteres Ergebnis darf niemals eine neuere Generation überschreiben.

**Dateien/Typen:** `TokenPair`, `PrivateTokenStore`, `SharedTokenStore`, `TokenCoordinator actor` in
Data/SecurityStorage; alte Store-Typen erhalten bis Cleanup Adapter.

**Tests:** App refresh, Extension refresh, Rotation, gleichzeitiger Refresh, App übernimmt Shared,
Lock nach Extension refresh, Logout, fehlgeschlagener persistenter Write und Generation Race.

**Done:** Es gibt genau eine dokumentierte Merge-Regel; kein Refresh Token geht durch Rotation
verloren.

### S-303 – SessionRuntime und DefaultAuthRepository

**Abhängigkeiten:** A-203, A-206, S-302

**Deckt ab:** D-026

**Umsetzung:**

- `SessionRuntime actor` besitzt SDK Client, Token Coordinator, Account und Unlock-Zustand,
- `DefaultAuthRepository` implementiert vorhandene Server Setup/Login/TOTP/Unlock-Flows,
- Erfolg gibt nur `AccountSession` an die Presentation zurück,
- andere Repositories holen autorisierte Runtime intern,
- Sessionzustand als Automat: `signedOut`, `locked(account)`, `unlocking(account)`,
  `unlocked(session)`, `expiring`,
- ungültige Transitionen sind Fehler und werden getestet,
- Session Expiry wird als Event/AsyncStream an `AppModel` geliefert,
- Access Token Closure aus `AuthenticatedSession` entfällt nach Consumer-Migration.

**Tests:** komplette State-Transition-Matrix, paralleles Unlock, Lock während Request, Logout,
invalid_grant Event und retrybarer Refresh.

**Done:** keine View erhält Client oder Access Token.

### S-304 – Biometrie-Recovery

**Abhängigkeiten:** A-205, S-303

**Deckt ab:** D-020

**Umsetzung:**

- User Cancel ist kein Enrollment-Verlust und führt ruhig zurück zur Unlock-Auswahl,
- invalidiertes/nicht mehr vorhandenes Gated Item setzt den persistenten Biometrie-Status zurück,
- Master-Passwort-Unlock bleibt erreichbar,
- nach erfolgreichem Master-Passwort-Unlock kann Biometrie erneut angeboten werden,
- Keychain-/LA-Fehler werden nicht alle als „wrong password“ angezeigt.

**Tests:** Erfolg, Cancel, Lockout, Biometry Changed, Item Missing, OS Error und Re-enrollment.

**Done:** App kann sich aus jeder Biometrie-Invalidierung ohne Löschen des Accounts erholen.

### S-305 – PIN-Hardening

**Abhängigkeiten:** S-303

**Umsetzung:**

- bestehendes Limit von fünf Fehlversuchen beibehalten,
- Counter-Write darf nicht still scheitern; bei nicht persistierbarem Counter PIN-Unlock sperren,
- Erfolg setzt Counter atomar zurück,
- parallele PIN-Versuche serialisieren,
- kein PIN oder abgeleiteter Schlüssel wird geloggt,
- Disable entfernt PIN-Key und Counter nachvollziehbar.

**Tests:** 0–5 Fehler, Write Failure, parallele Versuche, Erfolg nach Fehlern, Disable.

**Done:** PIN kann bei Persistenzfehler nicht unbegrenzt ausprobiert werden.

### S-306 – AppModel als einziger Session Owner

**Abhängigkeiten:** S-303

**Umsetzung:**

- `AppSessionStore` durch `@MainActor @Observable AppModel` im neuen `AppFeature` ersetzen,
- Timeout gehört weiterhin zum Session Owner, nicht zu einem Screen,
- AppModel reagiert auf AuthRepository-Session-Events,
- Root UI wechselt typisiert zwischen Auth, Locked und Main Content,
- Lock und Logout besitzen getrennte, getestete Semantik,
- bei Lock: laufende Secret-Tasks canceln, Sensitive Temp cleanup, Shared Credentials widerrufen,
- bei Logout zusätzlich Account-/Token-/Cache-/Identity-Daten löschen.

**Tests:** State Transitions, Timeout, Scene Phase, einmalige Events, doppelter Logout und Lock
während eines Feature-Requests.

**Done:** genau ein App-weites Objekt besitzt den sichtbaren Sessionzustand.

### Quality Gate 3

- Auth-/Session-Tests vollständig grün.
- 429/5xx loggen nicht aus.
- Rotation zwischen Extension-Simulation und App bleibt gültig.
- Lock sperrt AutoFill; Unlock stellt es wieder her; Logout entfernt alles.

---

## Phase 4 – VaultRepository, Sync und atomare Projektionen

### V-401 – DefaultVaultRepository als einzige Vault-API

**Abhängigkeiten:** A-206, S-303

**Ziel:** Eine einzige Wahrheit für Main-App-State und Mutationen.

**Umsetzung:**

- `DefaultVaultRepository actor` besitzt den aktuellen in-memory `VaultSnapshot`,
- `observeVault()` liefert initialen und folgende Snapshots in Revision-Reihenfolge,
- `sync`, `create`, `update`, `delete`, Attachment-Mutationen und Passkey-bedingte Mutationen laufen
  über dieses Repository,
- gleichzeitige Syncs werden dedupliziert; Cancellation eines View-Consumers bricht einen von
  anderen benötigten gemeinsamen Sync nicht unkontrolliert ab,
- Serverrevision gewinnt nur, wenn sie neuer als lokaler Stand ist,
- keine View patcht eigene Cipher-Arrays nach Serverantwort,
- Offline/Transportfehler behalten den letzten in-memory Snapshot, werden aber sichtbar als stale
  markiert; daraus entsteht kein neuer persistenter Offline-Modus.

**Tests:** initial leer, erfolgreicher Sync, paralleler Sync, Cancel, Mutation, Mutation Failure,
ältere Revision und Session Lock.

**Done:** `VaultProcessor.state.ciphers` ist nicht mehr zweite autoritative Wahrheit.

### V-402 – AutoFillProjectionWriter

**Abhängigkeiten:** A-207, V-401

**Deckt ab:** D-010, D-011

**Umsetzung:**

- aus jeder erfolgreichen Sync-/Mutation-Transaktion minimierte verschlüsselte Login-Records
  erzeugen,
- Deleted und nicht Login-relevante Records vor dem Schreiben filtern,
- temp file im selben App-Group-Verzeichnis schreiben, Protection setzen, fsync soweit sinnvoll,
  atomar ersetzen,
- Revision erst nach vollständigem Write erhöhen,
- Writer-Fehler machen die Servermutation nicht rückgängig, markieren Projektion aber als stale und
  zeigen eine reparierbare Warnung; bei Delete darf eine alte Projektion nicht weiter angeboten
  werden: betroffene Identity sofort entfernen und Cache notfalls sperren,
- Account ID validieren, damit Accountwechsel keinen fremden Cache zeigt.

**Tests:** atomarer Erfolg, Encoding Error, Replace Error, alte Revision, Accountwechsel, Deleted,
Crash-Simulation zwischen temp und rename.

**Done:** Cache ist stets eindeutig `current`, `stale` oder `unavailable`; niemals stillschweigend
scheinbar aktuell.

### V-403 – Credential Identity Publisher integrieren

**Abhängigkeiten:** A-208, V-402

**Deckt ab:** D-010, D-012

**Umsetzung:**

- Identity-Mapping als pure Funktion in Data/PlatformServices,
- Repository veröffentlicht Identitäten nach erfolgreicher Projektion derselben Revision,
- Create/Update/Delete/Passkey Registration aktualisieren die Identitäten sofort,
- bei Lock alle secret-erfüllbaren Identitäten entsprechend der gewählten UX entfernen oder als
  locked behandeln; Verhalten dokumentieren,
- Fehler des OS Stores werden geloggt und in Projection Health sichtbar, ohne Vault-Sync zu
  verlieren.

**Tests:** Password, TOTP, Passkey, Delete, Rename/URI-Change, leere Liste, disabled Store und
Publish Failure.

**Done:** Identity Store und Cache tragen dieselbe Revision.

### V-404 – URI Match Engine vollständig machen

**Abhängigkeiten:** A-207

**Deckt ab:** D-007, D-008, D-009

**Umsetzung:**

- reine `URIMatcher`-Komponente in `AutoFillData` oder Domain-nah, ohne UI,
- vorhandene Bitwarden-Match-Modi aus dem synchronisierten Datensatz abbilden: Domain,
  Host, Starts With, Exact, Regular Expression und Never,
- Standardmodus eindeutig definieren und aus Server-/Accountdaten übernehmen, soweit vorhanden,
- URL normalisieren: IDNA/punycode über Foundation-Verhalten testen, lowercase Host, Default Ports,
  IPv4/IPv6, trailing dot, bare domains,
- bei konkreten Service Identifiers liefert kein Treffer **keine** Credentials,
- nur bei leerer Identifier-Liste darf die manuelle vollständige Auswahl erscheinen,
- vollständige Public Suffix List als gebündelte Resource verwenden; Quelle, Version, Lizenz und
  reproduzierbares Update-Script dokumentieren,
- Regex mit sicherer Fehlerbehandlung und begrenzter Eingabelänge; ungültige Regex matcht nie.

**Tests:** jeder Match-Modus, PSL (`co.uk` und private suffix fixtures), Unicode Host, malicious
Subdomain, ports, paths, no-match, empty identifiers, invalid URL und invalid regex.

**Done:** kein sicherheitsrelevanter Fallback auf „zeige alles“ bei bekannter Website.

### V-405 – Vault Sync Error Model und manueller Retry

**Abhängigkeiten:** V-401

**Umsetzung:**

- UI unterscheidet initial loading, refreshing, content, stale content plus warning und fatal
  session expiry,
- bestehendes Laden beim Anzeigen bleibt,
- Nutzer kann einen fehlgeschlagenen/alten Sync manuell erneut anstoßen; dies ist Release-Polish,
  kein neuer Server-Flow,
- keine unendlichen automatischen Retry-Loops,
- letzter erfolgreicher Sync-Zeitpunkt sichtbar, ohne Serverzeit vorzutäuschen,
- Fehlermeldungen enthalten eine konkrete Recovery-Aktion.

**Tests:** initial success/failure, refresh while content, retry success, cancellation, session
expiry.

**Done:** ein temporärer Syncfehler erzeugt weder Logout noch leeren Vault.

### Quality Gate 4

- Vault Repository Tests grün.
- jede Mutation aktualisiert Snapshot, Cache und Identities konsistent.
- URI-Matrix grün.
- gelöschte Ciphers werden in keinem Consumer sichtbar.

---

## Phase 5 – Feature-Presentation auf Observation migrieren

Die Reihenfolge geht von einfach nach komplex. Nach jeder Migration wird das alte
Processor/Store-Paar dieses Features entfernt, nicht parallel weitergeführt.

### U-501 – SettingsFeature migrieren

**Abhängigkeiten:** S-306, A-208

**Umsetzung:**

- `SettingsProcessor` durch `SettingsModel` ersetzen,
- `SettingsFeature -> AuthFeature` entfernen,
- PIN über `SettingsRepository`/Auth-Port, Open URL über `OpenURLClient`, Devices über Repository,
- AppKit/UIKit-Imports aus Model entfernen,
- Device Revocation zeigt Confirmation, Busy State und klaren Fehler; doppeltes Submit verhindern,
- Timeout-Writes sind testbar und Fehler nicht still.

**Tests:** vorhandene Tests portieren; Fetch/Revoke, PIN, Timeout, Lock/Logout Actions, Open URL.

**Done:** SettingsFeature importiert nur erlaubte Targets.

### U-502 – SendFeature migrieren und stabilisieren

**Abhängigkeiten:** A-203, S-303

**Umsetzung:**

- `SendProcessor` durch `SendModel`, Services durch `SendRepository`,
- direkte `Data(contentsOf:)`-Dateipfade entfernen; Transferarbeit folgt F-701,
- entschlüsselte Details nicht per `try?` still leeren; per-item Fehler anzeigen,
- Create/Update/Delete und Auswahl werden vom Repository-Snapshot abgeleitet,
- laufende Load/Save/Delete Tasks cancelbar und gegen Doppelaktion geschützt,
- Copy-Feedback nutzt injizierten Clock statt ungebundenem Sleep.

**Tests:** alle bisherigen Send-Tests portieren plus Cancellation, Duplicate Submit, Decrypt Error
und Selection nach Delete.

**Done:** kein Store/Processor/Coordinator im SendFeature; Verhalten unverändert außer Fixes.

### U-503 – VaultFeature migrieren

**Abhängigkeiten:** V-401 bis V-405

**Umsetzung:**

- `VaultProcessor` durch `VaultModel`, State aus Repository-Snapshot,
- Filter/Search/Selection bleiben Presentation State,
- Edit-Sheet nutzt H-102/H-103 Capability und Draft,
- Save/Delete/Attachment/Generator/TOTP/Passkey Load über injizierte Ports,
- Selection nach Delete und Filterwechsel deterministisch,
- TOTP Timer wird bei Lock/Navigation beendet,
- Preview-Datei-Lifecycle über `SensitiveTemporaryFileStore`,
- Coordinator-Wrapper entfernen, falls nur ein Root Screen gebaut wird.

**Tests:** alte State-/Processor-Tests portieren plus Repository Revisions, Lock Cleanup, read-only
edit und Task Cancellation.

**Done:** VaultFeature kennt HTTP, SDK, Keychain und Token nicht.

### U-504 – AuthFeature migrieren

**Abhängigkeiten:** S-303 bis S-306

**Umsetzung:**

- Auth Coordinator darf als typed Flow Controller bestehen, aber baut keine Live Dependencies,
- Screen-Processor durch kleine Models oder ein `AuthFlowModel` mit typisierten Steps ersetzen,
- Server Setup, Login, TOTP, Unlock und Biometrie Enrollment exakt als Zustandsautomat,
- Zurücknavigation darf keine Secrets länger als nötig halten,
- Password/PIN-Felder nach Erfolg, Cancel oder Lock leeren,
- onAuthenticated Client/Token Callback durch AppModel-Sessionbeobachtung ersetzen,
- Fehlermeldungen aus Domain-Fehlern mappen.

**Tests:** jede Transition, Back/Retry, Double Submit, Cancel, Session Expired, Secret Clearing und
Biometrie Recovery.

**Done:** `AuthDependencies.live()` und statische `AuthSession`-Neuerzeugung sind entfernt.

### U-505 – Root UI und Universal Navigation

**Abhängigkeiten:** U-501 bis U-504

**Umsetzung:**

- `RootView` konsumiert `AppModel` und bereits zusammengesetzte Feature Factories,
- iPhone nutzt passende Stack-/Tab-Navigation,
- iPad/macOS nutzen verfügbare Breite und `NavigationSplitView`, ohne fixe iPhone-unfähige Minima,
- macOS Settings Scene teilt dasselbe AppModel,
- Menüleiste reagiert korrekt auf locked/unlocked,
- `#if os` auf App Shell und kleine View-Adapter begrenzen,
- Window Restoration darf keine Secrets in persistenten Scene-Werten halten,
- Privacy Shield auf allen iOS-Szenen testen.

**Tests:** View-Model/Route-Tests; UI-Smokes für iPhone SE-Größe, iPad Split View und veränderbares
macOS-Fenster.

**Done:** gemeinsame Features sind wirklich plattformneutral; Unterschiede liegen am Rand.

### U-506 – AppArchitecture entfernen

**Abhängigkeiten:** U-501 bis U-505

**Umsetzung:**

- sicherstellen, dass kein Source `Store`, `StateProcessor`, `Coordinator`-Basisklasse oder
  `AppArchitecture` importiert,
- Target und alte Tests entfernen,
- nur echte featurelokale Flow Coordinator ohne Basisklasse behalten,
- `project.yml` und Package-Abhängigkeiten aktualisieren.

**Done:** `rg 'import AppArchitecture|StateProcessor|Store<'` findet im Produktcode nichts.

### Quality Gate 5

- alle Feature-Tests grün,
- keine Feature-zu-Feature-Imports,
- keine Live Dependency in Views,
- keine Tokens/SDK Clients in View-Initializern,
- beide Universal-App-Builds grün.

---

## Phase 6 – AutoFill und Passkeys releasefähig machen

### X-601 – AutoFillData statt VaultFeature-Import

**Abhängigkeiten:** A-207, V-402, V-404

**Deckt ab:** D-024

**Umsetzung:**

- Cache Reader, URI Matcher und SDK-Decrypt-Adapter in `AutoFillData`,
- Extension importiert nicht mehr `VaultFeature`,
- `AutoFillVaultStore` in Actor-basierte Komponenten teilen: `ExtensionSession`, `CredentialQuery`,
  `PasskeyService`,
- Client pro Extension-Invocation cachen, aber bei Account-/Revisionwechsel invalidieren,
- individuelle Decrypt-Fehler zählen und privacy-sicher melden; beschädigte Einträge nicht als
  leere Credentials darstellen.

**Tests:** Cache open, schema migration, wrong account, locked, partial decrypt failure, matching.

**Done:** AutoFill-Zielgraph enthält kein VaultFeature.

### X-602 – Password- und TOTP-AutoFill korrekt abschließen

**Abhängigkeiten:** X-601

**Umsetzung:**

- konkrete Website ohne Treffer zeigt einen sicheren Empty State, nicht den gesamten Vault,
- manuell geöffnete Liste ohne Identifier darf alle geeigneten Logins zeigen,
- Suchfilter erfolgt lokal auf bereits entschlüsselten Anzeigeattributen und loggt keine Queries,
- Credential Request wird genau einmal completed oder cancelled,
- fehlendes Username/Password/TOTP erhält typisierten, verständlichen Fehler,
- Lock zwischen Auswahl und Completion führt zu Cancel, nicht zu Fill aus altem State,
- TOTP wird so spät wie möglich erzeugt.

**Tests:** Controller-Orchestrierung über abstrahierten Extension Context; exact once completion,
no match, lock race, TOTP expiry boundary.

**Done:** Passwort/TOTP können nie versehentlich für eine nicht matchende konkrete Domain angeboten
werden.

### X-603 – Passkey Assertion härten

**Abhängigkeiten:** X-601

**Umsetzung:**

- RP ID muss exakt zur Request-Semantik und gespeicherten Credential passen,
- nur den ausgewählten Cipher entschlüsseln,
- User Verification Cancel/Failure sauber an AS Extension Context melden,
- Client Data Hash, Credential ID und User Handle niemals loggen,
- parallele Requests nicht über einen globalen, accountübergreifenden Cache vermischen,
- genau einmal Completion.

**Tests:** richtige/falsche RP ID, unbekannte Credential ID, missing user handle, cancel, SDK error,
concurrent invocations.

**Done:** Assertion ist deterministisch, accountgebunden und privacy-sicher.

### X-604 – Passkey Registration atomar machen

**Abhängigkeiten:** S-302, V-402, V-403, X-601

**Deckt ab:** D-012

**Umsetzung:**

- Registration erst als erfolgreich an das System melden, wenn Servermutation bestätigt ist,
- bei bestehendem Cipher vollständigen unveränderten Payload bewahren,
- bei neuem Cipher nur bereits vorhandenen Registration-Flow verwenden; keine neuen Cipher-Typen,
- Shared Token Refresh über gemeinsamen TokenCoordinator-Vertrag,
- nach Servererfolg verschlüsselten Record, Cache-Revision und Credential Identity aktualisieren,
- kann die lokale Projektion nach Servererfolg nicht aktualisiert werden, Request nicht doppelt an
  Server senden; Recovery Marker mit Mutation ID schreiben und beim nächsten App-Start durch Sync
  reparieren,
- Nutzerfehler versus temporärer Fehler unterscheiden.

**Tests:** create/update, rotated token, server reject, timeout vor/nach Serverantwort, cache write
failure, identity failure, Recovery Marker und duplicate prevention.

**Done:** Es gibt keinen Zustand, in dem das System Erfolg meldet, der Passkey aber sicher nicht im
Server-Vault gespeichert wurde.

### X-605 – App/Extension Lock- und Upgrade-Matrix

**Abhängigkeiten:** X-602 bis X-604

**Umsetzung/Testfälle:**

- App unlocked / extension current,
- App lockt während offener Extension,
- App logout während offener Extension,
- App neue Cache-Version / alte laufende Extension,
- Extension rotiert Token / App wird aktiv,
- Gerät nach Boot noch gesperrt,
- App Account wechselt nach Logout,
- beschädigter Cache, fehlender Key, fehlendes Entitlement.

**Done:** Jeder Fall hat erwartetes Verhalten und automatisierten Test, soweit ohne Signierung
möglich; restliche Fälle stehen in der Real-Device-Checkliste.

### Quality Gate 6

- Extension importiert nur vorgesehene Targets.
- URI-/Password-/TOTP-/Passkey-Tests grün.
- App Group und Keychain Sharing auf signiertem iPhone/iPad und macOS manuell bestätigt.
- Lock/Logout verhindert anschließend Fill und Passkey-Operationen.

---

## Phase 7 – Dateiübertragungen und sensible temporäre Daten

### F-701 – Streaming-/dateibasierter Transfer

**Abhängigkeiten:** A-204, A-205

**Deckt ab:** D-016

**Umsetzung:**

- Attachments und File Sends nicht mehr mit `Data(contentsOf:)` komplett laden,
- Download über URLSession in temporäre verschlüsselte Datei,
- Upload via Datei; Multipart Body bei Bedarf als geschützte temporäre Datei aufbauen,
- Größenlimit aus bestehender Serverantwort respektieren; kein neues Quota Feature,
- Progress optional nur dort anzeigen, wo bestehende UI bereits Busy State hat; keine neue
  Transferverwaltung bauen,
- Cancellation beendet Netzwerk und löscht partielle Dateien,
- File Size mit 64-bit Werten behandeln.

**Tests:** kleine Datei, simulierte große Datei ohne entsprechend großen Heap, cancellation,
partial download, disk full/write error und HTTP failure.

**Done:** Peak Memory wächst nicht proportional zur Dateigröße.

### F-702 – Sichere Attachment Preview

**Abhängigkeiten:** F-701, A-205

**Deckt ab:** D-015

**Umsetzung:**

- Entschlüsselung nur in vom `SensitiveTemporaryFileStore` registriertes Verzeichnis,
- Dateirechte/Protection unmittelbar setzen,
- Quick Look erhält nur normalisierte lokale URL,
- Cleanup bei Preview Dismiss, nächster Preview, Lock, Logout, App Start und Prozessnormalende,
- Startup Cleanup löscht ausschließlich eigenes Präfix und begrenzt auf erwarteten Temp Root,
- Fehlerpfade löschen verschlüsselte und entschlüsselte Teilfiles.

**Tests:** normal, decrypt fail, preview cancel, lock, restart scavenging und fremde Datei bleibt.

**Done:** kein bekannter normaler Fehlerpfad hinterlässt entschlüsselte Datei.

### F-703 – File Send auf denselben Transferkern umstellen

**Abhängigkeiten:** F-701

**Umsetzung:**

- doppelten Datei-I/O-Code aus SendFeature entfernen,
- security-scoped URL exakt für die benötigte Dauer halten,
- Dateiname und MIME/Content-Disposition genauso härten wie Attachments,
- Cancel/Retry darf keinen doppelten Send erzeugen,
- entschlüsselte Download-Dateien folgen demselben Temp-/Export-Lifecycle.

**Tests:** bestehende File-Send-Flows plus große Datei, cancel, retry, malicious filename.

**Done:** Attachments und Sends teilen sichere Infrastruktur, nicht UI- oder Domainmodelle.

### Quality Gate 7

- Memory-/Cancellation-Tests grün.
- Lock/Logout räumt sensitive Temp-Dateien auf.
- Authorization verlässt nie erlaubte Origin.

---

## Phase 8 – Konfiguration, Plattform- und UI-Polish

### P-801 – `.xcconfig` und Bundle-Konfiguration

**Abhängigkeiten:** Quality Gate 5

**Umsetzung:**

- `Configuration/Base.xcconfig`, `Debug.xcconfig`, `Release.xcconfig` und
  `Local.example.xcconfig`,
- Team ID, Bundle ID Prefix, App Group und Keychain Group konfigurierbar,
- echte lokale `Local.xcconfig` ignorieren,
- hardcodierten Team-ID-Fallback aus `SharedAppGroup.swift` entfernen,
- App Start validiert App Group/Keychain-Konfiguration und liefert in Debug klare Diagnose,
- `project.yml` nutzt Settings aus xcconfig und enthält keine persönliche Team ID.

**Tests:** generiertes Projekt enthält erwartete expandierte Werte; fehlende Werte scheitern klar.

**Done:** ein Contributor muss keine Swift-Datei oder `project.yml` mit eigener Team ID ändern.

### P-802 – HTTP-Policy

**Abhängigkeiten:** A-202, A-204

**Deckt ab:** D-017

**Umsetzung:**

- Release akzeptiert ausschließlich HTTPS,
- Debug darf HTTP nur für `localhost`, `127.0.0.1` und `::1` mit sichtbarer Warnung akzeptieren,
- Credentials nie über HTTP an LAN-/Internet-Hosts senden,
- URL-Normalisierung verhindert Userinfo, Fragment und überraschende Port/Scheme-Wechsel,
- ATS-Ausnahmen nicht global lockern.

**Tests:** URL-/Build-Configuration-Matrix.

**Done:** Release kann keine Zugangsdaten über Klartexttransport senden.

### P-803 – macOS Sandbox und Quick Access

**Abhängigkeiten:** P-801

**Deckt ab:** D-021

**Zielentscheidung:** Die veröffentlichte Standardkonfiguration verwendet App Sandbox. Falls ein
signierter Real-Build beweist, dass der bestehende globale Hotkey damit nicht sicher realisierbar
ist, muss der Owner zwischen notarisiertem Direktvertrieb ohne Sandbox und Wegfall des globalen
Hotkeys entscheiden. Luna entscheidet das nicht selbst.

**Umsetzung vor Gate:**

- Sandbox aktivieren und Network Client/App Group/Keychain Entitlements minimal halten,
- aktuellen `NSEvent` Global Monitor auf Lebensdauer, Berechtigungsbedarf und Cleanup testen,
- wenn möglich, Hotkey durch eine sandbox-kompatible registrierte Shortcut-Implementierung ohne
  Aufzeichnung beliebiger Tasten ersetzen,
- Launch at Login mit ServiceManagement testen,
- Threat Model dokumentiert endgültige Distribution und Rest-Risiko.

**Done:** signierter macOS-Smoke für Window, AutoFill, Hotkey, Launch at Login und Files; Owner-
Entscheidung dokumentiert.

### P-804 – UX-Zustände und Fehlermeldungen vereinheitlichen

**Abhängigkeiten:** Feature-Migrationen

**Umsetzung:**

- einheitliche Loading, Empty, Error, Stale und Busy Components in SharedUI,
- keine technische Error Description direkt als einzige Nutzerbotschaft,
- Destructive Confirmations für Cipher/Attachment/Send/Device,
- Double Submit überall deaktivieren,
- sichere Fehlerdetails nur im privacy-sicheren Logger,
- Fokus, Keyboard Navigation und Escape/Cancel auf macOS,
- Dynamic Type, VoiceOver Labels, ausreichende Touch Targets und Kontrast auf iOS.

**Tests:** Model-State-Tests; Accessibility Inspector manuell für Kernflows.

**Done:** jeder Fehlerzustand bietet Retry, Cancel oder klare nächste Handlung.

### P-805 – Universal Layout Polish

**Abhängigkeiten:** U-505

**Umsetzung:**

- keine fixe Mindestbreite in gemeinsamen iOS-Views,
- iPhone Portrait/Landscape, iPad Split View und Stage Manager prüfen,
- macOS Fenster bei Minimum und großer Breite,
- Sheets/Popovers plattformgerecht,
- Settings Tab nur iOS/iPadOS, Settings Scene auf macOS,
- Toolbar-/Keyboard Commands für bestehende Aktionen, ohne neue Fachfunktion,
- sensible Inhalte in App Switcher/Screen Capture gemäß verfügbarer APIs schützen.

**Done:** visuelle Checkliste auf allen drei Formfaktoren ohne abgeschnittene Kernaktion.

### P-806 – Logging und Privacy

**Abhängigkeiten:** A-204 bis A-208

**Deckt ab:** D-027

**Umsetzung:**

- zentraler `AppLogger` mit Kategorien Auth, Network, Vault, AutoFill, Storage und UI,
- E-Mail, Serverpfad, Domain, Cipher-/Send-Namen, IDs, Tokens, TOTP, Passkey-Material und
  Dateinamen standardmäßig private oder gar nicht loggen,
- keine Response Bodies von Auth/Vault loggen,
- Best-Effort-Fehler mit Kategorie und nicht sensitiver Operation erfassbar,
- Debug-Logs der Extension bauen keine persistente Browsing History,
- Release enthält keinen Diagnose-Schalter, der Secrets offenlegt.

**Tests:** Logger-Sink in Tests prüft Redaction bekannter Canary-Secrets.

**Done:** Secret-Scan in Logs/Fixtures findet keine Laufzeit-Secrets.

### Quality Gate 8

- Debug und Release Configuration bauen.
- Layout-/Accessibility-Checkliste abgeschlossen.
- keine persönliche Team ID im Repository.
- endgültige macOS Sandbox-/Distribution-Entscheidung dokumentiert.

---

## Phase 9 – Package-Konsolidierung und Cleanup

### C-901 – Feature-Sources nach AppModules verschieben

**Abhängigkeiten:** Quality Gate 8

**Umsetzung:**

- migrierte Sources und Tests targetweise nach `Packages/AppModules` bewegen,
- nach jedem Target Package-Test und beide Apps bauen,
- Git Moves verwenden, soweit möglich, damit History nachvollziehbar bleibt,
- alte Package-Manifeste erst entfernen, wenn letzter Consumer umgestellt ist,
- TestSupport nur im jeweiligen Test-Target; keine produktiven Public Mocks.

**Reihenfolge:** Domain/Core -> Settings -> Send -> Vault -> Auth -> AppFeature -> AutoFill.

**Done:** `Packages/AppModules` enthält alle handgeschriebenen App-Module;
`Packages/VaultwardenSDK` bleibt separat.

### C-902 – project.yml vereinfachen

**Abhängigkeiten:** C-901

**Umsetzung:**

- nur noch `AppModules` und `VaultwardenSDK` als lokale Packages,
- App Targets importieren Composition/AppFeature-Produkte,
- Extension Targets importieren ausschließlich AutoFill-Produkte plus notwendige Adapter,
- unnötige direkte Dependencies entfernen,
- Projekt neu generieren; generiertes `.xcodeproj` bleibt ignoriert.

**Done:** `xcodebuild -list` zeigt beide Apps und Extensions korrekt; beide Builds grün.

### C-903 – Alte Module und Migrationsadapter löschen

**Abhängigkeiten:** C-902

**Umsetzung:**

- alte Verzeichnisse `AppArchitecture`, `NetworkingKit`, `VaultCore` und alte Feature-Packages nur
  löschen, wenn `rg` keine Consumer mehr findet,
- alle `TODO(<Task-ID>)`-Migrationsadapter abarbeiten,
- tote Coordinators, DTO-Duplikate, `.DS_Store` und alte generierte Logs entfernen,
- README Layout aktualisieren.

**Done:** keine doppelte Implementierung für Token, Cache, Cipher Mapping oder State Management.

### C-904 – Architekturregeln automatisieren

**Abhängigkeiten:** C-903

**Umsetzung:**

- SwiftLint `restricted_imports` oder kleines Repository-Script prüft verbotene Imports,
- CI prüft, dass Feature Targets kein AppKit/UIKit/BitwardenSdk/Networking/SecurityStorage
  importieren,
- CI prüft `.live()` außerhalb Composition Roots,
- ein Composition Test baut App- und Extension-Dependency-Graph mit Fakes.

**Done:** ein absichtlich verbotener Import lässt die Prüfung fehlschlagen.

### C-905 – Format-, Warning- und Concurrency-Policy

**Abhängigkeiten:** C-903

**Umsetzung:**

- vorhandene `.swiftformat` als einzige Formatquelle prüfen und auf finalen Source-Baum anwenden,
- verwendete SwiftFormat-Version in Setup und CI pinnen,
- Compiler-Warnings in CI als Fehler behandeln,
- Swift 5.10 beibehalten, aber vollständige Strict-Concurrency-Diagnostik aktivieren und alle
  projektinternen Warnungen beheben,
- keine pauschalen `@unchecked Sendable`-Marker; jede unvermeidbare Ausnahme braucht Kommentar,
  Synchronisationsmechanismus und Test,
- kein Swift-6-Sprachmodus-Upgrade in diesem Release; das wäre ein eigener späterer Scope.

**Done:** Format-Check, warnings-as-errors und Strict-Concurrency-Prüfung sind grün.

### Quality Gate 9

- nur zwei lokale Packages: AppModules und VaultwardenSDK.
- alle Tests und Builds grün.
- Importregeln automatisiert.
- Format-, Warning- und Concurrency-Policy grün.
- keine Migration-TODOs offen.

---

## Phase 10 – Vollständige Testpyramide und CI

### T-1001 – Unit-/Contract-Abdeckung schließen

**Abhängigkeiten:** Quality Gate 9

**Pflichtsuites:**

- Domain State Machines und Policies,
- HTTP/OAuth-Fehlermatrix,
- Keychain und Token Reconciliation,
- Cipher-/Send-Roundtrip-Fixtures,
- URI Match/PSL,
- Cache Schema/Atomic Write/Revision,
- Lock/Logout/Timeout,
- Attachment/File Transfer,
- AutoFill Password/TOTP/Passkey-Orchestrierung,
- alle Defekte D-001 bis D-027 mit Regressionstest oder dokumentiertem manuellen Gate.

**Done:** Defektregister enthält pro ID Link/Testname.

### T-1002 – App Composition und UI-Smokes

**Abhängigkeiten:** T-1001

**Umsetzung:**

- Launch Arguments wählen In-Memory-/Fixture-Dependencies, keine echten Credentials,
- Smokes: signed out -> setup, locked -> unlock, unlocked -> tabs, vault empty/content/error,
  create/edit/delete confirmation, settings lock/logout, sends,
- Screenshots enthalten nur synthetische Werte,
- iPhone und iPad Simulator sowie macOS.

**Done:** Kernnavigation und Dependency Graph laufen in CI ohne Vaultwarden-Server.

### T-1003 – Gepinnter Vaultwarden-Contract-Smoke

**Abhängigkeiten:** T-1001

**Scope:** Nur bereits unterstützte Flows testen; keine neue Kompatibilität bauen.

**Umsetzung:**

- dokumentierte, gepinnte Vaultwarden-Version in einer lokalen/CI-Testumgebung,
- eigener synthetischer Testaccount und nach Test löschbare Daten,
- Login/TOTP soweit automatisierbar, Sync, unterstützte Cipher CRUD, Attachment, Send, Device API,
- bei API-Drift Test rot und Befund dokumentieren; nicht automatisch neue API-Version nachbauen,
- Secrets nur aus CI Secret Store, niemals in Fixtures oder Logs.

**Done:** reproduzierbarer Smoke gegen genau die dokumentierte Serverversion.

### T-1004 – Signed Real-Device-Matrix

**Abhängigkeiten:** T-1002

**Manuell, vor jedem Release:**

- aktuelles unterstütztes iPhone/iPad: App Group, Shared Keychain, Password/TOTP AutoFill,
  Passkey Assertion/Registration, Face ID/Touch ID, Device Lock, App Switcher Shield,
- macOS 14+: Main App, Extension, Touch ID soweit verfügbar, Menu Bar, Hotkey, Launch at Login,
  File Picker/Preview, Lock/Logout,
- App Update über vorherigen Testbuild: Cache Schema und Keychain Migration,
- Netzwerk weg/kommt zurück, 429/5xx Simulation, Serverzertifikatfehler,
- große Attachment-/Send-Datei innerhalb vorhandener Servergrenzen.

**Done:** `Docs/RemainingReleaseWork.md` mit Datum, Gerät/OS und Ergebnis; keine Credentials.

### T-1005 – CI Workflow

**Abhängigkeiten:** T-1001, C-904

**Jobs:**

1. Format/Lint/Architecture Rules,
2. `swift test` AppModules,
3. SDK Smoke Tests mit vorbereitetem/verifiziertem Artefakt,
4. macOS unsigned Debug Build,
5. iOS Simulator unsigned Debug Build,
6. optional Contract Smoke nur geschützt/manuell,
7. Secret Scan und Dependency/License Report.

**Regeln:** keine Signing-Zertifikate im normalen PR-Job; Logs und Artifacts dürfen keine
Credentials enthalten; Caches anhand SDK-Revision und Patch-Hash schlüsseln.

**Done:** frischer Clone erreicht ohne lokale IDE-Schritte grüne nicht-signierte CI.

### Quality Gate 10

- Defektregister vollständig abgedeckt.
- CI grün.
- signierte Real-Device-Checkliste grün.
- gepinnter Vaultwarden-Smoke grün oder klar als manuelles Release-Gate dokumentiert.

---

## Phase 11 – Veröffentlichung und Projektpflege

### L-1101 – Lizenz- und Third-Party-Entscheidung

**Verantwortlich:** Owner entscheidet Lizenz; Luna sammelt und dokumentiert.

**Umsetzung:**

- eigene Projektlizenz als `LICENSE`,
- `THIRD_PARTY_NOTICES.md` für Bitwarden SDK/FFI, Public Suffix List und sonstige Dependencies,
- Lizenzkompatibilität des vendorten/gepatchten SDK vor Veröffentlichung prüfen,
- generierte Artefakte und Upstream-Quellen eindeutig kennzeichnen.

**Stop:** Luna darf keine Projektlizenz eigenmächtig auswählen.

**Done:** Repository und Release-Artefakt enthalten alle erforderlichen Notices.

### L-1102 – SDK-Build reproduzierbar und überprüfbar

**Umsetzung:**

- Upstream Revision, Rust Toolchain, Targets und Patch-Hash im Script fixieren,
- Download-/Checkout-Zustand verifizieren,
- Build-Ausgabe in temporäre/build-spezifische Pfade,
- SHA-256 des XCFramework dokumentieren,
- entweder CI baut das Artefakt reproduzierbar oder Release stellt ein geprüftes Artefakt plus
  Hash bereit,
- keine 7-GB-Buildreste im Git.

**Done:** frische Maschine kann nach README das erwartete Artefakt erzeugen oder verifizieren.

### L-1103 – Security- und Architektur-Dokumentation

**Dateien:**

- `SECURITY.md`: Meldeweg, unterstützte Version, keine öffentlichen Secret Reports,
- `Docs/Architecture.md`: finaler Target Graph, Composition Roots und Datenflüsse,
- `Docs/ThreatModel.md`: Assets, Trust Boundaries, App Group, Keychain, Temp Files, Clipboard,
  AutoFill, Netzwerk, macOS Sandbox,
- `Docs/ADR/`: State Management, SDK Adapter, Token Sharing, AutoFill Contract, Distribution,
- `CONTRIBUTING.md`: Setup, Tests, Generated Files, Scope Freeze.

**Done:** Dokumentation beschreibt finalen Code, nicht die Übergangsarchitektur.

### L-1104 – README für Lernprojekt-Release

**Umsetzung:**

- klarer Projektstatus oben,
- Screenshots nur mit synthetischen Daten,
- Requirements und reproduzierbares Setup,
- Link zu Feature Status, Known Limitations, Security und Architecture,
- genaue Aussage zu unterstützter Vaultwarden-Testversion ohne allgemeine Kompatibilitätsgarantie,
- Signing/App Group Setup,
- „nicht sicherheitsauditiert“ und geeigneter Disclaimer,
- keine falsche Aussage mehr, dass nur `DEVELOPMENT_TEAM` geändert werden müsse oder Features nie
  voneinander abhängen, falls das final nicht stimmt.

**Done:** frischer Contributor kann bauen; Nutzer versteht Grenzen vor Installation.

### L-1105 – Release Engineering

**Umsetzung:**

- Version `0.1.0-prealpha` oder vergleichbar,
- Changelog mit funktionierend/behoben/bekannt nicht unterstützt,
- Release Build mit Warnings as Errors,
- Archive, Codesign, Notarization beziehungsweise ausgewählte Distribution dokumentieren,
- SHA-256 der veröffentlichten Artefakte,
- Release Notes verlinken Security Disclaimer und Feature Matrix,
- keine Telemetrie hinzufügen.

**Done:** Release Checklist vollständig; Artefakt entspricht Source-Tag.

### Quality Gate 11 – Release Candidate

- alle Quality Gates 0–10 erfüllt,
- Owner-Entscheidungen Lizenz und macOS Distribution dokumentiert,
- keine P0/P1-Defekte offen,
- P2-Defekte entweder behoben oder als konkrete Known Limitation ohne Daten-/Security-Risiko
  dokumentiert,
- CI, Contract Smoke und Real-Device-Matrix grün,
- README/Statusmatrix entsprechen dem tatsächlichen Build.

## 8. Definition of Done für das Gesamtprojekt

Der Umbau ist abgeschlossen, wenn alle folgenden Aussagen wahr sind:

- Ein frischer Clone kann mit dokumentierten Befehlen SDK, Projekt und beide Plattformen bauen.
- Alle Unit-, Contract-, Composition- und UI-Smoke-Tests sind grün.
- Alle Defekte D-001 bis D-027 sind geschlossen oder bei D-021 durch eine Owner-Entscheidung
  kontrolliert.
- Kein Edit eines unterstützten Ciphers verliert unsichtbare Daten.
- Nicht unterstützte Cipher-Typen können nicht versehentlich editiert werden.
- Lock und Logout behandeln In-Memory-State, Keys, Tokens, Cache, Identities und Temp-Dateien gemäß
  der dokumentierten Semantik.
- 429, 5xx und Netzwerkausfall loggen nicht aus.
- AutoFill bietet bei bekannter Domain keine fremden Credentials an.
- Passkey Registration meldet nicht vor bestätigtem Servererfolg Erfolg.
- Bearer Tokens verlassen nie die erlaubte Server-Origin.
- Dateiübertragungen skalieren nicht linear im RAM und hinterlassen keine bekannten Klartextreste.
- Features importieren einander nicht und erzeugen keine Live Dependencies.
- Domain und Feature-Tests benötigen weder Netzwerk noch Keychain, FFI, AppKit oder UIKit.
- App und Extension besitzen getrennte Composition Roots und einen versionierten Vertrag.
- Das Repository enthält Lizenz, Third-Party-Notices, Security Policy, Contribution Guide,
  Architektur, Threat Model, Feature Status und Release Checklist.
- Der Release ist klar als nicht auditiertes Lernprojekt gekennzeichnet.

## 9. Empfohlene Beauftragung von Luna

Nicht „setze den ganzen Plan um“ schreiben. Geeignete Aufträge sind:

```text
Lies Docs/RemainingReleaseWork.md und den eingefrorenen Scope in diesem Plan. Historische Restangaben nicht als neue Aufgaben übernehmen.
Setze ausschließlich Task H-103 um. Halte Scope, Tests und Übergabeformat aus dem Plan ein.
Ändere keine Architektur außerhalb dieser Task.
```

Für eng gekoppelte kleine Tasks darf ein Paket beauftragt werden, zum Beispiel:

```text
Setze S-301 und nur die zugehörigen Tests um. S-302 noch nicht beginnen.
```

Nach jedem Quality Gate sollte ein separates Review stattfinden, das prüft:

- entspricht die Implementierung dem eingefrorenen Scope,
- sind Abhängigkeitsrichtungen eingehalten,
- wurden Defekte wirklich reproduziert und nicht nur Fehlermeldungen versteckt,
- sind Security-Invarianten erhalten,
- baut und testet der Stand reproduzierbar.

## 10. Historischer Umsetzungsstand (2026-09-28)

Dieser Abschnitt bewahrt die damalige Umsetzungsevidenz. Seine Status-/Restangaben sind historisch
und wurden in die [zentrale Arbeitscheckliste](../RemainingReleaseWork.md) abgeglichen.
Nur dort aktuelle Aufgaben pflegen; teilweise inzwischen erledigte Punkte nicht neu implementieren.

**H-103a / A-206 / X-604 – unbekannte Cipher-Felder:** Der bisher offene verlustbehaftete
Write-Pfad wird jetzt durch eine explizite read-only-Grenze abgesichert. Der Decoder erkennt
unbekannte Root-/Nested-/Array-Felder, auch Null-/Leerwerte; ein unveränderbarer Safety-Fence
erzwingt `edit=false` im SDK und Cache. Data prüft das encrypted Backing unabhängig vom
decrypted SDK-Flag; die UI zeigt `unsupportedPayload` statt eine Server-Permission vorzutäuschen.
Editor, Delete, Attachment-Mutationen und Passkey-Registration verweigern unbewahrbare Writes,
auch bei neuem Payload während Crypto oder einer alten Selection. Bekannte Inhalte bleiben
lesbar. Eine neue bekannte Serverrevision löst den lokalen Fence wieder ab. Details und
Akzeptanznachweise: [ADR 026](../ADR/026-unsupported-cipher-write-fence.md).

Finaler Paketlauf nach verstärktem Cache-Encoder: **822 AppModules-Tests bestanden**
(820 Swift-Testing-Methoden/103 Suites plus zwei XCTest); elf neue Methoden. Separat erneut
bestandener unveränderter realer SDK-Smoke = **823 unterschiedliche Methoden über beide Packages**.
Beide Plattformen bestanden die endgültigen unsigned Debug-/Release-App-/Extension-Builds;
genaue Guard-/Build-Ergebnisse stehen in [Verifikation](../Verification.md).

Das ist bewusst **kein beliebiger Unknown-JSON-Roundtrip und keine neue Kompatibilität**.
Unbekannte Werte verbleiben nur am Server, nicht im projizierten DTO; alte bereits verlustbehaftete
Caches brauchen einen frischen Sync. Die H-103/A-206-Restangaben zur vollen Payload-Erhaltung
sind entsprechend als nicht implementierte Zukunftssemantik zu lesen, nicht als weiter offener
ungeschützter Schreibpfad. SDK-Decryption-Diagnostik, reale Server-/Upgrade-/OS-Matrix sowie
die übrigen A-206/X-604-Gates bleiben offen. Nächstes lokales Pflichtpaket: S-302/S-303
operation-eigene Auth-Commit-/Refresh-Recovery; keine neuen Kompatibilitätsfelder nachbauen.

Vorherige Verifikation des File-Send-/Cleanup-/FIFO-Blocks: **811 AppModules-Tests bestanden**
(809 Swift-Testing-Methoden/102 Suites plus 2 XCTest), 27 neue Methoden; vorher separat bestandener
SDK-FFI-Smoke = 812 unterschiedliche Methoden über beide Packages. Eigener File-Send-Pfad nutzt
denselben geschützten Temp-/64-KiB-Multipart-/HTTP-File-Kern wie Attachments. Whole-file-SDK-
Allokation bleibt; F-701/Quality Gate 7 nicht geschlossen. Beide Plattformen bestanden die
unsigned Debug-/Release-App-/Extension-Builds;
genaue Build-/Restgates in Verification und ADR 025.

Vorherige Verifikation des Attachment-Dateitransports: **784 AppModules-Tests bestanden**
(782 Swift-Testing-Methoden in 102 Suites plus zwei XCTest-Tests); SDK-Smoke zuvor separat
bestanden, damit 785 über beide Packages. 14 neue Methoden, beide unsigned Debug-Builds grün.
Beide unsigned Release-Builds am finalen Attachment-Stand ebenfalls bestanden; Befehle in
Verification. Assembly/Blob-HTTP jetzt dateibasiert; SDK-Crypto und File-Send-Pfad behalten Voll-RAM-Grenzen.
Kein dateigrößenunabhängiger Gesamt-Heap, D-016/F-701/F-703 bleiben teilweise (ADR 023).

Vorherige Verifikation des Auth-Cleanup-/Strict-Concurrency-Blocks: **770 AppModules-Tests bestanden**
(768 Swift-Testing-Methoden in 100 Suites plus zwei XCTest-Tests), dazu der erneut ausgeführte
echte SDK-FFI-Smoke (**771 über beide Packages**). 11 neue Cleanup-/Replay-Methoden und eine
Concurrent-Date-Parser-Methode; beide unsigned Debug-App-/Extension-Builds nach Formatkorrektur
bestanden. Eigene Targets prüfen vollständige Strict Concurrency mit Warnings as Errors;
SDK-Warning-Policy unverändert. Details ADR 022 und Verification.

Vorherige Verifikation des TOTP-Ablaufblocks: **758 Tests bestanden**
(756 Swift-Testing-Methoden in 98 Suites plus zwei XCTest-Tests) in den beiden AppModules-Testtargets.
7 neue Methoden zur Epoch-Perioden-/Generation-/Dispatch-Grenze, beide unsigned Builds grün.
Zuvor Terminal-Context-/Fehlerpolicy (751 Tests):
21 Methoden neu: 10 Completion, 4 Query/Context, 4 Fehlerpolicy, 2 SDK-Callback-Cancel,
1 Plattform-Fehlermapping; bestehende Postcommit-Regression um Verifikationsabbruch ergänzt.
Zuvor 18 Methoden zur gemeinsamen OS-Mutationsordnung (730 Tests): 7 async Dateilock, 2 Cache-/Unlock-Policy, 5 Publisher-Guard,
4 kombinierte App-/Extension-Ordnungsregressionen.
Zuvor 26 SDK-Callback-/Registration-Port-Methoden (712 Tests),
22 Recovery-Review-/Abandonment-Methoden (686 Tests), 17 inkrementelle Projektionsmethoden
(664 Tests), 30 Registration-/Recovery-Methoden (647 Tests) und
26 Query-/Passkey-/Session-Methoden ergänzt; bestehende Assertions
erhalten. Der AuthPresentation-Block portierte 65 Methoden und ergänzte 14; beide unsigned
macOS-/iOS-Simulator-App-/Extension-Builds bestehen. Nur AppModules/VaultwardenSDK bleiben als
lokale Packages. Der damals nicht erneut ausgeführte SDK-FFI-Smoke wurde im aktuellen Block
separat erfolgreich ausgeführt; das ist keine vollständige FIDO-/Crypto-Vektor-Matrix.

Historischer vollständiger Baseline-Lauf (2026-09-27): alle damals neun lokalen Paket-Testtargets
gebaut/ausgeführt, **459 Tests bestanden**, beide unsigned App-Builds grün.
Die 27 zentralen Task-Race-/Lifecycle-Tests bestehen zusätzlich in fünf Wiederholungen.
Details und klare Abgrenzung zu noch offenen Server-/Geräte-/Cross-process-Prüfungen stehen in
`Docs/Verification.md`. Die datierten Implementierungsberichte unterhalb dieser
Tabelle behalten ihre damaligen Build-only-Angaben als Historie; sie sind keine aktuelle Testsperre.

| Task | Stand | Ergebnis | Noch offen |
| --- | --- | --- | --- |
| R-000 | erledigt | Lokaler Recovery-Commit `e465721` und Tag `pre-restructure-baseline` existieren. | Recovery-Punkt nur bei einer bewusst neuen Baseline erneuern. |
| R-001 | erledigt | `Scripts/test-packages.sh` testet die zwei verbleibenden lokalen Packages VaultwardenSDK/AppModules sequenziell; `Scripts/build-unsigned.sh` baut macOS und iOS Simulator unsigned. | Die Scripts später um neue UI-/Contract-Targets und CI ergänzen. |
| R-002 | erledigt | `Docs/FeatureStatus.md` und sichtbarer Lernprojekt-/Security-Disclaimer in der README vorhanden. | Statusmatrix mit jeder Feature-Migration aktuell halten. |
| R-003 | offen | Einzelne Regressionstests entstanden mit den Fixes. | Vollständige Charakterisierung für Send, Timeout, Lock/Logout, Cache und Attachment-Lifecycle wie spezifiziert ergänzen. |
| H-101 | erledigt | Store übernimmt Processor-State ohne zusätzlichen Main-Queue-Turn; direkte aufeinanderfolgende Effects sind getestet. | App-Smoke auf SwiftUI-Publishing-Warnung erst in Quality Gate 5. |
| H-102 | erledigt | Zentrale, typisierte `VaultItemPermissions` verhindern Edit/Delete für nicht verlustfrei unterstützte Cipher-Typen, bekannte Attachment-Decryption-Fehler, inaktive Items und für das Formular fehlende Secret-View-Berechtigungen (inklusive Collection-Flags). Nicht auflösbare/mehrdeutige Collection-Zuordnungen sperren Secret-Zugriff und Änderungen fail-closed. Die Wire-Grenze weist unvollständige Required-Payloads und nicht unterstützte Blob-Daten vor einem verlustbehafteten Editor zurück. | Lokale Capability-/Roundtrip-Fixtures bestehen; bei jedem neuen Editor erweitern. Reale Server-Roundtrips bleiben zu prüfen. |
| H-103 | erledigt | Der live verwendete `Domain.VaultItemDraft` enthält nur Formwerte, eigene IDs und die Ausgangsrevision; `SDKVaultItemDraftMapper` bewahrt unveränderte Login-/Identity-/Attachment-Metadaten, optionale Leer-/Nil-Werte und Hidden-Payloads. Typwechsel ist gesperrt. Fehlende/veraltete Edit-Basen und widerrufene Berechtigungen werden vor Crypto und nach dessen Suspension vor HTTP abgelehnt. Doppelte Save-Effects sind serialisiert; nach bestätigtem Server-Write und lokaler Decrypt-Störung wird kein erneut erstellbarer New-Item-Draft angeboten. Der Wire-Pfad bewahrt nun auch Custom Fields, Passwort-Historie und Attachment-Key/-Name (`attachments2`). Nil-/Leer-URI-Zeilen verschieben Match-/Checksum-Metadaten nicht mehr; Delete berücksichtigt das separate serverseitige Permission-Flag und prüft es vor dem Request erneut. | Wire-/Editor-/Permission-Fixtures sind gebaut und bestanden. Unbekannte zukünftige Felder bleiben mit A-206 als separate Payload-Erhaltungsaufgabe offen. |
| H-104 | erledigt | Aktive-Vault- und AutoFill-Sichtbarkeit werden zentral aus Deleted-/Archived-Status abgeleitet. | Die Live-Projektion übernimmt dieselbe Policy; signierte Extension-/OS-Prüfung bleibt offen (D-010). |
| H-105 | erledigt | Attachment-URLs sind same-origin, Redirects werden abgelehnt und Dateinamen für Multipart/Anzeige bereinigt. | Streaming und atomare Temp-Datei-Lifecycle-Arbeit gehören zu Phase 7, nicht zu diesem Sofortfix. |
| D-020 | erledigt | Fehlende oder nicht mehr verfügbare biometrische Enrollment-Daten löschen Keychain-Item und Capability-Flag; der Passwortpfad kann danach wieder eine neue OS-geschützte Enrollment anbieten. Abbruch des LocalAuthentication- oder Keychain-Prompts bleibt still und erhält die Enrollment. | Re-Enrollment, Lockout, Biometry-Changed und echte Keychain-Ausfallfälle auf unterstützten Geräten prüfen; lokale Fake-Fixtures bestehen, ersetzen aber keine Geräteprüfung. |
| D-015 / F-702 | teilweise | Attachment-Transfer und -Preview nutzen den gemeinsamen `SecurityStorage`-Actor mit eigenem Temp-Root, 0700/0600-Rechten, normalisierten Dateinamen, Cleanup beim Sessionstart und Lock/Logout sowie expliziter Inaktivierung nach Lock. Session- und Einzelordner-Cleanup werfen Fehler; die App-Shell widerruft Runtime und Shared-AutoFill-Capability vor dem Datei-Cleanup und hält bei Fehlern eine wiederholbare Recovery offen, und Transfer/Preview zeigen Cleanup-Fehler statt sie zu verschlucken. Die throwing Actor-API und verspätete Preview-Bereinigung sind durch bestandene lokale Fixtures abgedeckt. | D-016/F-701: Eigener Attachment-Transport ist jetzt file-basiert (ADR 023); File-Send teilt jetzt diesen Transferkern (ADR 025); nur der SDK-interne Crypto-Pfad hält weiterhin ganze Dateien im RAM. Echter Gesamt-Heap, Disk-full und App-Lifecycle-Matrix offen. |
| V-401 | teilweise | Ein app-komponiertes `Data.DefaultVaultRepository` besitzt live den SDK-freien `VaultSnapshot`, initiale/geordnete Streams, Single-Flight-Sync und FIFO für Sync/CRUD/Attachments. `SDKVaultSessionSource` hält SDK-Backing und HTTP/Crypto. UI, Cache und Identitäten werden nach bestätigten Writes vom selben Quellstand abgeleitet; Caller-Cancellation verhindert keinen Commit, Runtime-Widerruf verhindert späte Veröffentlichung. Repository-/Source-/Pipeline-Fixtures bestehen. | Reale Server-/Multi-Scene-/Cross-process-Matrix, Extension-Passkey-Serverpfad und vollständige Recovery bleiben offen. Lokale Revisionsguards sind keine serverseitige Konfliktlösung. |
| V-402 | teilweise | Der Live-Repository-Pfad schreibt account-/grant-gebundene encrypted-only Projektionen atomar. Der Codec bewahrt das UUID-Invocation-Fence und ergänzt monotone `projectionRevision`; feste Proofs sperren alte Unlocks. Cachefehler lassen bestätigte Writes bestehen und zeigen Reparaturbedarf. Der bestehende Extension-Reader/Upsert liegt jetzt live in `AutoFillData.LegacyAutoFillCacheStore`; sein injizierter Autorisierungsport prüft Proof und gebundene Tokens im selben SharedToken-Prozess-Lock. Lokale Writer-/Pipeline-/Datei-/Authorization-Fixtures bestehen. | Versionierte Golden-File-/Schema-Grenzen und echte App-/Extension-Prozess-, Dateifehler- und Neustart-Recovery-Matrix prüfen. |
| V-403 | teilweise | App-Publisher und Extension-Passkey-Projektion benötigen nun explizit denselben Domain-Mutationsport. FD-owned App-Group-flock serialisiert Replace/Clear und Add/Recheck/gezielte Compensation; keine Grant-Sperre über OS-awaits. Cache-/Runtime-/Unlock-Guards vor/nach App-Publish und nach Extension-Acquisition, ältere Unlocks dürfen Successor-Identitäten nicht clearen. OS-Fehler/fehlende Koordination melden stale/unavailable statt unguarded Fallback. Registration-Journal bleibt bis exaktem vollständigem Sync/Cache-/OS-Nachweis. 18 neue Methoden, kompletter Lauf 730 Tests und beide regenerierten unsigned Builds bestanden. | Echte signierte OS-Store-/QuickType-/parallele Prozess-/Upgrade-/Termination-Prüfungen ausführen. Keine atomare Cache/Journal/HTTP/OS-Completion, kein durables OS-Fencing gegen späten Daemon-Request nach Prozessdeath. Unverifizierte Health-/Review-Freshness/Recovery-Gaps und unkoordinierte alte Binaries bleiben offen. Siehe ADR 016/019. |
| A-201 | erledigt | `Packages/AppModules` enthält den Ziel-Targetgraph und einen Compile-Test ohne Rückkante. | Neue Targets nur vertikal mit realem Code befüllen; alten Code erst nach Migration löschen. |
| A-202 | teilweise | SDK-freie IDs, Session-/Vault-Grundmodelle, Ladezustand und URL-Normalisierung liegen in `Domain`. Der echte Editor nutzt jetzt `VaultItemDraft` mit unveränderbarer Item-ID, Art und Ausgangsrevision sowie typisierten Draft-Fehlern. SDK-freie Summary-/Detail-Payloads, Folder-/Collection-/Attachment-/Passkey-Anzeigen, typisierte Permissions/Restriction-Codes und Item-ID-/Revision-Contexts für Detail-Aufgaben sind live in Verwendung. Draft-, Summary-, Detail- und TOTP-Beschreibungen sind redigiert; Detail enthält keine Crypto-Keys, versteckten SDK-Payloads oder TOTP-Seeds. SDK-freie `KeyDerivationParameters`, `PreloginService` und stabile `AuthFlowError` sind live an Auth-/SDK-Grenzen angeschlossen. `PasswordSignInCommands`, stabile Login-Rejections sowie opaque Challenge-/Pending-Session-Capabilities liefern Domain-only Ergebnisse an drei Auth-Models. | Domain-Modelle und Fehler-Mapping erst mit den jeweiligen vertikalen Flows vervollständigen. |
| A-203 | teilweise | Repository- und Plattform-Ports sind in `Domain` deklariert. Der SDK-freie Prelogin-Port hat einen produktiven Data-Adapter; Auth-Kontexte verwenden Domain-KDF-Parameter statt SDK.Kdf. `Domain.PinUnlockSettings` wird live von `Data.SessionPinUnlockSettings` implementiert; Settings erhält weder Session noch Store. Frischer Login/TOTP läuft live über Domain-Commands und widerrufbare Capabilities mit Data-Implementierungen; Biometrie-Enrollment erhält nur den Domain-Pending-Port und den OS-Client. ReturningUnlockCommands/Account/Availability/Result/Failure sind ebenfalls Domain-only; Data besitzt den produktiven Returning-Adapter. Domain.AuthFlowCommands/AuthRestoreResult/AuthenticatedSessionCapability sind live mit Data.DefaultAuthFlowService und AppModel verbunden; Controller/Root-UI konsumieren keine Data-Assembly mehr. | Live-Adapter, Use Cases und Feature-Injektion auf diese Ports umstellen. |
| A-204 | teilweise | `Networking` hat Foundation-only Request-/Response-Typen, standardmäßig ephemere Sessions ohne Cookie-/Response-Cache, Auth-Header-Entfernung bei Cross-Origin-Redirects und Redirect-Reject. Uploads lesen aus Datei; Downloads werden in eine geschützte sibling-stage geschrieben und ersetzt. `HTTPStatusError` behält nur Status, `Retry-After` und begrenztes JSON mit redigierten Stringfeldern. Die Live-Send-/Vault-/Settings-Adapter und Auth verwenden dieses Modul statt `NetworkingKit`; Vault-/Send-/Settings-Presentation importiert Networking nicht; Send-Fehlerantworten werden nicht länger vollständig aufbewahrt. Auth-/Prelogin-, Geräteverwaltungs- und Vault-API-Requests weisen Redirects explizit ab. `Data.SharedTokenProvider` und AutoFill verwenden ebenfalls `Networking` statt des alten Transports. Prelogin und Passwort-/TOTP-Transport samt Wire-Modellen/Form-Builder sind nach Data migriert; Credential-Requests prüfen die Server-Policy und Cancellation vor HTTP und nach dem Response. 15 bestehende Transport-Testmethoden sind nach AppModules portiert. | Netzwerk-Testmatrix für Datei-/Redirect-/Cancellation-Fälle vervollständigen und Build-Policy zentral mit P-802 verbinden. NetworkingKit ist nach Portierung seines produktiven Transport-Smokes entfernt. Eigene Attachment-/Send-Datei-Transporte sind file-basiert (ADR 023/025); SDK-interner Whole-file-Heap bleibt D-016. |
| A-205 | teilweise | `SecurityStorage.DefaultKeychainStore` verwendet Update-then-Add und klassifizierte Reads; Auth-, Shared-Token- und Settings-Stores verwenden die SecurityStorage-Ports. PIN-Zählerfehler werden fail-closed behandelt: Fehlversuche müssen vor weiterer Freigabe gespeichert sein, Limit gilt über Appstarts; bei Zählerausfall werden PIN-Key und Account-Flag separat deaktiviert und ein fehlgeschlagener persistenter Rückfall klar gemeldet. Biometrie-Key-Löschung ist throwing; fehlgeschlagener Enrollment-Rollback und Unlock-Cleanup werden nicht verschluckt. Cross-process Token-Lock vermeidet Symlink-Following, setzt restriktive Rechte und bricht bei fehlgeschlagenem Öffnen/`flock` Compare-and-Write, Save oder Clear ab. Private, Shared und gespeicherte Account-Reads unterscheiden notFound von Keychain-/Decode-Fehlern; Die App widerruft den entsperrten Runtime-Zustand vor Lock-/Logout-Cleanup; bei Fehlern bleibt Unlock hinter einer wiederholbaren Recovery gesperrt. Shared-Key/-Token-Löschung wird auch bei Temp-Cleanup- oder Token-Reconciliation-Fehlern versucht. Geräte-IDs müssen vor Login/Unlock persistent sein; Auth-/PIN-/Token-Tests nutzen typed Keychain-Fakes. Lokale Fake-Fehlerpfade sind gebaut und bestanden. Die ungenutzte VaultCore.KeychainService-API ist entfernt; ihr echter Keychain-Roundtrip prüft jetzt DefaultKeychainStore in AppModules. Die frühere AuthKeychainStore-Implementierung liegt jetzt als `Data.AuthCredentialStore` außerhalb der Presentation; App-Komposition injiziert denselben Store direkt in Auth, Lifecycle-Repository und PIN-Settings. | Echter paralleler App-/Extension-Refresh-Race sowie Shared-Token-Lösch-/Refresh-Fehler bleiben mit realen Contract-/Prozess-Prüfungen zu verifizieren; lokale Test-Suites bestehen. |
| A-208 | teilweise | Domain-Port kapselt Pasteboard, Biometrie, Device Name, File Import und Open URL. AuthFeature verwendet Domain.BiometricClient und DeviceNameClient; RootView injiziert SystemBiometricClient und SystemDeviceNameClient. SettingsFeature verwendet Domain.OpenURLClient und zeigt Öffnungsfehler. SendPresentation und VaultPresentation verwenden Domain.FileImportClient; Originaldateien bleiben ohne Klartext-Kopie, security-scoped Zugriff endet nach lokaler Verschlüsselung und Picker-Fehler werden sichtbar. Beide Features verwenden Domain.PasteboardClient; nur PlatformServices enthält Pasteboardzugriffe und die change-count-gesicherte Löschung. Die doppelte VaultCore-Pasteboard-Implementierung samt doppeltem Testset ist entfernt. | Der alte Vault-Identity-Service ist gelöscht; OS-Identitäten werden über Domain/Data/PlatformServices veröffentlicht. Übrige Feature-Framework-Zugriffe prüfen und fehlende Fake-Client-/Fehlerkombinationen ergänzen; vorhandene lokale Suites bestehen. |
| A-206 | teilweise | Laufende Auth-/Vault-/Send-Crypto-Operationen und Client-Konfiguration liegen in `BitwardenSDKAdapter`; der Passwortgenerator nutzt einen SDK-freien Domain-Port mit validiertem, minimum-count-treuem System-RNG-Fallback. Cipher-/Folder-/Collection-/Attachment-Wire-Modelle und SDK-Mapping sowie der gemeinsame Date-Codec liegen jetzt ebenfalls im Adapter; Die nicht mehr benötigten Vault-Legacy-Aliases sind entfernt. Custom Fields, Passwort-Historie, URI- und Attachment-Encryption-Metadaten werden im realen Response -> SDK -> Request-Pfad mitgeführt. Ungültige Enum-/Date-Werte, kaputte Passkeys, doppelte IDs und nicht unterstützte Blob-Payloads werden nicht still normalisiert oder verlustbehaftet editiert. Sync liefert eine SDK-freie `VaultLoadWarning`; die Liste zeigt nicht ladbare aktive Einträge dauerhaft als unvollständig an und erlaubt Retry. Einzel-Item-Decryption respektiert Cancellation. Form-Draft -> SDK-Rekonstruktion und die bestehende Passkey-Item-Factory liegen im Adapter; versteckte SDK-Metadaten sind aus dem Domain-Draft entfernt. `SDKVaultPresentationMapper` leitet die bestehende Liste, Suche, Filter, Details, Berechtigungen und Passkey-Anzeigen in eigene Domain-Werte ab. Die Views importieren das SDK nicht mehr. Verbotene Login-/Karten-/SSH-/Notiz-Secrets fehlen im Detail-Payload; Passkey-Key/-Handle-Payloads gelangen nicht mehr in Feature-Supplement-State. Save-/Attachment-Pfade verwenden stabile, SDK-diagnostikfreie Fehlertexte. Send-Krypto und DTO-Abbildung liegen jetzt ebenfalls im Adapter und verwenden redigierte Domain-Datentypen; Extension-Bridges verwenden weiterhin SDK-geprägte Modelle, die Extension-Crypto-/WebAuthn-Aufrufe laufen aber über den scoped `SDKAutoFillService`. macOS-/iOS-App-Schemes bauen; lokale Wire-/Sync-/Permission-/Recovery- und Send-Tests bestehen. `SDKKeyDerivationMapper` konvertiert App-/Extension-KDF-Parameter gemeinsam: fehlende Werte behalten vorhandene algorithmusspezifische Defaults, ungültige/überlaufende Zahlen und unbekannte Algorithmen werden vor SDK-Aufruf abgewiesen, nicht still auf PBKDF2 normalisiert. Der appseitige Token-Provider ist jetzt SDK-frei in Data; nur `SDKManagedTokenAdapter` implementiert die SDK-Callback-Konformität, ohne zweite Token-Autorität. Frischer Login/TOTP erstellt die opaque SDK-Ressource in Data; `SDKAuthCredentialCryptography` kapselt Hash/Unlock/Key-Derivation ohne raw Client in seinem API. Returning-Unlock nutzt dieselbe opaque Auth-Crypto-Grenze für Passwort/PIN/decrypted-key; keine rohe SDK-Client-Erstellung oder SDK-State-Typen in Auth-Screens/Routen. AutoFill-SDK-Konfiguration, redigierte Credential-/Passkey-Backing-Werte und Assertion-JSON liegen ebenfalls im Adapter; AutoFillData besitzt weder direkten SDK-Import noch SDK-Abhängigkeit. | Rohe unbekannte Payload-Erhaltung, zentrale Fehlerübersetzung und privacy-sicheres Logging vervollständigen. SDK-interne Feld-Decryption-Fehler ohne geworfenen Fehler müssen noch als Degradation erfasst werden. SDK-Kostenlimits für KDFs und vollständige Contract-/FFI-Testmatrix ergänzen; der vorhandene lokale FFI-Smoke-Test besteht. |
| A-207 | teilweise | Versionierter, Foundation-only AutoFill-Envelope lehnt unbekannte Zukunftsschemata ab und enthält keine Klartext-Secrets. | Golden Files, vorherige Schema-Version und der atomare Reader/Writer folgen mit AutoFillData. |
| S-301 | teilweise | App und Extension verwenden denselben typisierten Refresh-Transport in Data und `connector`. 429/5xx haben Vorrang vor dem OAuth-Body; nur explizites `invalid_grant` auf 400/401 ohne Challenge schließt den Coordinator. Retry-After wird endlich/nichtnegativ geparst; positive Delays sperren lokale Refreshes derselben Generation. Login zeigt keine rohen Serverdiagnosen und navigiert bei 429/5xx nicht zu 2FA. Passwort-/TOTP-HTTP und Response-Klassifizierung liegen jetzt in Data; der Refresh-Wrapper delegiert unverändert an den gemeinsamen Transport. Endpoints, Form-Felder und 2FA-Decodierung sind erhalten; unsichere Server-URLs erreichen HTTP nicht. Login-/TOTP-Ergebnisse gehen jetzt als Domain-Rejection-Enum an die UI; auch unbekannte injizierte Diagnosen werden nicht als UI-Text übernommen. Provider 0/TOTP bleibt der einzige ausführbare zweite Faktor. | Lokale Response-/Retry-After-/Login-Regressionstests bestehen; vollständige Fehler-UI und signierte Matrix offen. Siehe `Docs/ADR/002-token-refresh-coordination.md`. |
| S-302 | teilweise | `Data.PrivateAuthSessionStore` speichert Account, Wrapped Keys, Tokens und Sign-in-Scope atomar. Frischer Login startet eine neue Lineage; Split-Tokens autorisieren nie. App-/Extension-Provider delegieren Lookup/Refresh an `Data.TokenCoordinator`. `Data.AppTokenPersistence` besitzt Merge/Commit/Lock-Reconciliation; `Data.ExtensionTokenPersistence` besitzt fixed-proof Persistenz über synchrone scoped Transaction-Ports. `Data.SharedTokenStore`/`SharedTokenTransaction` und `SharedAutoFillUnlockStore` besitzen jetzt auch Shared-Envelope-/Grant-Encoding, widerrufbare synchrone Leases und Cache-Autorisierung. Keychain und Container sind injiziert, fehlender Container scheitert vor Keychain-Zugriff. SDK-freie `SharedAccountInfo` und unveränderte Wire-Namen liegen in AutoFillContract; KDF-Integer-Konvertierung ist throwing im SDK-Adapter. `SecurityStorage.CrossProcessFileLock` besitzt den Lock; Dateiname/Schema bleiben gleich. Unveränderbare Authority, permanenter Widerruf, UUID-Job-Ownership, Single-Flight je Actor und strikt neuere Commit-/Output-Generationen verhindern obsolete lokale Ergebnisse. Kandidaten werden vor Shared-Publikation validiert; niedrigere Generationen sind keine Gewinner. Einseitige Write-Failure-Pfade erhalten die Rotation; Dual-Write-Failure klassifiziert unabhängige Revocation-Failure ohne rohe Diagnosen. Overflow wird vor Refresh abgewiesen. Lokale Regressionstests bestehen; beide App-Builds grün. `Data.AppAuthTokenProvider` und die Bootstrap-Factory besitzen jetzt Fresh-Login-Proof, Scope-/Epoch-Bindung und persistenten Commit; Proof und ungeprüfte raw-key/token Helpers sind Data-intern. Data validiert die ursprüngliche Fresh-Login-Autorität nach jedem Device-/Prelogin-/Hash-/Token-/Unlock-Await und nochmals beim Commit; lokale Gates belegen Denial nach Cancellation, Lock und Lineage-Wechsel. Returning PIN-Increment/-Reset und PIN-/Biometrie-Cleanup verlangen jetzt die vor Suspension erfasste Epoch direkt im Write-Lock; scope-only Produktions-Mutationen sind entfernt. Lokale Gate-/Storage-Denial-Tests belegen keine Mutation nach Lock bei gleicher Lineage. | Die App-Group-Konfiguration liegt jetzt in Composition/SharedAppGroup.swift ohne Core-Paket; Contributor-Konfiguration ist lokal unter P-801 umgesetzt; signierte Container-/Keychain-Berechtigungen bleiben offen. Auth-/Preference-Orchestrierung weiter migrieren. Gleichzeitigen rotierenden Netzwerk-Refresh, Prozessabbruch, Dual-Write-/Revocation-Failure, persistente Recovery und signierte Cross-process-Matrix implementieren/verifizieren. Optionaler SDK-Token-Callback kollabiert typisierte Fehler noch zu nil. Siehe `Docs/ADR/001-auth-token-ownership.md`, `Docs/ADR/002-token-refresh-coordination.md` und `Docs/ADR/003-token-persistence-ports.md`. |
| S-303 | teilweise | `Data.DefaultAuthRepository` restauriert den atomaren privaten Account und besitzt jetzt live die getypten `locked`/`unlocking`/`unlocked`/`expiring`/`signedOut`-Übergänge. Der Restore-Pfad prüft Server-/Accountidentität; Unlock-Start/-Fehler, persistenzgeprüfter Handoff, runtime-ID-gebundener Ablauf sowie Lock/Logout sind angeschlossen. PIN enrollment/removal, PIN counters und Biometrie-Disable/-Read prüfen nun den exakten Sign-in-Scope unter dem Shared-Storage-Lock; Unlock-Routen binden sich an die restaurierte Scope-ID. Login-/TOTP-/Unlock-Submits und Biometrie-Handoff ignorieren parallele Duplikate; betroffene Oberflächen zeigen stabile statt rohe Fehlertexte. State-, Scope-Denial- und Parallel-Unlock-Fixtures bestehen. Fehlgeschlagener Keychain-Cleanup blockiert Restore/Handoff mit durablem auth.cleanup.v1-Marker auch über Store-/Repository-Neuerzeugung; Replay vor Restore (ADR 022). Data.AuthenticatedSession assembliert Domain-Account und opaque SDK-Resource gegen den validierten Token-Scope, ohne öffentlichen Client/Token-Callback; exakte persistierte Serveridentität bleibt erhalten. Token-KDF-Metadaten werden vor Crypto/Commit gegen die tatsächlich verwendeten Prelogin-Parameter geprüft und als explizite Werte gespeichert; Stored-/Shared-Mapping verwendet dieselbe Validierung. AppComposition erzeugt einen Data.AuthCredentialStore und injiziert ihn direkt in DefaultAuthRepository und DefaultAuthFlowService; der Lifecycle-Wrapper und die Feature-eigene Keychain-Komposition sind entfernt. Provider-/Commit-Infrastruktur und StoredAccount->Domain-Mapping liegen jetzt in Data. Data.PasswordSignInService und PasswordSecondFactorChallenge sequenzieren frischen Login/TOTP einschließlich Crypto und Commit. Opaque PendingAuthSession besitzt scoped AutoFill-/Biometrie-Operationen; single-use Handoff nutzt dieselbe Ressource und installiert Expiry vor Rückgabe. Alle fünf Auth-Models verwenden nur Domain-Ports; TOTP-Retry/Transfer/Widerruf und late Key-Derivation sind lokal geprüft. ReturningUnlockService sequenziert auch Passwort/PIN/Biometrie einschließlich Repository-Begin/-Failure, Plattformprompt, Store/SDK, PIN-Fallback, Shared-Publikation und Ownership-Transfer. UnlockModel und alle Routen verwenden nur Domain-Werte/Commands; der persistierte PIN-Key/Budget wird bei jeder Submission erneut geprüft. Restore/Handoff laufen nun über Domain.AuthFlowCommands/AuthenticatedSessionCapability mit Data.DefaultAuthFlowService; nur AppComposition konsumiert die konkrete Data-Assembly. Restore beginnt Unlock nicht vor Submission und prüft Cancellation/Epoch/Account/Scope nach Repository-Awaits. Controller und alle Auth-UI/Tests liegen im Domain-/SharedUI-only AuthPresentation-Target; AuthFeature/Produkt-AuthServices sind entfernt. | Vollständiger repository-observation-only Workflow und app-eigener konkreter Session-Adapter bleiben transitional. Getrennte Keychain-Items sind keine atomare Mehrfach-Key-Transaktion. Durables Commit-/Refresh-Recovery, reale Cleanup-/Crash-Verifikation, operation-eigene Cancellation-Semantik sowie echte Settings-/Key-Replacement-/Multi-Scene-/Geräte-/Prozess-/Server-Matrix bleiben offen. Keine Rollback-/Zeroization-Zusage; siehe Docs/ADR/012-returning-unlock-commands.md. |
| S-304 | teilweise | Biometrie-Cancel löscht keine Enrollment-Daten und kehrt ohne Fehlerbanner zur Passwort-/Unlock-Auswahl zurück, auch wenn der getrennte Keychain-Prompt abgebrochen wird. Fehlende/invalide Keys resetten die Enrollment, OS-/Keychain-Fehler bleiben von Passwortfehlern unterscheidbar. Fake-Tests für beide Cancel-Stellen bestehen. | Vollständige Cancel-/Lockout-/Biometry-Changed-/Item-Missing-/OS-Error-/Re-Enrollment-Matrix auf echten Geräten prüfen; App-Build deckt LA-/Keychain-Races nicht ab. Siehe `Docs/ADR/004-auth-repository-lifecycle.md`. |
| S-305 | teilweise | Fehlversuch-Zähler bleibt auf fünf begrenzt; fehlgeschlagene Fehlerzähler-Writes deaktivieren PIN fail-closed. PIN-Submits sind auch über überlappende Model-Instanzen appweit seriell. Scheitert nach einem korrekten PIN das persistente Zurücksetzen des Zählers, wird Enrollment/Key entfernt; bei fehlgeschlagenem Fallback bleibt PIN-Unlock im aktuellen Flow gesperrt und warnt vor erneutem Versuch. Ungültige KDF-Metadaten scheitern vor Unlock-Beginn/Crypto/Biometrie-Prompt, leeren Eingaben und ändern weder PIN-Zähler noch Enrollment/Keys; sie zählen nicht als falscher PIN. Lokale Regressionstests bestehen. Data.SessionPinUnlockSettings prüft Autorisierung vor/nach Derivation; Enrollment/Removal vergleichen zusätzlich den vorher erfassten Widerrufs-Epoch unter dem Storage-Lock. Kontrollierte Late-Crypto-/Runtime-/Epoch-/Lineage-Fixtures bestehen. | Parallele Model-/Keychain-Versuche und persistente Write-/Disable-Fehler-Matrix auf realem Keychain verifizieren; die einzelnen PIN-Key-/Zähler-/Account-Einträge sind keine atomare Transaktion. |
| S-306 | teilweise | `AppFeature.AppModel` ist der live verwendete `@MainActor @Observable` Session Owner für Root, Settings, Menü und Timeout. `AppSessionStore` ist entfernt. SDK-freie Ports und der app-eigene `AppSessionAdapter` halten konkrete Data-Composition außerhalb von AppFeature; HTTP ist explizit injiziert (ADR 024). Geordnete Repository-Snapshots tragen Transition, Revision und Runtime-ID. Handoff prüft nach allen Suspensionen Epoch/Runtime/Repository; Lock/Logout widerrufen vor Cleanup, warten verspätete Vorbereitung ab und merken Logout während laufendem Lock vor. Recovery blockiert weitere Handoffs. Beide App-Schemes bauen; deterministische AppModel-Regressionstests bestehen, auch in fünf Wiederholungen des kritischen Testblocks. | Credential-Arbeit vor dem AppModel-Handoff gegen Cancel/Lock/Lineage-Wechsel absichern. Persistentes Keychain-Cleanup-Replay ist implementiert (ADR 022); realen Neustart-/Crash-/Marker-Ausfall sowie Multi-Scene-, echte Keychain-/Datei- und signierte Lifecycle-Matrix verifizieren. Siehe `Docs/ADR/005-app-model-ownership.md`. |
| X-601 | teilweise | AutoFillData besitzt account-/unlockgebundenen synchronen Lease, gefenceten Cache-Reader/Writer, URI-Matcher/PSL und ExtensionVaultSession mit CredentialQuery-/PasskeyService-Actors. AutoFillVaultStore enthält nur Composition. Picker halten keine Secrets; Fulfilment löst frisch auf, Partial-Fehler sind sichtbar und mehrdeutige IDs gesperrt. FIDO-SDK-Callbacks/Request-Encoding/Backing/Delta-Policy liegen jetzt vollständig im SDK-Adapter; legacyView ist internal, rohe Crypto-APIs private. Typisierte Registration-Persistenz/Coordinator liegen in AutoFillData, Device-owner-Verifikation in PlatformServices über Domain-Port. Extension importiert kein BitwardenSdk und hat keine direkte SDK-Produktdependency mehr. Kein globaler Client-Cache. 26 weitere Methoden, damaliger kompletter Lauf 712 Tests und beide regenerierten unsigned App-/Extension-Builds bestanden. | Silent SDK-Feld-Degradation, fehlende Collection-Policy im Legacy-Cache und signierte Geräte-/OS-/Prozess-Matrix bleiben offen. Controller/OS-Context und Transport-/App-Composition sind keine vollständig verifizierte OS-Integration. Typisierte Terminal-Orchestrierung und Context-Port sind jetzt live in AutoFillData; siehe ADR 014/018/020. |
| X-602 / X-603 | teilweise | Invocation-Gate verhindert veraltete Callbacks/doppelte terminale API-Aufrufe; alte Grants öffnen Sessions nicht erneut. Password/TOTP lösen frisch auf, List-Picker zeigen Partial-Warnung ohne Secrets. Assertion bindet eindeutige aktuelle Credential-ID und exakte RP, entschlüsselt nur den ausgewählten Cipher, prüft Authority/Cancellation nach Callback und lehnt fremde Ergebnis-ID ab. Busy-Guard verhindert parallele Assertions; mehrere Passkeys je Cipher haben verschiedene Picker-IDs. Direct-Identity entschlüsselt ebenfalls nur den ausgewählten Cipher; fehlgeschlagene konkrete Requests öffnen keine unscoped Liste mehr. SDK-Callback-Suche prüft jetzt exakten decoded UserHandle/IDs/RP statt UserHandle zu ignorieren; Auswahl verlangt genau einen aktuellen ausgewählten Cipher statt first. Metadatenfehler werden nicht verschluckt. User-Verification-/late Lock-/Cancellation-Fixtures bestehen ohne echte OS-Prompts. Terminal-Context-Harness prüft die im Controller verwendete Completion-/Cancellation-Grenze ohne await vor synchronem OS-Dispatch. Typisierte Route-/Fehlermatrix, sticky expliziter Biometrie-Abbruch und Query/Context-Gates bestehen; 21 neue Methoden, 751 Tests und beide unsigned Builds grün. Domain.TimeBasedOneTimeCode erhält SDK-Periode/exakte Generation; bounded Regeneration und terminaler Epoch-Periodencheck sind mit injizierter Uhr geprüft. 7 neue Methoden, 758 Tests grün. | Echter Apple-Controller/UI/OS-Context, reale User-Verification-/UserHandle-/FFI-Matrix und signierte Lock-/Completion-Races bleiben offen. Siehe ADR 018/020/021. |
| X-605 | teilweise | Pure Lock-/Re-Unlock-/Epoch-/Read-Error-/Token-Race-Tests bestehen; explizite signierte Lifecycle-/Upgrade-Matrix ist dokumentiert und offen. | Sämtliche Real-Device-Fälle aus `Docs/AutoFillLifecycleChecks.md` und der Task-Matrix ausführen; kein Release-Gate erfüllt. |
| X-604 | teilweise | Operation-eigener Write-Actor und App-Group-Journal reservieren öffentliche Credential-/Account-Metadaten vor HTTP; unknown/confirmed Retry ist gesperrt. Cache-first inkrementelle OS-Projektion, exakte Rechecks und gezieltes Cleanup sind live. App-Sync reconciliert nur eindeutige Credential/RP/Cipher nach Cache-/OS-Erfolg. Neue Marker binden originatingUnlockID. Explizites Domain-only Review/Abandonment verlangt frischen vollständigen Sync, anderen Unlock, einmalige Nonce, Inspektion/Risiko-Checkbox und unveränderten exakten Record im Grant-/Token-Lock. Typisierter Persistence-Port prüft Originalcache nach Decrypt/vor HTTP und genau ein neues Credential im selben editierbaren Ziel. Whole-registration-Coordinator sperrt vor Crypto, entpackt Writer-Fehler nach FFI-Wrapping und bindet Ergebnis-ID/Attestation an bestätigten Receipt. UI-Cancellation überspringt bestätigte Projektion nicht, aber blockiert Completion; Runtime-Widerruf bleibt wirksam. Kein Rollback, kein HTTP-Retry oder Journalreset. Gemeinsamer FD-owned Identity-Mutationsport hält jetzt Add/Recheck/Compensation gegen App-Replace/Clear geordnet; App-Publish/Clear revalidieren aktuelle Cache-/Unlock-Autorität. 18 weitere Methoden, damaliger kompletter Lauf 730 Tests und beide unsigned Builds bestanden. Terminal-Context/-Fehlerpolicy sperrt bei unklaren/output-invalid Registrierungsfehlern denselben Save und erhält bestätigte Recovery vor User-Cancel; aktueller kompletter Lauf 751 Tests und beide unsigned Builds bestanden. | Legacy-Origin-lose Marker bleiben ohne exakten Credential-Nachweis blockiert. Signierte Review-/Late-HTTP-/Server-/FFI-/Process-kill-/Power-loss-/Cross-process-Matrix bleiben offen. Geordnete teilnehmende OS-Blöcke sind keine atomare Cache-/OS-Completion und kein durables Fencing gegen späte Daemon-Requests nach Prozessabbruch oder alte unkoordinierte Binaries; Health-/Review-Freshness-Gaps verifizieren. Siehe ADR 015/016/017/018/019/020. |
| V-404 | teilweise | Alle vorhandenen URI-Match-Modi, no-match-Verhalten und Regex-Fehler sind getestet; konkrete Websites liefern bei keinem Match keine Credentials. Vollständige Mozilla PSL (inklusive Private-Suffix-, Wildcard- und Exception-Regeln) ist gepinnt gebündelt; IDNA, IPs, Ports und nicht-hierarchische URIs sind abgedeckt. Engine, Tests und unveränderte PSL liegen jetzt in `AutoFillData`; ein SDK-freier `AutoFillURIMatchMode` bildet die vorhandenen Modi ab. Update-Script und Lizenzdokumentation verwenden den neuen Resource-Pfad. | Die Extension-Filter-/OS-Integration für konkrete No-match- und manuelle Leer-Identifier-Fälle vollständig prüfen. Der bestehende Base-Domain-Default bleibt; keine neue Account-Settings-/Vaultwarden-Kompatibilitätsfunktion ergänzen. |
| P-801 | teilweise | Base-/Debug-/Release-xcconfig und ignorierte Local.xcconfig mit Beispiel sind angeschlossen. Team-ID-Fallback und persönliche Team-ID aus Projekt/Swift sind entfernt. Alle vier Bundle-, App-Group-, privaten/shared Keychain- und Versionswerte stammen aus derselben Konfiguration. SecurityStorage.AppStorageConfiguration prüft Werte und Container; instance-based AppComposition/AppStartup blockiert Auth vor Store-/Repository-Komposition bei Fehlern und zeigt Debug-Diagnose ohne Werte. Default-Speichernamen/Schema bleiben gleich. Zehn neue Unit-Testmethoden sowie positive/negative Debug-/Release-Settings-/Template-Prüfungen aller vier Targets bestehen. Contributor benötigen keine Swift-/YAML-Änderung. | Konfigurationscode ist lokal abgeschlossen, aber vorgelagertes Quality Gate 5 und signierte App-Group-/Keychain-/Provisioning-Verifikation bleiben offen. Formatprüfung und Container-Auflösung beweisen keine signierte Berechtigung; P-803 und Release-Gates nicht abschließen. Siehe Docs/ContributorConfiguration.md und Docs/ADR/008-build-configuration.md. |
| P-802 | teilweise | Domain besitzt die einzige Server-URL-Policy: HTTPS oder explizite Debug-Loopbacks; Userinfo, Query, Fragment, leere Hosts und ungültige Ports werden abgewiesen. Domain-Decode validiert die bestehenden vier URL-Felder. Data-Session und AutoFill-SDK-Bootstrap prüfen die Credential-Server-Policy; lokale negative URL-/Scope-Tests bestehen. Die Data-Prelogin-/Passwort-/TOTP-Transporte und der Identity-Refresh-Wrapper prüfen Credential-URLs vor HTTP. Auch die Data-Token-Bootstrap-Factory verweigert unsichere Server vor Erfassung der Speicher-Autorität. | Release-/ATS-/Build-Konfigurations-Matrix und vollständige Durchsetzung über alle bestehenden Transportpfade mit A-204 abschließen. Keine neuen Kompatibilitätsadapter hinzufügen. |
| C-905 | teilweise | `SDKCipherService` und der AutoFill-Passkey-Schreiber nutzen eine durchgehend `@Sendable` Token-Closure statt einer pauschalen `@unchecked Sendable`-Ausnahme; macOS- und iOS-App-Schemes kompilieren. | Verbleibende Projektwarnungen erfassen, Strict-Concurrency-Diagnostik und Warnings-as-Errors in CI aktivieren sowie die Formatter-Version pinnen. |
| U-503 | teilweise | `AppModules.VaultPresentation` enthält die gesamte Vault-UI, `@Observable VaultModel`, State/Actions/Effects und Filter; Abhängigkeiten sind Domain/SharedUI plus System-UI-Frameworks, kein SDK/HTTP/Storage. Repository-Snapshots, typisierte Drafts/IDs, Session-/Revision-/Permission-Guards, Secret-Clearing, bestätigte Write-Ergebnisse, Save-Sperre und injiziertes Temp-Cleanup bleiben live. Model-/State-/SDK-Source-/Cipher-/Sync-/Identity-Tests und Fixtures liegen jetzt bei AppModules. Das alte VaultFeature-Manifest, ungenutzte Sync-/Attachment-/Identity-/Cache-Writer-Services und Legacy-Aliases sind gelöscht; ihre relevanten Regressionen prüfen den produktiven SDKVaultSessionSource-/IdentityMapper-Pfad. Matcher, PSL, gefenceter Cache-Store und Codec liegen in AutoFillData. 510 AppModules-Swift-Testing-Tests plus zwei XCTest-Filtertests bestehen. App/Extension verwenden ausschließlich die zuständigen AppModules-Produkte für Vault/Send/Settings. | Weitere Extension-Orchestrierung migrieren. Reale Multi-Scene-/App-/Extension-Lifecycle-Matrix, unklarer unbestätigter Write-Ausgang und serverseitige Konflikte bleiben offen. Keine neue Re-Prompt-/Kompatibilitätsfunktion hinzufügen. |
| U-501 | erledigt | `AppModules.SettingsPresentation` verwendet Domain und SharedUI; es importiert weder `AuthFeature` noch `VaultCore` oder SDK-Module. Die Presentation nutzt `@Observable SettingsModel` und Domain-only Account-/Session-Capabilities. PIN-Abfragen/Enrollment/Removal laufen über `PinUnlockSettings`; die App-Komposition bindet diesen Port direkt an `Data.SessionPinUnlockSettings` mit Runtime-/Scope-/Epoch-Prüfung und demselben Credential-Store wie Auth/Repository. `PinEnrollment` und der app-eigene PIN-Adapter sind entfernt. Devices laufen über `Domain.SettingsRepository` und `Data.DefaultSettingsRepository` mit Runtime-Widerruf, Redirect-Sperre und validierten IDs. Revoke verlangt Bestätigung, zeigt laufende IDs und verhindert Doppelaktionen. Timeout-Policy liegt in Domain, UserDefaults-Persistenz in Data und der appweite Watchdog in AppFeature; Settings lädt/speichert über injizierten Port, zeigt Fehler, und eine nicht lesbare Policy sperrt bei fälligem Timeout fail-closed. 23 Settings-Tests sowie die zugehörigen Data-/AppFeature-Tests sind Teil des bestandenen AppModules-Laufs (510 plus zwei XCTest-Tests). Das alte SettingsFeature-Manifest ist entfernt; die App importiert SettingsPresentation. |
| U-502 | erledigt | `AppModules.SendPresentation` verwendet eine `@Observable SendModel`-Presentation mit Domain-Werten und injiziertem `SendRepository`; SDK-/HTTP-/Session-Verantwortung liegt in `BitwardenSDKAdapter`/`Data`. Das Feature hängt nur von `Domain` und `SharedUI` ab; Store, Processor, Coordinator und SDK-geprägte Send-DTOs sind entfernt. Bestätigte Mutationen werden repository-eigen projiziert, auch wenn ein UI-Consumer abbricht; Runtime-Widerruf bleibt wirksam. Datei-Upload-/Cleanup-Fehler und bereits bestätigte Teil-Writes werden getrennt dargestellt, um unbeabsichtigte Doppel-Uploads zu verhindern. Die vier Send-Model-Tests sind jetzt Teil des bestandenen AppModules-Laufs (510 plus zwei XCTest-Tests); das alte SendFeature-Manifest und seine Xcode-Abhängigkeiten sind entfernt. |
| U-504 | teilweise | AuthPresentation in AppModules enthält alle fünf Observation-Models, State/Actions/Views, typed Flow Controller und AuthRootView; Produktabhängigkeiten ausschließlich Domain/SharedUI. Domain.AuthFlowCommands besitzt Password-Command, Restore und Runtime-Handoff; AuthenticatedSessionCapability enthält nur Account/ID/Access/Authorization/Revoke. Data.DefaultAuthFlowService assembliert Commands/Restore/Handoff gegen den einen injizierten Credential-Store/Repository. Alte AuthServices und das AuthFeature-Manifest sind entfernt; AuthDependencies existiert ausschließlich im Testtarget. PIN-/Biometrie-/Epoch-/Transfer-/Secret-Clearing-Invarianten bleiben erhalten. Veralteter Restore revokiert late Commands; veralteter Handoff revokiert late Runtime, accepted Teardown nicht. Alle 65 bisherigen Auth-Methoden sind mit Assertions portiert; zehn neue Data- und vier Domain-only Controller-Methoden ergänzt. 589 Swift-Testing-Methoden in 75 Suites plus zwei XCTest-Tests bestehen (591 gesamt), ebenso beide regenerierten unsigned Builds. | Vollständiger repository-observation-only Auth-Workflow statt Übergabenotifikation, operation-eigene Commit-/Cancellation-Semantik, durable Recovery sowie Settings-/Multi-Window-/Server-/signierte Geräte-Matrix bleiben offen. AppComposition konsumiert noch die konkrete Data-Assembly für ihren Session-Adapter. Keine Zeroization/Rollback-Zusage oder neuen Kompatibilitätsfeatures. Siehe Docs/ADR/013-auth-presentation-and-handoff.md. |
| U-506 | erledigt | Keine Store-/StateProcessor-/generische Coordinator-Basis oder AppArchitecture-Imports im Produktcode. Paket, alte generische Tests und alle Projekt-/Manifestabhängigkeiten sind gelöscht. Auth behält ausschließlich einen featurelokalen typed Observation Flow Controller; Retention/direct-state-Invarianten laufen gegen produktive Auth-Models. Importprüfung, betroffene Suites und beide unsigned App-/Extension-Builds bestehen. |
| C-901 | teilweise | Vault-, Send- und Settings-Sources einschließlich Model-/State-/SDK-/Regressionstests liegen in den vorgesehenen AppModules-Presentation-/Adapter-Targets. Gemeinsame Shared-Token-/Unlock-Persistenz und ihre bisherigen Core-Tests liegen jetzt ebenfalls in Data/AppModules; SDK-freie Account-Wirewerte in AutoFillContract, KDF-Mapping im Adapter. Drei alte Feature-Manifeste sowie VaultCore sind entfernt. Session-Assembly liegt in Data; alle verbleibenden Core-Tests sind portiert und ausgeführt. 510 Swift-Testing-Tests plus zwei XCTest-Tests sowie beide unsigned App-/Extension-Builds bestehen. Auth-HTTP-/Wire-Sources und 15 bestehende Transporttests sind ebenfalls nach Data/AppModules migriert. Auth-Credential-Store, App-Token-Provider, Bootstrap, PIN-Settings und 54 bestehende Speicher-/Token-Testmethoden liegen ebenfalls in Data/AppModules. Frisches Login-/TOTP-Sequencing, JWT-Bookkeeping und private Challenge-/Pending-Ressourcen sind nach Data migriert. Vier weitere bestehende Testmethoden sind nach AppModules portiert, 18 Methoden neu. Der aktuelle Gesamtblock besteht mit 577 Tests einschließlich Auth und beiden unsigned Builds. Returning-Orchestrierung liegt jetzt ebenfalls in Data, der verbleibende UI-/Routen-Code konsumiert Domain-Ports. 14 neue Data- und drei neue Model-Methoden prüfen diesen Block; bisherige Assertions bleiben erhalten. Auth-UI/Controller/RootView und alle 65 bisherigen Auth-Tests sind jetzt nach AuthPresentation/AppModules migriert. Die neue Restore-/Handoff-Service-Komposition liegt in Data, alle UI-APIs Domain-only. 14 Methoden neu; aktueller kompletter Lauf 591 Tests und beide unsigned Builds bestanden. AutoFill-Invocation-/Query-/Assertion-Orchestrierung liegt jetzt ebenfalls in AppModules.AutoFillData; 26 neue Methoden inklusive Direct-Identity-Nachfix, aktueller kompletter Lauf 617 Tests und beide unsigned Builds bestanden. Registration-Mutationssequencing/Journal liegen ebenfalls in AutoFillData, Sync-Reconcile/Warnings in Data/Domain; SDK-Write-Klassifikation im Adapter. 30 weitere Methoden; damaliger kompletter Lauf 647 Tests und beide unsigned Builds bestanden. Die direkte inkrementelle Registration-Projektion liegt jetzt ebenfalls in AutoFillData mit Domain-Port und PlatformServices-Adapter; 17 weitere Methoden, damaliger Lauf 664 Tests und beide regenerierten unsigned Builds bestanden. Review-Metadaten liegen in Domain, noncegebundene Recovery in Data, explizite Sheet/Actions in VaultPresentation; AutoFillData entfernt nur den unter Grant-Lock exakt verglichenen Record nach frischem Unlock. 22 weitere Methoden, damaliger kompletter Lauf 686 Tests und beide unsigned Builds bestanden. SDK-FIDO-Callbacks/Request-Encoding/Delta-Validator liegen jetzt im SDKAdapter, typisierte Registration-Persistenz/-Coordinator in AutoFillData und Device-owner-Verifier in PlatformServices. Die Extension hat keine raw SDK-Imports/-Produkte mehr. 26 weitere Methoden, damaliger kompletter Lauf 712 Tests und beide unsigned Builds bestanden. Shared-OS-Mutationsport liegt in Domain, async FD-Lock in SecurityStorage, Cache-/Unlock-Policy in AutoFillData; App-/Extension-Composition injiziert denselben Lock. 18 weitere Methoden, damaliger kompletter Lauf 730 Tests und beide unsigned Builds bestanden. Terminal-Orchestrierung/Context-Port/Fehlerpolicy liegen in AutoFillData; Extension hat nur den Apple-Adapter. 21 weitere Methoden, aktueller kompletter Lauf 751 Tests und beide unsigned Builds bestanden. | App-Shell-/OS-Context-/Composition-Adapter und verbleibende Auth-Commit-/Recovery-Grenzen prüfen; noch nicht alle handgeschriebenen Module liegen in AppModules. |
| C-902 | erledigt | project.yml enthält nur noch AppModules und VaultwardenSDK als lokale Packages. App-Targets nutzen Auth-/Vault-/Send-/SettingsPresentation und AppFeature; Composition behält ausdrücklich benötigte Data-/Storage-/Networking-/SDK-/AutoFill-Adapterprodukte. Extension-Targets importieren keine Presentation-Produkte. XcodeGen-Regeneration und xcodebuild -list -json zeigen beide Apps und beide Extensions korrekt; beide unsigned App-/Extension-Builds bestehen. Testscript/README verwenden die zwei verbleibenden Packages. | Verbleibende direkte Extension-Adapterabhängigkeiten bei X-601 weiter reduzieren; keine Release-/Signierungs-Gate-Zusage. |
| C-903 | teilweise | Ungenutzte Vault-Service-Parallelimplementierungen, Aliases und Spies sowie alte Vault-/Send-/Settings-Manifeste sind entfernt. Shared-Persistenz/Wiretypen liegen ohne doppelte Core-Implementierung in Data/AutoFillContract. Generische Store-/Processor-/Coordinator-Basis und AppArchitecture sind nach Auth-Model-Portierung gelöscht; NetworkingKit nach Portierung seines Transport-Tests ebenso. VaultCore samt ungenutzten Keychain-/Environment-/SDK-Aliases ist nach Migration aller Consumer und verbliebenen Tests entfernt. README, Projektgraph und Testscript verwenden zwei verbleibende Pakete. Feature-eigener AuthKeychainStore/AccessTokenProvider, Lifecycle-Wrapper, PinEnrollment und app-eigener PIN-Adapter sind nach Migration entfernt. TwoFactorContext, PendingSessionContext, AuthUnlockFlow und Feature-eigenes JWT-Bookkeeping sind nach Migration ohne Alias gelöscht. Die produktive raw SDKClientFactory sowie StoredAccount/StoredTokens/VaultUnlockService-Aliases sind gelöscht. BitwardenSdk/AutoFillContract/SecurityStorage sind keine direkten AuthFeature-Produktabhängigkeiten mehr; SDK/Storage-Fixtures bleiben im Testtarget. AuthFeature ist nach Consumer-Migration entfernt; produktive AuthServices ebenso. AuthDependencies und raw-client No-Handle-Fixtures bestehen nur im separaten AuthPresentationTests-Target. Keychain-Service-Namen behalten den historischen AuthFeature-Suffix, keine Credential-Migration durch Umbenennung. AutoFillVaultStore-Nested-Session, MatchedLogin, NoOp-Tokenprovider und Request-JSON-Helper sind nach Migration gelöscht, ohne Aliases; legacyView ist nun SDK-internal, perform bietet nur typed Adapter-Operationen; raw FIDO-/Registration-Backing liegt im Adapter und die Extension hat keine direkte SDK-Dependency mehr. | App-eigener Session-Adapter, verbleibende Extension-Migrationsadapter, übrige Migration-TODOs und finale Artefaktbereinigung bleiben offen. |

### Architektur und Quellcode-Freigabevorbereitung (2026-09-28)

| Task | Stand | Ergebnis | Noch offen |
| --- | --- | --- | --- |
| F-703 / D-016 | eigener Transferkern umgesetzt, reale Verifikation teilweise | File-Send verwendet vorhandenes SDK-encryptFile, geschützten Temp-Owner, 64-KiB-Multipart und HTTP-File-Ports; UInt64-Größe, Scope nur während Crypto, Direct-Bearer/Azure-no-Bearer/Redirect-Policy erhalten. Load/Mutationen FIFO. Cleanup vor/nach Commit und Uploadfehler getrennt; bestätigte Drafts schließen vor UI-Cancellation. Numerische/Datumsgrenzen ohne Trap/Clamping. 27 neue Methoden, voller Lauf 811 AppModules-Tests und beide Plattformen unsigned Debug/Release bestanden, ADR 025. | Echte SDK-Crypto-/Heap-/Server-/Disk-full-/Crash-/signierte Protection-/Scoped-Access-/Multi-Scene-Matrix. F-701/Quality Gate 7 offen wegen SDK-Whole-file-Allokation. Keine neue Send-Download-/Exportfunktion außerhalb des bisherigen Flows. |
| C-902 / C-903 | weiterer Cleanup umgesetzt | Vier Presentation-Targets liegen physisch unter `Sources/*Presentation`, ohne Legacy-Manifestpfade. AppSessionAdapter/PersistentTimeoutDriver beschreiben die aktuelle Composition. AutoFillFeature besitzt gemeinsame Picker-/Registration-Views; Extensions importieren nun dieses UI-Produkt, nicht rohes SDK. Der früher anders beschriebene C-902-Graph oben ist Historie. | Verbleibende Auth-Operation-/Recovery-Grenzen und tatsächliche Apple-Controller-/Lifecycle-Matrix; konkrete Composition-Adapter sind beabsichtigt, keine zu löschenden SDK-Aliases. |
| C-904 | lokal umgesetzt, CI vorbereitet | Source-/Manifest-Checks verbieten Reverse-/UI-/rohe SDK-Imports, `.live()` und konkrete HTTP-Factories außerhalb Composition/Networking. Sechs negative Wegwerf-Fixtures bestehen. Send/Settings verlangen expliziten HTTP-Port; AutoFillFeature hängt nicht mehr an AutoFillData. Vollständiger Paketlauf nach endgültigen Moves: 784 bestanden. | Source-Guard ist kein AST-Beweis; vollständiger Fake-App-/Extension-Composition-/UI-Smoke und Remote-CI bleiben offen. |
| C-905 | lokal umgesetzt, CI vorbereitet | Gepinntes SwiftFormat 0.63.0/Archivhash, eigene Targets Strict Concurrency complete/Warnungen als Fehler, SDK-Warning-Policy unverändert; Swift-5-Sprachmodus beibehalten. | Remote-CI und ältere Toolchains unbewiesen; jede unvermeidbare Sendable-Ausnahme weiterhin einzeln prüfen. |
| T-1005 | vorbereitet | Gepinnter Checkout, read-only Berechtigungen, Source-Guards/Secret-Fixtures, isolierter SDK-Build, beide Testpackages, unsigned Debug/Release und synthetische Konfigurationsmatrix in `.github/workflows/verify-source.yml`. Keine Signing-/Server-Secrets oder Uploads. | Workflow noch nicht auf GitHub gelaufen; kein grün behaupteter Fresh-Clone-CI-Gate. |
| L-1101 | ursprünglicher MIT-Stand durch Owner-Wahl 2026-11-07 ersetzt | GPL-3.0-only für eigene Dateien; upstream angebotene GPLv3-Option für die dual lizenzierten Bitwarden-SDK-Bestandteile des Source-only-Pakets gewählt. Keine Fremdsoftware wurde umgelizenziert. | Source-only-F-17 erledigt; konkrete Binärartefakte und deren Notices separat prüfen. |
| L-1102 | isolierter lokaler Neubau verifiziert | Alle fünf Release-Slices gebaut; Source-Pin/Toolchain/Patch/Lockfile/Bindings geprüft; echter FFI-Smoke gegen Neubau bestanden. Neues Inhaltsinventar und Cargo-Metadaten im ignorierten Scratch-Root; historisches installiertes Inventar bleibt separat. | Anderer Fresh-Clone-Rechner und Remote-CI; keine byteidentische Reproduktion/Provenance-Attestation. Siehe `Docs/SDKRebuildVerification.md`. |
| L-1103 / L-1104 | Dokumentation und Kontakt umgesetzt | Architecture, ThreatModel, CONTRIBUTING, SECURITY, CHANGELOG, Lernprojekt-README und Source-only-Freigabecheckliste beschreiben tatsächlichen Code und Restdefekte. Owner wählte welcome@temmi.land als privaten Security-Kontakt. | Owner prüft die Mail-Erreichbarkeit; keine Testmail oder garantierte Response-Zeit. Dokumentation nicht als vollständigen Hardening-Abschluss lesen. |
| L-1105 | nur Source-Vorbereitung im Scope | Owner wählte erste Veröffentlichung ohne installierbare Apps; lokale unsigned Release-Checks sind weiterhin sinnvoll. Kein Push/Tag/Release/Upload autorisiert. | Owner veröffentlicht ausgewählten Commit nach History-/Assets-/Notices-Review; Signed Archive/Distribution/Geräte-/SDK-Binary-Gates bleiben spätere eigene Freigabe. |

**Zusätzlicher Release-Befund – fail-closed abgesichert (2026-09-26):** Der zuvor fehlende
Zugriffsschutz für `CipherRepromptType.password` wird jetzt von `SDKVaultAccessPolicy` im eigenen
Adapter erzwungen. Ohne Re-Prompt-Freigabe fehlen sensible Detailwerte in den Domain-Projektionen;
TOTP-/Passkey-Laden, Bearbeiten/Löschen und Attachment-Zugriffe sind gesperrt. Auch Identity-/
Karten-Details werden bei fehlender Secret-View-Permission redigiert. Namen und Login-Usernames/
URIs bleiben nicht geheime Browsing-Metadaten. Ein Editor mit Klartextwerten wird bei entzogenem
Secret-Zugriff geschlossen, seine ungespeicherten Änderungen werden verworfen und dies wird
gemeldet; verspätete Form-Bindings können ihn nicht erneut öffnen. Save prüft das Flag auch nach
der suspendierenden Verschlüsselung erneut.

Cache-Write/-Upsert und Credential-Identity-Publishing schließen geschützte Logins aus. Die
Extension prüft zusätzlich alte Cache-Datensätze sowie direkte Anfragen für vorhandene OS-
Identities; Passwort-/TOTP-Fulfilment verwendet keine alte Picker-Kopie der Secrets. Passkey-
Assertion prüft den aktuellen Cache vor und nach der Geräteauthentifizierung. Registration prüft
das gewählte bestehende Item inklusive eindeutiger ID, Revision und Edit-Permission vor/nach der
Geräteauthentifizierung und vor dem Serverwrite; auch der verschlüsselte Schreibpayload muss die
Policy und die gewählte Ziel-ID erfüllen. Re-Prompt-Flags werden nie entfernt; Gerätebiometrie
oder ein bereits entsperrter SDK-Client gelten nicht als Master-Passwort-Nachweis. Die gemeinsame
Policy wird über einen klar markierten Legacy-Alias exportiert, bis `X-601` die Extension von
`VaultFeature` löst.

macOS-/iOS-Simulator-App-Builds inklusive Extensions sind grün; neue/angepasste Regressionstest-
Quellen wurden auf Wunsch weder gebaut noch ausgeführt. Das ist kein Security- oder Release-
Nachweis. Die Guards prüfen ausschließlich den verfügbaren lokalen Cache: eine fehlgeschlagene
Projektion kann weiterhin veraltete Serverberechtigungen hinterlassen. Account-/Unlock-Epochs und
der Widerruf des extensionweit gecachten Clients sind inzwischen implementiert (siehe X-601
unten), aber nicht auf signierten Geräten verifiziert. Collection-Permissions im Extension-Contract
bleiben offen. Ebenso fehlen serverseitige Konflikt-/Conditional-Write-
Garantien. Ein sessiongebundener, widerrufbarer Master-Passwort-Nachweis bleibt Aufgabe von
`S-303`; bis dahin bleiben Re-Prompt-Items eingeschränkt. Keine neue Re-Prompt- oder Vaultwarden-
Kompatibilitätsoberfläche hinzufügen; `X-604` ist damit nicht vollständig erledigt.

**S-303 – Live-Lifetime teilweise umgesetzt (2026-09-26):** `Data.SessionRuntime` besitzt ab dem
erfolgreichen Auth-Handoff eine eigene UUID, Domain-Account-Metadaten, einen widerrufbaren SDK-
Resource-Port und den App-Tokenprovider. Der private Client steckt nur in `SDKSessionClient`;
Vault-/Send-/Auth-Crypto und der Generator prüfen die gemeinsame Resource vor und nach ihren
Operationen. Die Legacy-`AuthenticatedSession` gibt keinen Client mehr an ihre Consumer zurück,
sondern scoped Services. Ein sessiongebundener Pasteboard-Wrapper sperrt auch verspätete Copy-
Closures aus alten Views; bereits vorher kopierte Werte behalten die bestehende Auto-Clear-Policy.
Explizite bestehende API-/Identity-/WebVault-Routen bleiben in den
Domain-Account-Metadaten erhalten; es entsteht keine neue Kompatibilitätsoberfläche.

`SessionHTTPClient` registriert Transport-Tasks im Runtime-Actor und cancelt sie beim Widerruf.
Auch eine nicht kooperative Dependency darf danach keinen Wert zurückgeben. Vault, Sends und
Settings beobachten den Runtime-Stream; obsolete State-Owner leeren Secrets, Formulare, TOTP/
Passkey-Supplements und Preview-Referenzen und verwerfen weitere Actions/Effects. Feature-Guards
prüfen zusätzlich nach suspendierenden Crypto-/Transport-/Picker-Schritten. Generator-Fallback
darf Cancellation nicht in ein erfolgreiches Ergebnis umwandeln. PIN-Enrollment prüft die Session
nach Derivation; seine lokale Persistenz läuft auf dem MainActor wie der App-Cleanup.

Der App-Tokenprovider ist permanent widerrufbar. Er cancelt den Refresh-Task und führt dessen
Persistenz nur auf seinem Actor nach erneuter Widerrufsprüfung aus. `Runtime.revoke()` wartet
Token-Shutdown vor Keychain-Löschung ab; ein später zurückkehrender Refresh kann die gelöschten
Tokens nicht wiederherstellen. Der Expiry-Handler wird vor dem Handoff registriert und trägt die
Runtime-ID, sodass ein altes Event keine spätere Sitzung abmeldet. Login-Token-/Account-Writes
sind throwing statt still best effort.

Die App entfernt den authentifizierten View-Tree und widerruft die Runtime vor Datei-/Keychain-
Cleanup. Fehlgeschlagene Bereinigung hält eine explizite, wiederholbare Recovery offen und lässt
keinen neuen Unlock zu. Temp-Cleanup und Shared-Capability-Revocation werden unabhängig versucht;
auch ein Fehler beim Übernehmen neuerer Shared Tokens darf ihre Löschung nicht überspringen.
Ein App-Handoff-Epoch verhindert, dass eine während Lock laufende Session-Vorbereitung später
wieder als aktiv erscheint. Neue UUIDs setzen die authentifizierten SwiftUI-StateObjects zurück.

**Noch nicht erledigt (aktualisiert 2026-09-27):** Der initiale `DefaultAuthRepository`-Stateautomat
ist live für Restore, Unlock-Beginn/-Fehler, Handoff, Ablauf, Lock und Logout (siehe S-303-Eintrag
unten). Passwort-/Prelogin-/2FA-/OAuth- und SDK-Unlock-Ausführung sowie die vollständige
Ownership-/Persistenzmigration von `S-302` nach Data bleiben offen. Auth-Routen/Unlock verwenden
weiterhin Legacy-Kontexte und SDK-Modelle; Presentation erhält noch den Übergangs-Session-Wrapper
und Token-Closures. Account-/Token-Writes bilden jetzt einen atomaren privaten Record (siehe
aktueller S-302-Abschnitt unten). PIN-/Biometrie-Lese-/Schreibpfade prüfen den exakten
Sign-in-Scope unter dem Shared-Storage-Lock, aber die getrennten Keychain-Items sind keine atomare
Mehrfach-Key-Transaktion; breitere Account-/Timeout-Settings bleiben offen. Die Extension verwendet jetzt eine eigene
Cross-process-Unlock-Epoch und einen invocation-scoped SDK-Holder (siehe unten); die vollständige
AutoFillData-/Repository-Anbindung und signierte Verifikation sind weiterhin offen.
Bereits bestätigte Serverwrites lassen sich durch Cancellation nicht zurücknehmen; ein unklarer
Write-Ausgang braucht weiterhin Repository-Recovery. OS-Identity-Publish-Races und ein persistenter
Cleanup-Recovery-Marker über App-Relaunch sind offen. Die Resource-Sperre beweist keine Zeroization
von SDK-internem Speicher oder bereits an einen Consumer ausgegebenen Werten. Die Locks im SDK-
Holder schützen ausschließlich Referenzzugriff; keine SDK-Arbeit oder Suspension läuft darunter.

macOS-/iOS-Simulator-App-Builds inklusive Extensions sind grün. Reine Runtime-/Transport-/Token-
Race-Fixtures und Legacy-Feature-Regressionstestquellen sind ergänzt/angepasst, aber auf Wunsch
nicht gebaut/ausgeführt. Reale Lifecycle-, Keychain-Failure- und Cross-process-Nachweise fehlen;
`S-303` und die Release-Definition bleiben deshalb offen.

**X-601/X-602/X-603 – Extension-Lifetime teilweise umgesetzt (2026-09-26):** Der globale
`ClientCache` ist entfernt. Der Controller besitzt pro OS-Invocation einen `UnlockedSession`-
Holder; Picker, fulfilment und FIDO2-Callbacks teilen nur diese Resource. `AutoFillData.ExtensionSession`
prüft einen frischen account-/server-/unlockgebundenen `ExtensionUnlockProof`. Die Keychain-
Capability enthält Key und vollständige Crypto-Account-Metadaten atomar in einem schema-
geprüften Record; rohe Legacy-Keys und ungültige KDF-Parameter werden nicht zum SDK durchgereicht.

Vor Shared-Key-Löschung rotiert ein unabhängiger, nicht geheimer Revocation-Epoch. Rotation und
Löschung werden unabhängig versucht: erfolgreiche Rotation sperrt einen trotz Löschfehler noch
vorhandenen Record; erfolgreiche Löschung sperrt bei Rotationsfehler. Wenn beide scheitern, ist
kein Cross-process-Widerruf bewiesen; die App bleibt in Cleanup-Recovery. Der bestehende App-
Group-Prozesslock serialisiert Epoch-/Grant-Publikation und Token-Compare-and-Write, niemals SDK-/
Netzwerk-Arbeit. Eine vor Lock gestartete Key-Derivation darf nur für ihren unveränderten Epoch
publizieren; Account-Metadaten werden nach Suspension erneut geprüft. Token-Mirroring findet erst
nach erfolgreicher Grant-Publikation ohne neue MainActor-Suspension statt. Der Extension-Refresh
prüft denselben Unlock-Proof im Compare-and-Write und nach dem Await, sodass ein alter Refresh auch
bei gleichen Token-Generationen nach Re-Unlock keinen neuen Tokenrecord überschreiben kann.

Der Legacy-Cache trägt jetzt Account-/Server-Ownership und eine lokale UUID-Revision. Ein voller
Live-Sync schreibt beides; Passkey-Upsert erhält Ownership und erneuert die Revision. Alte,
ungebundene oder fremde Caches werden abgelehnt; nach Upgrade sind App-Unlock und ein Sync nötig.
Fehlende/ungültige Listendaten zeigen Recovery-Hinweise statt einer irreführenden No-Matches-Anzeige.
Die laufende Invocation darf keine andere Revision/Organisation-Crypto mit dem alten Client
kombinieren. Das ist lokale Invalidation, nicht die atomare `V-402`-Projection oder eine Server-
Revision. Cache-/OS-Identity-Consistency nach App-Mutationen bleibt offen.

Alle Extension-Crypto-/WebAuthn-Aufrufe laufen durch `SDKAutoFillService` und den widerrufbaren
`SDKSessionClient`; Consumer erhalten keinen rohen Client. Passwort/TOTP lösen das gewählte Item
erneut auf und prüfen Invocation, Grant und Cache unmittelbar vor dem OS-Aufruf. Passkey-
Callbacks prüfen vor/nach Geräteauthentifizierung und vor Writes. Registration prüft nach dem
Servercommit den Grant, lehnt aber nicht allein ihre eigene erfolgreiche Cache-Mutation ab.
Ein sichtbarer Picker kontrolliert den Grant zusätzlich im geplanten Ein-Sekunden-Intervall,
leert bei Widerruf seine Werte und cancelt. Das ist kein harter Zeit-/Benachrichtigungsnachweis.

`ExtensionRequestLifecycle` sperrt veraltete UI-/Task-Callbacks und erlaubt höchstens einen
Completion-/Cancel-Aufruf pro Invocation. Doppeltaps können keinen parallelen Save starten.
Widerrufene Invocations werden nicht durch Laden eines neueren Grants wieder geöffnet. Bereits
ausgegebene OS-Credentials und bestätigte Serverwrites sind nicht rückholbar. Bei unklaren
Registration-Fehlern behauptet die UI deshalb nicht mehr „Nothing was created“; Sync vor einem
Retry wird empfohlen. Persistente Mutation-IDs/Recovery und Duplicate-Prevention über Retries/
Relaunch fehlen weiterhin mit `X-604`.

**Noch offen:** `AutoFillVaultStore`, URI-Matcher und der Legacy-Cache-/Writer müssen vollständig
nach `AutoFillData` hinter die vorgesehenen Ports wandern; der Extension-Target importiert weiterhin
`VaultFeature`. SDK-geprägte Callback-/Item-Modelle, Collection-Permissions, Partial-Decryption-UI,
OS-Identity-Revisionen und das injizierbare AuthenticationServices-Context-Harness sind nicht
fertig. Die endgültige Verifikation von Lock versus bereits begonnener OS-Completion ist
ausstehend; Keychain und OS-Completion sind keine gemeinsame Transaktion. Unterliegende
nicht kooperative SDK-/Netzwerk-Arbeit kann intern fertiglaufen, ihre obsolete Antwort wird an
den Guards verworfen. Keine Zeroization-Garantie oder neue Master-Passwort-Freigabe wird behauptet.
Die Produktions-Storage verlangt jetzt einen verfügbaren App-Group-Container; ein Prozess-only-
Lock ist ausschließlich explizite Fixture-Policy. Shared Tokens sind zusätzlich account-/server-/
sign-in-/unlockgebunden (siehe aktueller S-302-Abschnitt unten). Das ist kein atomarer Commit über
sämtliche Keys, Netzwerk-Refreshes und Server-/OS-Aktionen; die echte signierte Cross-process-
Verifikation und persistente Recovery bleiben mit S-302 ausdrücklich Release-Blocker.

macOS-/iOS-Simulator-App-Builds inklusive Extensions sind grün. Pure Proof-/Invocation-Gates,
Keychain-Fehler-/Upgrade-Fixtures, Cache-Ownership-/Revision-Fixtures und ein verzögerter Extension-
Refresh über Lock/Re-Unlock sind als Testquellen ergänzt/angepasst, aber nicht gebaut/ausgeführt.
Die weiterhin offene signierte Matrix steht in `Docs/AutoFillLifecycleChecks.md`; `X-601` bis
`X-605` sind damit nicht vollständig erledigt.

**S-302 – Account-/Token-Persistenz und Ownership teilweise umgesetzt (2026-09-26):**
`TokenPair`, `StoredAuthAccount`, `TokenScope` und `PrivateAuthSessionStore` liegen SDK-frei in Data;
AuthFeature nutzt Übergangsaliase. Ein atomarer privater Keychain-Record ersetzt die unabhängigen
Account-/Token-Writes des erfolgreichen Passwort-/TOTP-Logins. Frische Anmeldung erzeugt eine
neue Authentication-UUID und Generation 1, auch beim gleichen Account. Ein fehlgeschlagener
Replacement-Write lässt den früheren privaten Account-/Token-Record erhalten; vorausgehender
Capability-Widerruf und Biometrie-/PIN-Key-Cleanup sind allerdings nicht rollbackbar.

Generationen werden nur innerhalb derselben Account-/Server-/Authentication-Lineage verglichen.
Shared Tokens tragen zusätzlich den aktuellen Unlock-ID; Grant-Schema 2 enthält die
Authentication-ID. Neue `.v2`-Keychain-Namen verhindern, dass Legacy-Reader frisch ausgestellte
Grants/Tokens unter den alten ungebundenen Namen lesen; alte Items werden beim Widerruf separat
entfernt. Fremde, alte oder ungebundene Tokenrecords dürfen weder App-Reconciliation
noch Extension-Zugriff autorisieren. Token-Mirroring erfolgt nur unter einem aktuellen passenden
Grant. Vor Re-Unlock werden eligible neuere Shared Tokens bewahrt; neue Grant-/Token-Publikation,
Reconciliation, private Writes sowie Lock-/Logout-Cleanup nutzen einen gemeinsamen synchronen
Prozesslock. Kein SDK-/Netzwerk-/Biometrie-Aufruf oder Await läuft darunter. Der Callback besitzt
eine auslaufende Transaction-Lease; entkommene Handles können danach nicht lesen/schreiben.
Fehlender App-Group-Container ist ein Produktionsfehler; In-memory-Fixtures wählen `.processOnly`
ausdrücklich. Es gibt keinen stillen Entitlement-Fallback mehr.

Ein neuer Login-Provider kann keine früheren Credentials lesen, bevor sein eigener Login
committed ist. Zurückkehrende Provider bleiben an ihre ursprüngliche Lineage gebunden.
Verspäteter Refresh einer früheren Anmeldung darf auch ohne expliziten Revoke keine neue
Anmeldung überschreiben. Async-Grant-Publikation, Biometrie-Enrollment und finaler App-Handoff
prüfen den Provider-Scope erneut; Biometrie-Key-/Flag-Schreiben prüft ihn im Storage-Lock.
Wenn bereits eine neuere passende Rotation vorliegt, meldet ein alter Refresh-Reject nicht
fälschlich die neue Generation ab.

Bei erfolgreichem Shared- und fehlgeschlagenem Private-Write bleibt die Shared Rotation zur
späteren Übernahme erhalten. Bei fehlgeschlagener Shared-Publikation wird die frische Rotation
trotzdem privat gespeichert; anschließend wird die obsolete Shared Capability unabhängig
widerrufen und der aktuelle Lookup als Fehler gemeldet. Ein späterer Lookup kann die dauerhaft
gespeicherten privaten Tokens nutzen. Fehler beim Widerruf werden weitergegeben. Unlesbare
Authority wird nicht als „fehlt“ interpretiert; Dual-Write-Failure und Crash-Recovery sind offen.
Generation-Overflow wird fail-closed abgewiesen. Persistenzwerte haben redigierte Beschreibungen.

**Upgrade:** Alte `auth.account`-Metadaten dürfen noch Recovery anzeigen, alte separate
`auth.tokens` autorisieren nie. Die Auth-UI fordert für Split-Sessions einen einmaligen neuen
Passwort-/2FA-Login, danach Unlock und Sync. Roh-/Schema-1-Grants sowie ungebundene Caches bleiben
abgewiesen. Ältere bereits laufende Extension-Binaries müssen beendet/neugestartet werden;
diese Migration kann ihren Code nicht nachträglich ändern. Keine neue Kompatibilitätsfunktion
oder Unlock-/Re-Prompt-Oberfläche wurde hinzugefügt.

**Nicht geschlossen:** Shared-Envelope-/Grant-Encoding und App-Group-Komposition liegen weiterhin
in VaultCore; Merge/Persistenzpolicy und Lock sind inzwischen in Data/SecurityStorage (siehe unten).
`DefaultAuthRepository`, Auth-State-Automat,
scoped PIN-/restliche Account-Settings-Transitions, persistente Refresh-/Cleanup-
Recovery und Presentation-Entkopplung fehlen noch. Lokale Actor-Deduplizierung verhindert keinen
gleichzeitigen App-/Extension-Netzwerk-Refresh; der Storage-Lock ist kein Servercommit-Lock.
Server-seitige rotierende Refreshes, Prozessabbruch und mehrfache Persistenz-/Revocation-Fehler
bleiben zu verifizieren. Die neue Ablage ist keine gemeinsame Transaktion über alle unabhängigen
Keychain-Items und keine Zeroization-/Audit-Garantie.

macOS-/iOS-Simulator-App-Builds inklusive Extensions sind grün. Neue Account-/Server-/Lineage-,
Legacy-/Atomic-Write-/Single-Write-Failure-/Overflow-/Late-Refresh-/Lock-Policy-Testquellen sind
ergänzt/angepasst, ausdrücklich nicht gebaut oder ausgeführt. Die Entscheidung und Fehlermatrix
stehen in `Docs/ADR/001-auth-token-ownership.md`; die signierte Matrix ist in
`Docs/AutoFillLifecycleChecks.md` erweitert. S-302/S-303 und alle bisherigen Release-Gates bleiben
teilweise/offen.

**S-301/S-302 – Gemeinsamer Token-Refresh-Kern live (2026-09-26):**
App und Extension nutzen `Data.TokenCoordinator` über den synchronen `TokenPersistence`-Port.
Der Auth-Provider ist nur noch Bootstrap-/SDK-Bridge; der Shared-Provider reicht an denselben
Actor-Kern mit festem Unlock-Proof weiter. `TokenRefreshing` liefert SDK-freie, redigierte
Rotationsergebnisse. OAuth-Form und flexibler Decoder haben eine Implementierung in Data bzw.
Networking; VaultCore bietet Übergangsaliase statt duplizierter Logik.

Der Coordinator besitzt einen unveränderbaren Scope und schließt nach Widerruf oder klassifiziertem
Ownership-Wechsel permanent. Keychain-Read-Fehler sperren den Lookup, erfinden aber keinen
Accountwechsel. Gleichzeitige Requests derselben Generation teilen ein Refresh-Task; UUIDs
verhindern, dass ein alter Waiter einen neueren Job löscht. Ein einzelner abgebrochener Waiter
erhält kein Token, bricht aber nicht den Refresh anderer Waiter ab. Nichtkooperative Arbeit kann
intern weiterlaufen oder das Return verzögern; obsolete Ergebnisse dürfen nicht persistieren.
Neuere passende Gewinner werden nicht überschrieben oder durch alte Rejects abgemeldet.
Commit und finaler Refresh-Output verlangen eine strikt höhere Generation. Overflow sperrt bereits
vor dem Netzwerkrequest. Fehlende Rotation behält den bisherigen Refresh-Token.

429/5xx sind auch bei irreführendem `invalid_grant`-Body retrybar. Nur explizites `invalid_grant`
auf 400/401 ohne Challenge schließt den Coordinator und ruft den App-Expiry-Handler höchstens
einmal auf. In der Extension ist das kein globales Grant-/Key-Cleanup. Erfolgsantworten werden
validiert; Retry-After lehnt NaN/Infinity/negative Zahlen ab und sperrt dieselbe lokale Generation
bis zum endlichen positiven Deadline, ohne Sleep oder automatische Wiederholung. Login zeigt
stabile Fehler statt roher Serverdiagnosen; 429/5xx lösen keine 2FA-Navigation aus.

Neue Fixture-Quellen behandeln Single-Flight, Cancellation, nichtkooperative Late-Responses,
Widerruf, Lineage-Wechsel, neuere Gewinner, stale Reject, Retry-After, Job-Wechsel, Overflow,
fehlende Rotation, Storage-/Transportfehler, malformed Payloads und Status-/Body-Vorrang.
Sie sind ausdrücklich nicht gebaut/ausgeführt. App-Builds ersetzen diese Verifikation nicht.
Die Implementierung/Restgrenzen stehen in `Docs/ADR/002-token-refresh-coordination.md`.

**Weiter offen:** Single-Flight ist nur Actor-lokal; kein Netzwerk-/Server-Rotation-Lock zwischen
Prozessen. Shared-Envelope-/Grant-Encoding und Komposition bleiben Legacy; optionale SDK-Callbacks kollabieren
Fehler zu nil. Durables Refresh-Intent/Cleanup-Recovery, Dual-Write-/Revocation-Failure,
AuthRepository/State-Automat und die signierte Matrix sind nicht abgeschlossen. S-302/S-303 und
Phase 3 bleiben teilweise; keine neue Vaultwarden-Kompatibilität wurde implementiert.

**A-205/S-302 – Persistenzpolicy und Lock migriert (2026-09-26):**
`Data.AppTokenPersistence` übernimmt die zuvor in AuthFeature liegende private/shared Merge-Regel,
Refresh-Commit und Preserve-before-Revoke bei Lock. Der App-Coordinator erhält diesen Adapter
direkt; `AuthFeature.AuthTokenPersistence` ist entfernt. `Data.ExtensionTokenPersistence` besitzt
den fixed-proof Lookup, Winner-Adoption und Successor-Commit der Extension. Beide verwenden
`SharedTokenTransacting`/`SharedTokenTransactionPort`, synchron ohne SDK-/Legacy-Envelope-Typen.
VaultCore stellt die vorhandenen Records/Grant-Operationen über dieselbe widerrufbare Transaction-
Lease bereit; sie ist nach dem Callback ungültig, auch bei Throw. Kein Await oder rekursiver Lock.

`SecurityStorage.CrossProcessFileLock` besitzt jetzt Mutex/File-Open/Permissions/`flock`/Release.
Die VaultCore-Hülle wählt nur App-Group-Container und Policy. Der physische Dateiname bleibt
`.vaultwarden-token-store.lock`, damit alte/neue Prozesse weiterhin dieselbe Datei sperren.
Fehlender Live-Container ist fail-closed; `.processOnly` ist weiterhin explizite Fixture-Injektion.
Leere/Traversal-/NUL-Dateinamen werden abgewiesen. Der Lock ist synchron und nicht reentrant;
er ist weder Netzwerk-Single-Flight noch Server-/OS-Transaktion.

Zwei Defekte sind korrigiert: Kandidaten werden vor Publikation in die Shared-Ablage validiert,
nicht erst beim späteren privaten Write; eine niedrigere gespeicherte Generation als die Request-
Baseline darf nicht als Gewinner zurückgegeben werden. Successor-Commit verlangt exakt +1.
Bei Dual-Write-Failure versucht Data weiterhin unabhängigen Widerruf und meldet zusätzlich,
ob auch dieser scheiterte (`TokenCommitRecoveryError` ohne Token-/Raw-Error-Payload). Der
ausgestellte Refresh-Token kann trotzdem verloren sein; kein Recovery-Journal ist implementiert.
Einseitige Fehler behalten die bereits gespeicherte Rotation in der erfolgreichen Ablage.

Neue pure Port-/Merge-/Lock-Fixture-Quellen und aktualisierte AuthFeature/VaultCore-Adapter-Fixtures
behandeln equal/older/newer Winner, Scope-Denial vor Shared-Reads, Grant/No-Grant, malformed und
Nicht-Successor-Kandidaten, einseitige/duale Writes, Cleanup-Failure, Lease-Ende und alte Unlocks.
Ausdrücklich nicht gebaut/ausgeführt. macOS-/iOS-Simulator-App-Builds sind grün; offizielle
Subrepos unverändert. Entscheidung/Restgrenzen: `Docs/ADR/003-token-persistence-ports.md`.
S-302/S-303 und Release-Gates bleiben offen/teilweise; Shared-Record-/Grant-Komposition,
typed Fehler-UI, durables Recovery und signierte Cross-process-Verifikation folgen noch.

**S-303 – Initialer Auth-Stateautomat angeschlossen (2026-09-27):** `Data.DefaultAuthRepository`
restauriert nur den atomaren privaten Account und besitzt die App-weiten getypten Zustände. Der
Coordinator restauriert vor dem Routing, validiert gespeicherten Account/Server und meldet
Unlock-Beginn/-Fehler; `AppSessionStore` bestätigt den Handoff nur, wenn derselbe Account noch
persistiert ist. Ablauf ist an die Runtime-ID gebunden. Lock/Logout veröffentlichen den gesperrten/
abgemeldeten Zustand vor dem throwing Keychain-Cleanup; die bestehende Recovery-UI lässt Cleanup
wiederholen. Neue Transition-/Scope-Denial-/Parallel-Unlock-Fixtures wurden ergänzt, aber nicht gebaut/ausgeführt. Das ist
absichtlich nur ein Teil von S-303: Credential-/2FA-/OAuth-/SDK-Unlock-Flows, AppModel-Ownership,
VaultRepository-Anbindung, Auth-Settings-Migration und das Entfernen des Sessionwrappers bleiben
offen. PIN-/Biometrie-Lese-/Schreibpfade prüfen nun Scope unter dem Shared-Storage-Lock, jedoch sind
die getrennten Keychain-Items nicht atomar und echte Lock-Races nicht verifiziert. Details:
`Docs/ADR/004-auth-repository-lifecycle.md`.

**S-306 – AppModel live angeschlossen (2026-09-27):** Der oben historisch noch offene
AppModel-Ownership-Schritt ist jetzt umgesetzt. Die beiden App-Einstiegspunkte halten je ein
gemeinsames Observable-Modell; Root, Settings und macOS-Menü lesen dieselbe getypte Authority.
`AppSessionStore` und seine direkten Lock-/Logout-Wrapper sind entfernt. Repository-Events werden
am Actor geordnet registriert; Restore-/Unlock-Failure-Events sind von explizitem Lock/Logout
unterscheidbar. Nach asynchroner Vorbereitung und Repository-Freigabe prüft der Handoff seine
Epoch, Runtime-ID, Persistenzfreigabe und den aktuellen Snapshot erneut. Lock/Logout nehmen die
sichtbare Freigabe sofort zurück, drainen verspätete Vorbereitung vor Temp-Cleanup und upgraden
einen laufenden Lock bei zusätzlicher Logout-Anforderung. Repository-Ablauf widerruft auch ohne
Legacy-Callback. Fehler halten den Wiederholungszustand geschlossen. Die bestehenden Feature-
Services laufen ausdrücklich noch über einen app-eigenen Adapter; Auth-Arbeit vor diesem Handoff
ist damit nicht automatisch cancellation-/lineage-sicher. Beide App-Schemes bauen ohne Testtargets;
die neuen Regressionstestquellen sind weder gebaut noch ausgeführt. Persistente Recovery,
Real-Device-/Multi-Scene-Verifikation und sämtliche Release-Gates bleiben offen. Details:
`Docs/ADR/005-app-model-ownership.md`.

**U-504 – Auth-Routen-Lifetime teilweise migriert (2026-09-27):** Die Neuerzeugung von Screen-
Stores bei jeder View-Auswertung ist entfernt. Der getypte Auth-Flow hält einen Store/Processor je
Route; Redraws erhalten Eingaben und Submit-Gates. Eine app-komponierte Repository-Instanz wird
in AppModel und AuthRootView injiziert, statt innerhalb des Features global nachgeschlagen zu
werden. Routenwechsel canceln Restore/Handoff und invalidieren alte Callback-IDs; aufgegebene
Pending-Provider werden widerrufen. Unlock-Logout verwendet den vollständigen AppModel-Cleanup.
App-Schemes bauen auf macOS und iOS Simulator; neue Fixture-Quellen sind nicht gebaut/ausgeführt.
Das ist keine vollständige Credential-Cancellation oder Persistenz-Rollback-Garantie: alte SDK-/
Netzwerk-Arbeit kann noch vor ihrem abgewiesenen Callback schreiben. Der folgende Persistenz-
Authority-Schritt begrenzt dies bei Lock/Logout/Lineage-Wechsel. AuthFlowModel/Domain-Use-
Cases, operationgebundene Commit-Authority, Secret Clearing und die reale Matrix bleiben offen.
Details: `Docs/ADR/006-auth-route-lifetime.md`.

**S-302/S-303/U-504 – Persistente Auth-Authority vor Handoff abgesichert (2026-09-27):** Fresh
Login bindet sich vor Prelogin/SDK/Netzwerk an den bestehenden Widerrufs-Epoch und vorherigen
Sign-in-Scope. Der Commit vergleicht beides unter demselben Speicher-Lock, validiert Kandidaten
vor Grant-Widerruf und liefert Record plus neuen Epoch gemeinsam zurück. Lock/Logout oder ein
anderer Sign-in verwerfen späte Ergebnisse; Same-Lineage-Refresh bleibt erlaubt. Returning-Unlock
capturt den Epoch vor seiner ersten Suspension. Provider, AutoFill-Sharing, Biometrie-Enrollment
und AppModel-Handoff prüfen diese unveränderbare Freigabe erneut; sie dürfen nach Lock nicht
einfach den neuen Epoch übernehmen. PIN-Cancellation wird nicht mehr als falscher PIN gezählt,
und post-crypto Persistenz-/Authority-Fehler verbrauchen kein PIN-Budget. Passwort-/TOTP-Felder
werden nach Erfolg/Cancellation geleert. Neue Fake-/Race-Fixtures sind nur Quelltext, nicht
gebaut/ausgeführt. Dies ersetzt weder operationgebundene Route-Cancellation, Commit-Rollback,
durable Recovery noch die signierte Matrix. Die Keychain-Recovery kann lokale Sign-in-Daten
ausdrücklich nach Bestätigung über AppModel-Logout entfernen; fehlgeschlagener Handoff baut
eine neue Anmeldung statt einer toten Enrollment-Route auf. Details:
`Docs/ADR/006-auth-route-lifetime.md`.

**V-401/V-402/V-403/U-503/V-405 – größerer Live-Vault-Block (2026-09-27):** Eine sessiongebundene,
app-komponierte Repository-Instanz ist jetzt im Vault-Pfad live. Sync ist Single-Flight; Sync und
CRUD/Attachment-Mutationen laufen FIFO. Die UI patcht keine eigenen SDK-Cipher-Arrays mehr:
Details, Folder/Collections, Drafts, TOTP und Passkey-Anzeige sind Domain-basiert, SDK-Backing und
Crypto bleiben im Adapter. Erfolgreiche Mutationen koppeln Snapshot, verschlüsselte Projektion
und OS-Identitäten; bestätigte Writes mit nachfolgendem lokalen Fehler verlangen Sync statt
erneuter Erstellung. Cache-/OS-Fehler und stale Inhalte haben Reparaturhinweise; der lokale letzte
Sync-Zeitpunkt wird angezeigt. Lock leert sofort, joint Cleanup und drainiert alte OS-Writes.
App-Projektion/Extension-Upsert verwenden denselben Prozess-Lock und feste Proof-/Cache-Fences.
Das existierende Extension-Format bleibt mit monotonem Zusatzfeld kompatibel; Collection-/Secret-
Permissions werden vor Export geprüft. Keine neue Kompatibilitätsfunktion/Server-API.

Das ist **kein abgeschlossener Phase-4-Gate**: Extension-Reader/Passkey-Serverpfad bleiben
transitional, X-604 bleibt offen, Transfers bleiben RAM-basiert und serverseitige Conditional
Writes fehlen. U-503 verwendet noch den bestehenden Store statt abgeschlossener Observation-
Migration. Der Nutzer hat ausführliche Tests bis zur nächsten Freigabe zurückgestellt; alte
VaultProcessor-/State-Testquellen müssen später auf Repository-Fakes portiert werden. In diesem
Block wurden keine Testtargets gebaut oder Tests ausgeführt. Architektur/Restgrenzen:
`Docs/ADR/007-live-vault-repository.md`; ausführliche Prüfschulden:
`Docs/Verification.md`. App-Kompilierung ersetzt keine dieser Prüfungen.
Der finale Block kompiliert als macOS- und iOS-Simulator-App inklusive Extension ohne Signing;
`git diff --check` ist sauber und die offiziellen Subrepos sind unverändert.

**Verifikation nach Portierung (2026-09-27):** VaultProcessor-/State-Tests sind auf Repository-
Fakes und Domain-Snapshots umgestellt; Crypto-/HTTP-Assertions prüfen den tatsächlichen
`SDKVaultSessionSource`. Neue Fixtures prüfen bestätigte Writes trotz UI-Cancellation,
Projektionsfehler, FIFO und Lock sowie den OS-Write-Drain. Der tatsächlich ausgeführte Testlauf
hat unerlaubten Restore nach fehlgeschlagenem Logout und veraltete Attachment-Bestätigungen
aufgedeckt und behoben. Save verhindert nun Cancel/Sheet-Dismiss statt Rückgängigmachen eines
bereits eingereichten Serverwrites zu suggerieren. Testkompilierungsfehler sind korrigiert.
Alle neun lokalen Pakete bestehen mit 459 Tests; der bestehende Swift/Rust-FFI-Smoke-Test ist
enthalten und wurde ohne Änderung der SDK-Quellen ausgeführt. Der kritische Block mit 27 Tests
besteht fünfmal. Beide unsigned App-/Extension-Builds sind grün. **Kein gesamter Phase-/Release-
Gate wird dadurch geschlossen.** Echte Server, signierte Geräte, OS-Context und konkurrierende
App-/Extension-Prozesse sind nicht verifiziert. Siehe `Docs/Verification.md`.

**U-501 – Settings-Migration abgeschlossen (2026-09-27):** `SettingsFeature` hängt nur noch von
`Domain` ab; `AuthenticatedSession`, `AuthFeature`, SDK, Store/Processor sowie lokale HTTP-/Timeout-
Live-Services sind aus der Settings-Presentation entfernt. PIN und Timeout verwenden injizierte
Ports, Gerätezugriffe laufen über einen runtime-scoped Data-Adapter. Timeout-Policy, UserDefaults-
Persistenz und appweiter Watchdog liegen in Domain/Data/AppFeature. Die Settings-Oberfläche zeigt
Bestätigung, Busy-State und sichtbare Fehler statt stiller Writes; ein nicht lesbarer Timeout wird
bei fälligem Ablauf fail-closed mit Lock und Fehlerbanner behandelt. Settings-Suite: 23 Tests;
AppModules-Suite: 158 Tests; beide unsigned App-Schemes bauen (macOS universal, iOS Simulator
arm64). Keine offiziellen SDK-/Vaultwarden-Subrepos geändert.

**U-502 – Send-Migration abgeschlossen (2026-09-27):** `SendFeature` besteht aus einer Domain-only
Presentation (`SendModel`, `SendState`) plus injiziertem `SendRepository`; HTTP, Cache und Sitzung
liegen in Data, Send-Wire-/Kryptoabbildung im SDK-Adapter. Direkte SDK-, Store-, Processor- und
Coordinator-Abhängigkeiten sowie alte Send-Services/DTOs sind aus dem Feature entfernt. 4
SendFeature-Tests und 175 AppModules-Tests bestehen, einschließlich Repository- und
SDK-Kryptotests. macOS- und iOS-Simulator-Schemes bauen unsigned. Dateiübertragung ist noch
RAM-basiert (D-016/F-701); echte Vaultwarden-Server-Uploads und reale Session-/OS-Races bleiben
Release-Verifikation, kein neu eingeführtes Kompatibilitätsfeature.

**U-503 – Vault-Model-Zwischenschritt (2026-09-27):** `VaultProcessor`/`StateProcessor` wurden
durch `@Observable VaultModel` ersetzt; Root hält das Model in `@State`, Views binden an dessen
Observation, und die direkte `AppArchitecture`-Abhängigkeit ist aus `VaultFeature` entfernt. State,
Actions, Effects und Model liegen jetzt unter `Models`. Eine neue Regression prüft echte
Observation-Änderungen. Beim Lauf der Source-Tests fiel auf, dass `.completeFileProtection` auf dem
macOS-Anhang-Downloadpfad nicht geschrieben werden kann; iOS behält den Schutz, macOS schreibt
atomar in das restriktive Temp-Verzeichnis. Alle 115 VaultFeature-Tests sowie beide unsigned
App-Schemes (macOS und iOS Simulator arm64) bestehen. `VaultFeature` hängt aber weiterhin als
Legacy-Package im App-Graph.

**U-503 – erstes Presentation-Target (2026-09-27):** `VaultFilter` wurde in
`Packages/AppModules/Sources/VaultFeature` verschoben und ist nun der erste produktive Typ im
`AppModules.VaultPresentation`-Target. Die Legacy-Feature- und Testtargets referenzieren das Modul
explizit; neue Modul-Tests prüfen Favorite-, Folder-, Item-Type-, Collection- und Titelverhalten.
Die zwei Filtertests und alle 175 AppModules-Tests bestehen. Das komplette VaultFeature-Target
baute und bestand alle 115 Tests im nicht parallelen Lauf. Ein voriger paralleler Lauf hing ohne
abschließendes Testergebnis und wurde abgebrochen; mit `--no-parallel` lief derselbe Testsatz in
0,146 Sekunden durch. Beide unsigned App-Schemes (macOS und iOS Simulator arm64) bauen auch nach
der Moduländerung. Das neue Target ist damit kein Platzhalter mehr, aber noch kein vollständiges
Live-Feature: Root, Views, State, Model und Composition verbleiben im Legacy-Package.

**U-503 – Live-Model im Zielmodul (2026-09-27):** `VaultModel`, `VaultState`, `VaultAction` und
`VaultEffect` wurden anschließend nach `AppModules.VaultPresentation` verschoben. Das Model enthält
keine konkrete `SensitiveTemporaryFileStore`-Abhängigkeit mehr; der Legacy-Root adaptiert den
Storage-Actor auf eine injizierte asynchrone Cleanup-Closure. State ist außerhalb des Moduls nur
lesbar, die Legacy-Views senden Änderungen über typisierte Actions. `VaultFeature` bleibt vorerst
als UI-/Composition-Adapter und Testpaket bestehen. Das komplette Paket baute; alle 115 VaultFeature-
Tests liefen mit `--no-parallel` erfolgreich. 175 AppModules-Tests plus die zwei Filtertests und
beide unsigned App-Schemes (macOS und iOS Simulator arm64) bestehen nach diesem Model-Schnitt.

**U-503 – Live-Presentation im Zielmodul (2026-09-27):** `VaultRootView`, adaptive Split-/Compact-
Layouts, Sidebar, Item-Liste, Detail, Editor, Generator und die Pasteboard-Environment-Erweiterung
liegen jetzt ebenfalls im `AppModules.VaultPresentation`-Target. Alte `VaultCore`-View-Imports sind
entfernt; Sheet-Größen verwenden `SharedUI.platformMinSize`. Der App-Root injiziert den sicheren
Cleanup-Actor als Closure und bindet die direkten `VaultPresentation`-/`SecurityStorage`-Produkte
für macOS und iOS in die Xcode-App-Targets ein. Der SwiftPM-Build fand zunächst zwei veraltete
`macOSMinSize`-Aufrufe; diese wurden auf die plattformneutrale SharedUI-API umgestellt. Danach
bestanden 115 VaultFeature-Tests, 175 AppModules-Tests plus zwei Filtertests und beide unsigned
App-Schemes. `VaultFeature` verbleibt noch für Data-/SDK-/AutoFill-Service-Bridges und Session-
Cleanup, nicht mehr für die Vault-UI. Danach wurde der dünne `VaultSensitiveData`-Wrapper aus dem
Legacy-Target entfernt: AppComposition öffnet und säubert `SensitiveTemporaryFileStore.shared`
direkt am Composition-Rand. Die alte VaultFeature-Abhängigkeit auf SecurityStorage sowie die
nicht mehr genutzten Abhängigkeiten auf SharedUI/VaultPresentation wurden aus dem Produkt-Target
entfernt; Testtargets behalten ihre gezielten Testabhängigkeiten. Beide App-Schemes bauen auch
nach dieser Lifecycle-Verschiebung. Die fünf konkreten `SensitiveTemporaryFileStore`-Tests wurden
in `AppModulesArchitectureTests` verschoben; die Model-Tests verwenden eine Cleanup-Testclosure und
der VaultFeature-Testsatz braucht keine SecurityStorage-Abhängigkeit mehr. Damit bestehen jetzt
110 Legacy-Vault-Tests und 180 AppModules-Tests (plus zwei Filtertests).

**U-503 – AutoFill-Brücke aus dem App-Target gelöst (2026-09-27):** Das bestehende verschlüsselte
AutoFill-Cachemodell und sein bidirektionaler Codec liegen jetzt in `AppModules.AutoFillData`; das
Encoding-Protokoll liegt als Vertrag in `AutoFillContract`. `SessionVaultProjection` behält die
Session-/SharedToken-Komposition am App-Rand, verwendet aber keinen `VaultFeature`-Typ mehr. Die
macOS-/iOS-Haupttargets verloren ihre direkte `VaultFeature`-Produktabhängigkeit; die dauerhafte
Quelle dafür ist `project.yml`, danach wurde XcodeGen ausgeführt. Geprüft: 182 AppModules-Swift-
Testing-Tests plus zwei Filtertests, 110 VaultFeature-Tests, unsigned macOS-arm64- und iOS-Simulator-
App-/Extension-Builds sowie `git diff --check`. Das Legacy-Paket bleibt noch für Extension-Services
im Projektgraphen. Keine offiziellen Vaultwarden-/Bitwarden-Subrepos geändert.

**U-503 / X-601 – Legacy-Vault aus dem Produktionsgraphen entfernt (2026-09-27):** URI-Matching,
PSL-Parser und die unveränderte gepinnte Suffix-Liste liegen jetzt in AutoFillData. Der Matcher
verwendet den SDK-freien `AutoFillURIMatchMode`; die vorhandenen SDK-Modi werden am Adapterrand
übersetzt. `LegacyAutoFillCacheStore` besitzt den Reader und gefenceten Upsert. App-Group-Pfad und
Autorisierung sind injiziert; `SharedTokenStore` implementiert den AutoFillContract-Port und
prüft den festen Unlock-Proof sowie gebundene Tokens innerhalb seines bestehenden Prozess-Locks.
Die Cache-UUID/Projektionsrevision wird dort vor dem atomaren Dateiaustausch erneut geprüft.
macOS verwendet atomare Writes ohne iOS-Dateischutzoption; iOS behält Complete File Protection.
Neue Store-Fixtures prüfen erfolgreiche Mutation und unveränderte Bytes bei altem Unlock,
veralteter Cache-UUID, anderem Server, erschöpfter Revision, fehlender Datei und Authority-Fehler.
Der konkrete SharedToken-Port verweigert Writes bei anderem Unlock, fehlenden Tokens und Widerruf.

Der Cipher-HTTP-/Wire-Service liegt nun als `SDKCipherService` im Adapter; Extension-Callbacks
nutzen `SDKVaultAccessPolicy` und die bereits migrierte Passkey-Factory direkt. Matcher-, reine
Cache- und Factory-Tests wurden nach AppModules verschoben; die Credential-Identity-Regression
bleibt beim alten Service. Alle VaultFeature-Imports der App/Extension sowie beide Extension-
Produktabhängigkeiten und der Paketverweis sind aus `project.yml` entfernt; XcodeGen wurde danach
ausgeführt. Die alten VaultFeature-Quellen sind noch ein separat testbares Übergangspaket, kein
Teil des Produktionsgraphen. README, ADR 007, Lifecycle-Prüfliste, Resource-Updatepfad und
Lizenznachweis beschreiben den aktuellen Stand.

Verifiziert: 212 AppModules-Swift-Testing-Tests plus zwei XCTest-Filtertests, 31 VaultCore-Tests,
82 verbleibende VaultFeature-Tests sowie unsigned macOS-arm64- und iOS-Simulator-App-/Extension-
Builds. Die PSL-Prüfsumme bleibt `7333192f818588d9d0044d27d67210c782acd6d87cf71f54a00dfa20a561cfc9`.
Kein gesamtes Release-Gate ist damit erfüllt; reale Server, signierte Geräte und parallele Prozesse
sind weiterhin offen. Offizielle SDK-/Vaultwarden-Subrepos bleiben unverändert.

**U-503 / U-501 / U-502 / C-901 bis C-903 – drei Feature-Pakete aufgelöst (2026-09-27):**
VaultModel-/State-/Live-SDK-Source-/Cipher-/FIDO2-Tests und ihre Fixtures liegen jetzt bei
AppModules. Sync-Regressionen verwenden SDKVaultSessionSource: Decryption und Org-Key-Reihenfolge,
fehlende Tokens, HTTP-Fehler, partielle Antworten und doppelte IDs. Alte Attachment-Assertions
sind mit den vorhandenen Live-Source-Tests zusammengeführt; zusätzliche Source-Fixtures prüfen
relative/same-origin Downloads, fremde Origins vor jedem Blob-Request, fehlende Tokens und sichere
Multipart-Dateinamen. Metadata-/Upload-Tests prüfen V2-Endpunkt, verschlüsselten Dateinamen/Key,
Ciphertext-Größe/-Bytes, Bearer-Header und Redirect-Reject. Die Identity-Regression geht jetzt durch
den echten SDK-Export und Domain-IdentityMapper: normale Password-/TOTP-/Passkey-Identitäten werden
erzeugt, Re-Prompt/hidden secrets exportieren weder Cache-Records noch OS-Suggestions.

Die nur noch vom alten Testsatz verwendeten Sync-/Attachment-/Identity-/Cache-Writer-Services,
SDK-/DTO-/Generator-Aliases und ungenutzten Service-Spies sind gelöscht. Kein VaultFeature-Paket
bleibt als Parallelimplementierung übrig. Send- und Settings-Presentation liegen einschließlich
der bisherigen Model-Tests in ihren AppModules-Targets. SettingsProcessor-Dateinamen sind an den
bereits verwendeten SettingsModel-Typ angepasst; persistierte Preference-Keys bleiben unverändert.
Die leeren Send-/Settings-Scaffold-Typen und drei alte Feature-Manifeste sind entfernt.
`project.yml`, App-Imports, Package-Testscript, README und ADR 007 sind auf den neuen Graphen
umgestellt; XcodeGen wurde ausgeführt. Sechs lokale Pakete verbleiben, nicht die finalen zwei.

Verifiziert: 315 AppModules-Swift-Testing-Tests in 41 Suites plus zwei XCTest-Filtertests bestanden;
beide neu generierten unsigned App-/Extension-Builds (macOS arm64 und iOS Simulator) bestanden.
Die höhere Zahl an Tests im Paket ist überwiegend zusammengeführte bestehende Abdeckung, kein neues
Kompatibilitätsfeature. Der standardmäßige SwiftPM-Xcode-Backend-Lauf scheiterte nach Korrektur
der portierten Initializer-Reihenfolge bei SDK-Archivkopien an `errno=28` (Speicherplatz).
Das native SwiftPM-Backend baute und führte den vollständigen betroffenen Testsatz erfolgreich
aus. Diese lokale Speicherplatz-Umgehung ist deprecated und keine neue Repository-/CI-Vorgabe.
Aktuelle Build-Ergebnisse und Reproduktionsbefehl: `Docs/Verification.md`.
Es wurden keine offiziellen SDK-/Vaultwarden-Subrepos verändert und kein Release-Gate als
abgeschlossen markiert.

**S-302 / A-207 / C-901 – Shared-Auth-Persistenz aus VaultCore gelöst (2026-09-27):**
`SharedTokens`, `SharedTokenStore`, `SharedTokenTransaction`, `SharedTokenProvider` und
`SharedAutoFillUnlock`/`SharedAutoFillUnlockStore` liegen jetzt in Data. Der synchrone,
nicht-Sendable Transaction-Lease bleibt beim Callback-Ende unwirksam; Proof-/Sign-in-/Generation-
Checks, Epoch-Widerruf und Cache-Autorisierung sind unverändert erhalten. Keychain und Container
werden explizit injiziert. Data liest dafür weder Bundle-/Team-Konfiguration noch App-Group-
Entitlements. Fehlender Container scheitert vor jedem Keychain-Zugriff; `.processOnly` bleibt
eine explizite Fixture-Policy, kein Produktionsfallback.

`SharedAccountInfo` und unveränderte Keychain-Wire-Namen liegen SDK-frei in AutoFillContract.
SDK-KDF-/Environment-Mapping ist im Adapter. Das Mapping verwendet geprüfte `UInt32(exactly:)`-
Konvertierungen, lehnt unbekannte KDF-Typen ab und erfindet bei fehlendem Server keine Umgebung.
Beschreibungen/Debugbeschreibungen von Account-Metadaten und Unlock-Grant sind redigiert.
JSON-Felder, v2-Schema, UUID-Fences und `.vaultwarden-token-store.lock` bleiben gleich.
VaultCore enthält für diesen Pfad nur noch den Übergangs-Kompositionsrand `SharedAppGroup`.
AuthKeychainStore importiert VaultCore nicht mehr; Live-Auth, App-Projektion und Extension-
Komposition liefern die gleiche bestehende Keychain/Container-Konfiguration an Data.
Die Extension importiert Data ausdrücklich; `project.yml` und XcodeGen-Graph sind aktualisiert.

27 bisherige Core-Tests sind nach AppModules verschoben. Acht neue Methoden prüfen injizierten
echten Dateipfad/0600/Wire-Namen, fehlenden Container vor jeder Keychain-Operation, Revocation,
KDF-Grenzen/Defaults, unbekannte Typen, fehlenden Server und Redaction. Eine vorhandene Biometrie-
Testfixture wirft Setupfehler jetzt, statt sie zu verschlucken; ihre unbenutzte-`try?`-Warnung ist
entfernt. Ausgeführt und bestanden: 350 AppModules-Swift-Testing-Tests in 44 Suites plus zwei
XCTest-Tests, 109 AuthFeature-Tests und vier verbliebene VaultCore-Tests inklusive des bestehenden
Keychain-Smokes. Nach XcodeGen bestehen beide unsigned App-/Extension-Schemes (macOS arm64 und
iOS Simulator). Das native SwiftPM-Backend bleibt nur lokale Speicherplatz-Umgehung.
Prüfbefehle und offene Gates stehen in `Docs/Verification.md`.

Nicht abgeschlossen: Passwort-/TOTP-Ausführung im Repository, Auth-Observation-Presentation,
SDK-freier Session-Handoff und vollständige App-Group-/PIN-/Biometrie-Komposition. Reale parallele
App-/Extension-Refreshes, Prozessabbruch und durables Recovery bleiben offen. Keine zusätzliche
Vaultwarden-Kompatibilitätsfunktion und keine Änderungen an offiziellen Subrepos.

**U-504 / U-506 / A-204 / C-902 bis C-903 – Auth-Models und zwei Legacy-Pakete aufgeräumt (2026-09-27):**
Server Setup, Login, TOTP, Unlock und Biometrie Enrollment verwenden nun konkrete MainActor-
Observation-Models ohne Store-/Processor-Vererbung oder zweite State-Kopie. Der typed AuthCoordinator
hält ein Model je Route; AuthFlowView enthält die Darstellung. Die App erzeugt AuthServices einmal
mit injizierten Netzwerk-, privaten/geteilten Keychain-, Container- und Plattformclients; Screens,
Repository und PIN-Einstellungen verwenden dieselbe Store-Konfiguration. AuthSession und die
statischen Live-Factories in AuthDependencies/PinEnrollment sind entfernt.

AuthOperationLifetime hält eine Operation je Screen, dedupliziert und propagiert Caller-Cancellation.
Navigation/UI Exit retiriert den Screen vor Ersatz, cancelt seinen Task und leert Passwort/PIN/Code.
Die private optionale TOTP-Context-Referenz wird entfernt; Back-Callbacks halten keine Passwort-/
Hash-/Client-Contexts. Späte Fehler nach nicht kooperativer Suspension setzen keinen alten UI-Fehler
oder Secret-State wieder ein. Provider bleiben bei erfolgreicher Übergabe dem SessionRuntime
zugeordnet; UI-Abbau widerruft einen accepted Handoff nicht. Ein konkreter Nachreview-Defekt ist
behoben: später Nicht-Cancellation-Fehler aus einem abgebrochenen PIN-Crypto-Call zählt keinen
Fehlversuch und deaktiviert nicht das Enrollment. Der gated Regressionstest besteht.

AppArchitecture und NetworkingKit sind nach Auflösung aller Produktionsconsumer vollständig
aus Sources/Manifesten/project.yml/Testscript entfernt. Der bestehende HTTP-Smoke prüft jetzt
Networking.URLSessionHTTPClient; sein URLProtocol-Fake hat keine mutable globale Response.
Die alten generischen Store-Tests sind mit ihrer gelöschten Implementierung entfernt; Retention,
direkte State-Writes und Observation sind durch reale Auth-Model-Tests abgedeckt. Vier lokale
Pakete verbleiben. App-Komposition deklariert Networking/SDK-Adapter direkt; XcodeGen wurde ausgeführt.

Ausgeführt und bestanden: 126 Auth-Tests in 13 Suites (18 neue Methoden) sowie 351 AppModules-
Swift-Testing-Tests in 45 Suites plus zwei XCTest-Tests (ein portierter Transporttest). Beide
unsigned macOS-arm64-/iOS-Simulator-App-/Extension-Builds bestehen auch nach dem PIN-Nachreview.
Ein class-only Biometrie-Testdouble und das scoped PIN-Enrollment-Testsetup wurden korrigiert,
die portierten Auth-Assertions nicht abgeschwächt. Unveränderte Core-/SDK-Testtargets wurden in diesem Block nicht erneut
ausgeführt; keine neue Gesamtbaseline behauptet. Ignorierte Caches liegen wiederverwendbar auf
dem Workspace-Volume statt der fast vollen Systempartition. Prüfbefehle: Docs/Verification.md.

U-506 ist erledigt, U-504/S-303 bleiben teilweise: SDK-Contexts und der Session-Callback sowie
Credential-Ausführung sind noch im AuthFeature-Übergangspaket, nicht vollständig in Domain/Data/
AuthPresentation. Cancellation ist kein Rollback bestätigter Persistenz und keine Zeroization-
Garantie. Reale Server, signierte Geräte, Multi-Window und parallele App-/Extension-Prozesse sowie
durables Recovery bleiben offen. Keine neuen Kompatibilitätsfunktionen oder Änderungen an offiziellen
Bitwarden-/Vaultwarden-Subrepos; kein gesamtes Release-Gate geschlossen.

**C-901 bis C-903 / S-303 / P-802 – VaultCore vollständig aufgelöst (2026-09-27):**
Alle Core-Consumer und das Package-Manifest sind aus Quellen, Auth-Manifest, project.yml und
Testscript entfernt. Drei lokale Pakete verbleiben: AppModules, AuthFeature und VaultwardenSDK.
Die gemeinsame App-/Extension-Konfiguration liegt in `Composition/SharedAppGroup.swift` und wird
von allen vier Targets kompiliert. Shared-Wire-Namen, Speicherformate und Lock-Dateiname bleiben
unverändert; offizielle Bitwarden-/Vaultwarden-Quellen wurden nicht angefasst.

`Data.AuthenticatedSession` assembliert den typisierten Domain-Account und eine bereits gekapselte,
widerrufbare SDK-Resource gegen den validierten persistenten Token-Scope. Kein öffentlicher roher
SDK-Client, optionaler Token-Callback oder impliziter Live-HTTP-Client bleibt an dieser Grenze.
HTTP wird für den Vault-Source explizit injiziert; alle Session-Kopien teilen dieselbe Lifetime.
Account-/Server-Mismatch und bereits widerrufene Ressourcen scheitern vor Handoff.
Wichtig für vorhandene Installationen: Der Storage-/Cache-Owner behält die exakte persistierte
Server-URL, auch mit abschließendem Slash. Domain-Normalisierung ändert nur Transport-Routen,
nicht die bestehende Shared-Grant-/Cache-Identität. Ein Regressionstest deckt dies ab.

Domain besitzt jetzt das einzige Servermodell und die Credential-Server-Policy. HTTPS ist erlaubt,
HTTP nur für explizite Debug-Loopbacks; Userinfo, Query, Fragment, fehlender Host und ungültige Ports
werden abgewiesen. Auch Decode validiert die bestehenden vier URL-Felder. Session-Assembly und
AutoFill-SDK-Bootstrap erzwingen die Policy. Nicht verwendete Core-Environment-/SDK-Aliases,
Sizing-Duplikate und die ungenutzte Legacy-Keychain-API sind entfernt; keine neue Serverfunktion.

Ausgeführt und bestanden: 364 AppModules-Swift-Testing-Tests in 48 Suites plus zwei XCTest-Tests,
128 AuthFeature-Tests in 13 Suites, XcodeGen sowie unsigned macOS-arm64- und generische iOS-
Simulator-Builds inklusive beider Extensions. Die vier verbliebenen Core-Tests sind nach AppModules
portiert und ausgeführt, einschließlich des echten synthetischen Keychain-Roundtrips. Elf neue
Testmethoden prüfen URL-/Decode-Policy, Session-Scope/-Lifetime, HTTP-Injektion und ServerSetup.
Eine anfängliche neue Request-Assertion wurde auf den bestehenden Sync-Query
`excludeDomains=true` korrigiert; kein produktiver Netzwerkpfad wurde dafür geändert.
Der SDK-FFI-Smoke wurde in diesem Block nicht erneut ausgeführt. Details und Befehle stehen in
`Docs/Verification.md`; die inkrementellen lokalen Build-Caches bleiben erhalten.

S-303/U-504 bleiben teilweise: Credential-/SDK-Orchestrierung liegt noch in AuthFeature und der
Auth-Callback liefert eine Data-Assembly statt eines Domain-only Ergebnisses. Stand dieses Blocks: P-801 blieb offen;
SharedAppGroup enthält weiterhin den bisherigen persönlichen Team-Prefix als Fallback;
xcconfig-/Bundle-/Entitlement-Validierung ist nicht umgesetzt. Vollständige Release-/ATS-Matrix,
signierte Geräte, reale Server, Cross-process-Refresh und durables Recovery sind nicht verifiziert.
Kein gesamtes Release-Gate wird durch diesen Block geschlossen.

**P-801 / S-306 – Contributor-Konfiguration und Startup-Komposition lokal umgesetzt (2026-09-27):**
Base-/Debug-/Release-xcconfig sowie ein Local-Beispiel sind hinzugefügt; echte Local.xcconfig ist
ignoriert. project.yml enthält keine persönliche Team-ID mehr. Alle vier Targets beziehen Bundle-
Familie, App Group, private/shared Keychain-Namen, App-ID-Prefix und Version aus denselben Werten.
Der Swift-Team-Fallback ist gelöscht; Contributor ändern nur Local, nicht Swift oder project.yml.
Default-Storage-IDs, Wire-Namen, JSON-Schema und Lock-Dateiname bleiben unverändert.

SecurityStorage.AppStorageConfiguration validiert injizierte Werte, Bundle-Familie und die
aufgelöste Container-URL. Composition bleibt alleiniger Bundle-/FileManager-Lookup. Ein Prefix
braucht exakt zehn Großbuchstaben/Ziffern und abschließenden Punkt, identisch zu den Entitlements;
keine stille Separator-Normalisierung. Fehlende/unexpandierte/ungültige Werte und ein fehlender
Container werden vor der Erstellung von Credential-Stores abgewiesen. Private/shared Services
müssen verschieden sein. Neue Contributor-Identifier wählen getrennten Speicher, keine Migration.

AppComposition ist nun eine einmal erzeugte Instanz statt statischer live Dependencies. Beide App-
Entrypoints behalten einen typed AppStartup mit derselben Composition/AppModel-Instanz für Root,
Menü und Settings. Ein Konfigurationsfehler zeigt Recovery vor Auth/Restore, ohne Credential-Cleanup;
Debug nennt nur den Schlüssel, Release eine stabile Build-Reparaturanweisung. Scene-/Timeout-
Events gehen nur an konfigurierte Modelle. Extension-Shared-Store-Factories werfen vor Keychain-
Zugriff; Cache-Reader und Autorisierungsstore erhalten denselben einmal aufgelösten Container.

Ausgeführt und bestanden: 374 AppModules-Swift-Testing-Tests in 49 Suites plus zwei XCTest-Tests
und 128 AuthFeature-Tests in 13 Suites. Zehn neue Testmethoden mit parametrisierten Fällen prüfen
Default-/Contributor-Identifier, Prefix-/Entitlement-Zuordnung, fehlende/kaputte Werte, fremde
Bundles, Namespace-Trennung, Container-Denial und wertfreie Fehlertexte. XcodeGen und beide
unsigned App-/Extension-Builds bestehen. Die vier tatsächlichen Produkt-Info.plists samt eingebetteten
Extensions sind auf je acht expandierte Identity-/Storage-/Versionswerte geprüft und stimmen überein.
Scripts/verify-configuration.swift prüft Debug und
Release für alle vier Targets: Default-IDs mit synthetischem Team sowie vollständig abweichende
Contributor-IDs mit separatem App-ID-Prefix bestehen; fehlendes Team und Prefix ohne Punkt
scheitern ausdrücklich mit Exit 1. Keine Local-Datei, kein Signing und keine Credentials verändert.

Konfigurationscode ist lokal abgeschlossen; P-801 bleibt wegen des offenen vorgelagerten Quality
Gate 5 und der signierten Container-/Keychain-/Provisioning-Matrix teilweise. Eine Formatprüfung
oder erfolgreiche Container-Auflösung beweist keine signierte Berechtigung. Kein App-UI-Launch,
signierter Prozess, realer Server oder Geräte-Smoke in diesem Block; keine Sandbox-/Hotkey-
Distribution-Entscheidung (P-803). SDK-FFI-Smoke nicht erneut ausgeführt, offizielle Subrepos
unverändert. Reale Release-Gates und Auth-Command-/Handoff-Migration bleiben offen.
Anleitung: Docs/ContributorConfiguration.md; Entscheidung: Docs/ADR/008-build-configuration.md;
ausgeführte Befehle und Resultate: Docs/Verification.md.

**A-202 / A-203 / A-206 / S-303 / U-504 – Auth-Transporte und KDF-Grenze migriert (2026-09-27):**
Prelogin sowie Passwort-/TOTP-HTTP inklusive OAuth-Form-Builder, Wire-DTOs und Device-Metadaten
liegen jetzt in Data. Die alten AuthFeature-Dateien sind entfernt, nicht per Kompatibilitäts-Alias
behalten. Domain besitzt PreloginService, KeyDerivationParameters und AuthFlowError;
SDKAuthenticationService und SDKVaultUnlockService nehmen Domain-Parameter entgegen und
konvertieren erst im SDK-Adapter. Endpoints, Wire-Namen, connector, Refresh-Delegation und
bestehende Integer-/String-2FA-Provider-Decodierung bleiben erhalten. Credential-HTTP prüft URL-
Policy und Cancellation vor Requests sowie nach nicht kooperativen Responses; Data-Token-/Code-/
Device-Beschreibungen sind redigiert. Keine neuen Server-/Kompatibilitätsfunktionen.

Drei reale KDF-Defekte sind behoben: ungeprüfte Int->UInt32-Konversionen konnten trapen bzw.
unbekannte Algorithmen still auf PBKDF2 fallen; fehlende Token-Metadaten konnten andere Werte
als den tatsächlichen Prelogin-KDF speichern; die Shared-Freigabe eines Legacy-Argon2-Accounts
ohne Iterationswert konnte fälschlich den PBKDF2-Default 600.000 publizieren. Ein gemeinsamer
SDKKeyDerivationMapper weist negative/nullgroße/überlaufende und unbekannte Werte ab und
verwendet nur für fehlende Werte die vorhandenen algorithmusspezifischen Defaults. Token-
Metadaten müssen vor SDK-Unlock/Persistenz mit den tatsächlichen Prelogin-Parametern übereinstimmen;
fehlende Felder übernehmen diese Parameter. Neue erfolgreiche Logins speichern explizite Werte
im unveränderten Account-Schema; Legacy-Records werden beim Lesen nicht umgeschrieben.
Stored-/Shared-Mapping verwendet dieselbe Validierung. Das prüft Zahlenrepräsentation und
positive Werte, nicht vollständige SDK-Kostenlimits oder den Erfolg echter Crypto-Operationen.

Returning Unlock prüft Metadaten vor Repository-Transition, Client-/Crypto-Erstellung und
Biometrie-Prompt. Ungültige Daten leeren Passwort/PIN und zeigen einen stabilen Domain-Fehler;
PIN-Versuchsbudget, Keys und Enrollment bleiben unverändert. Die Fehler werden nicht mehr als
falsches Passwort/PIN verbucht. Scope-/Epoch-Guards und appweite PIN-Serialisierung bleiben erhalten.

Ausgeführt und bestanden: 405 AppModules-Swift-Testing-Tests in 54 Suites plus zwei XCTest-
Filtertests und 117 AuthFeature-Tests in 12 Suites, insgesamt 524 Tests. 15 vorhandene Transport-
Testmethoden sind portiert, nicht als neue Tests gezählt; 20 Methoden sind neu. Sie prüfen Mapper-
Grenzen/Defaults, Token-/Stored-/Shared-Werte, Redaction, Transport-Denial und kontrollierte
Cancellation sowie KDF-Fehler vor Token/Crypto/Commit und ohne PIN-/Enrollment-Veränderung.
Beide unsigned macOS-arm64-/iOS-Simulator-App-/Extension-Builds bestehen. Auch der abschließende
Auth-Lauf nach Entfernung ungenutzter Imports besteht vollständig.

Ein erster Auth-Testbuild zeigte einen fehlenden Data-Import im Biometrie-Test; korrigiert, ohne
Re-Export. Ein erster AppModules-Lauf mit 404 Tests deckte eine vorhandene Cache-Test-Flakiness
auf: JSON-Decoding/Re-Encoding garantiert keine Byte-Reihenfolge von Objekt-Schlüsseln. Der Test
vergleicht jetzt das vollständige JSON-Objekt samt allen verschlüsselten Werten; ein neuer Fall
mit umsortierten Schlüsseln ergänzt die Regression. Produktiver Cache-Code bleibt unverändert.
Der finale vollständige Lauf mit 405 Tests besteht; kein Assert wurde entfernt, kein wiederholter
Zufalls-Retry als Nachweis verwendet.

S-303/U-504 bleiben teilweise: Keychain-Komposition, SDK-Token-Provider, Client-Erstellung,
Credential-Sequencing, Commit und pending SDK-Contexts liegen weiter in AuthFeature.
IdentityTokenService liefert Data-Wirewerte an diesen Übergangsflow, keine fertigen Domain-only
Command-/Presentation-Ergebnisse. AuthPresentation bleibt Domain/SharedUI-only. Es bleiben drei
Pakete; kein vorzeitiges Löschen des Auth-Pakets. Durables Recovery, echte Runtime-/Commit-Races,
KDF-Kostenlimits und signierte Server-/Geräte-/Cross-process-Matrix sind offen. Kein SDK-FFI-
Smoke, echter Server, UI-Launch oder Release-Produkt-Build in diesem Block; keine Zeroization-
oder Rollback-Zusage. Offizielle Subrepos bleiben unverändert.
Entscheidung: Docs/ADR/009-auth-transports-and-kdf.md; Resultate/Befehle:
Docs/Verification.md. Kein gesamtes Release-Gate wird hierdurch geschlossen.

**A-205 / S-302 / S-303 / S-305 / U-504 – Credential-Autorität und PIN-Settings nach Data migriert (2026-09-28):**
Der ehemalige AuthKeychainStore liegt jetzt als AuthCredentialStore in Data. Device-ID, private
Session, scoped Biometrie-/PIN-Speicher, Shared-Publikation und Lock/Logout behalten Namen,
Schutzklassen, Schema, Lock-Policy und exakte Serveridentität. StoredAccount->Domain-Mapping
und klassifizierte optionale Keychain-Reads sind ebenfalls aus AuthFeature entfernt. AppComposition
erzeugt nach Konfigurationsprüfung genau diesen Store, injiziert ihn in AuthServices und direkt als
AuthSessionLifecycleStore in DefaultAuthRepository. AuthServices erzeugt weder Store noch
Repository/PIN-Settings. AuthLifecyclePersistence, PinEnrollment und der app-eigene
SessionPinUnlockSettingsAdapter sind gelöscht, keine Kompatibilitäts-Aliases hinzugefügt.

Data.AppAuthTokenProvider und die Produktions-Bootstrap-Factory besitzen jetzt Fresh-Login-Proof,
Scope-/Epoch-Bindung, Commit, Refresh-Coordinator und Widerruf. Initializer, Commit-Proof und
unscoped Raw-Key-/Token-Persistenzhelpers sind Data-intern. Frischer Login leiht keine alten Tokens;
Returning Bootstrap vergleicht Account/Server/Scope/Epoch vor Bereitstellung. Unsichere URLs
werden schon vor Erfassung der Storage-Autorität abgewiesen. Data importiert dafür kein SDK;
SDKManagedTokenAdapter besitzt ausschließlich die SDK-Callback-Konformität mit Sendable-Funktion
und Cancellation-Prüfung vor/nach dem Callback. Keine zweite Token-Autorität.

Data.SessionPinUnlockSettings implementiert den Domain-Port gegen denselben Store und Runtime.
Enrollment validiert vor Crypto und nach dessen Suspension. Enrollment/Removal vergleichen den
vorher erfassten Widerrufs-Epoch unter dem Write-Lock zusätzlich zum Sign-in-Scope, der Lock
überlebt. Verspätete nicht kooperative Derivation nach Runtime-Widerruf, Lock oder neuem Login
kann kein Enrollment schreiben. Das sind keine atomaren Mehrfach-Keychain-Writes; Key, Zähler
und Account-Flag bleiben separate Items mit bestehendem Fehler-/Rollback-Verhalten.

Ein Nachreview korrigiert die verbliebene KDF-Publikationslücke aus dem vorherigen Block:
Der Producer mappt Legacy-Argon2 richtig, aber der echte Shared-Write verglich noch rohe
PBKDF2-/Nil-Defaults und konnte diese normalisierten Werte ablehnen. Auch dieser Vergleich
berechnet jetzt die kanonischen Erwartungswerte innerhalb der Storage-Transaktion. Omitted-
Defaults gelangen in Grant/Tokens ohne private Metadaten umzuschreiben. Fremde/geänderte
Identität/KDF/Wrapped-Private-Key-Werte und alte Epochs bleiben gesperrt. Mapper-Tests allein
hatten den erfolgreichen produktiven Write noch nicht bewiesen; der neue Testblock prüft ihn.

Ausgeführt und bestanden: 477 AppModules-Swift-Testing-Tests in 62 Suites plus zwei XCTest-
Filtertests und 63 AuthFeature-Tests in acht Suites, insgesamt 542 Tests. 54 bestehende Methoden
aus vier Speicher-/Token-Suites sind portiert, nicht als neue Tests gezählt; 18 Methoden sind neu.
Synchronized In-Memory-Stores/Refresh-Fixtures, kontrollierte Continuation-Gates und vollständige
Private-Record-Feldvergleiche prüfen tatsächliche Shared-Publikation, Metadata-Denial, PIN-
Erfolg/Crypto-/Counter-Write-Fehler, Late-Crypto/Widerruf, Cancellation und Bootstrap-Authority.
Beide finalen unsigned macOS-arm64-/generischen iOS-Simulator-App-/Extension-Builds bestehen.

Die erste Portierungsrunde erforderte eine finale Klasse für das class-bound SDK-Token-Protokoll;
die neuen Persistenztests vergleichen Schema/Account/Scope/Tokens statt eine nicht existierende
Equatable-Konformität des Records zu verlangen. Keine Produktions-Konformität nur für Tests,
keine Assertions entfernt. Die vollständigen finalen Targets wurden ausgeführt, nicht nur gebaut.
Workspace-Caches bleiben erhalten; kein Projekt-/Manifest-Umbau oder XcodeGen nötig.

S-303/U-504 bleiben teilweise: Login-/TOTP-/Unlock-Sequencing, rohe SDK-Client-Erstellung,
pending SDK-Contexts sowie Initiierung von Data-Commit/Handoff liegen weiter in AuthFeature.
Presentation konsumiert dort noch Data-Payloads/klassifizierte Storage-Fehler; das ist nicht
Domain-only. AuthPresentation behält Domain/SharedUI-only Dependencies. Drei Pakete bleiben.
Keine signierten Geräte, echter Server/FFI-Crypto-Smoke, UI-Launch, Release-Produkt-Build oder
Cross-process-Matrix; durables Recovery und volle operation-eigene Commit-/Cancellation-
Semantik bleiben offen. Keine Zeroization-/Rollback-Zusage, kein gesamtes Release-Gate geschlossen.
Offizielle SDK-/Subrepo-Pfade bleiben unverändert; keine neuen Kompatibilitätsfeatures.
Entscheidung: Docs/ADR/010-auth-credential-authority.md; Resultate/Befehle:
Docs/Verification.md.

**A-202 / A-203 / A-206 / S-302 / S-303 / U-504 – Login-/TOTP-Commands und opaque Auth-Capabilities (2026-09-28):**
Frischer Login/TOTP sequenziert jetzt vollständig in Data: Device-/Bootstrap-Autorität, Prelogin,
Hash, Token-Grant, Account/KDF-Validierung, SDK-Initialisierung und privater Commit. Domain definiert
Commands, stabile Rejection-Ergebnisse, widerrufbare TOTP-Challenge und Pending-Authentication.
LoginModel, TwoFactorModel und EnableBiometricsModel erhalten nur diese Domain-/Plattform-Ports,
keine AuthDependencies/Wire-/Store-/SDK-Abhängigkeiten. UI-Routen tragen keine Passwörter, Hashes,
Client- oder Token-Provider-Properties mehr. TwoFactorContext, PendingSessionContext,
AuthUnlockFlow und Feature-eigenes JWT-Bookkeeping sind ohne Aliases entfernt.

PasswordSecondFactorChallenge besitzt private Retry-Credentials und ein Submit-Gate; nach
Erfolg leert sie ihre Passwort-/Hash-Referenzen und überträgt dieselbe Attempt-ID/Ressource an
PendingAuthSession. Ihr späterer Widerruf bei Forward-Navigation kann die Nachfolge-Session nicht
beenden. Provider 0/TOTP bleibt die einzige ausführbare 2FA-Art, keine neuen Kompatibilitätsfeatures.
Data validiert die ursprüngliche Fresh-Proof-Autorität nach jedem suspended Stage und beim Write
unter dem bestehenden Storage-Lock. Lock/Lineage-Wechsel/Cancellation sperren spätes Weiterlaufen.
Ungültiges Token-KDF sowie leere Subject-/Refresh-/Wrapped-Key-Daten und ungültige Expiry scheitern
vor SDK-Unlock. Unbekannte Diagnosen werden nur in eine stabile Domain-Rejection gemappt.

SDKAuthCredentialCryptography kapselt das SDK hinter einer opaque Ressource; Data besitzt keinen
raw SDK-Client. PendingAuthSession hält Store/Provider/Crypto privat, prüft bei AutoFill-/Biometrie-
Operationen Scope/Epoch vor/nach Derivation und nutzt die bestehenden scoped Write-Guards. Die
best-effort AutoFill-Policy bleibt erhalten. Der Data-Handoff-Bridge ist single-use, baut Runtime mit
derselben Ressource und installiert Expiry vor Rückgabe; Coordinator prüft danach Route/Authority/
Runtime vor dem Callback. Accepted UI-Teardown widerruft keine runtime-eigene Session.

Final tatsächlich ausgeführt und bestanden: 496 AppModules-Swift-Testing-Tests in 64 Suites plus
zwei XCTest-Tests und 62 AuthFeature-Tests in acht Suites, insgesamt 560 Tests. Vier bestehende
Methoden (JWT und Token-KDF-Denial) sind portiert; 18 Methoden sind neu. Gated In-Memory-/No-Handle-
Fixtures prüfen jeden Prelogin-/Hash-/Token-/Unlock-Abbruch, Lock bei gleicher Lineage, neue Lineage,
TOTP-Retry/Duplikate/Transfer/Widerruf, incomplete Tokens, late Key-Derivation, single-use Handoff
und Expiry sowie Domain-only UI-Callbacks. Beide finalen unsigned macOS-/iOS-Simulator-App-/
Extension-Builds bestehen. Keine Assertions entfernt; Compiler-Korrekturen am Zwischenstand sind
im finalen vollständigen Lauf enthalten. Kein Manifest-/Projekt-Umbau, Workspace-Caches erhalten.

S-303/U-504 bleiben teilweise: Returning UnlockModel und seine SDK-/PIN-/Biometrie-Orchestrierung,
Data-geprägter Restore und Root-Session-Callback sowie AuthFeature-Paketauflösung fehlen noch.
Nach bestätigtem privatem Commit gibt es keine Rollback-Zusage bei UI-Cancellation; die vollständige
operation-eigene Commit-/Cancellation- und durable Recovery-Semantik bleibt offen. Separate Keychain-
Items bleiben separate Writes. Kein echter Server, SDK-FFI-Smoke, UI-Launch, Release-Produkt-Build,
signiertes Gerät/Entitlement oder Cross-process-Lauf in diesem Block; keine Zeroization-/Release-
Gate-Zusage. Offizielle SDK-/Subrepos unverändert. Entscheidung: Docs/ADR/011-auth-command-capabilities.md;
ausgeführte Befehle/Ergebnisse: Docs/Verification.md.

**A-203 / A-206 / S-302 / S-303 / U-504 / C-903 – Returning-Unlock vollständig hinter Domain-Commands (2026-09-28):**
Data.ReturningUnlockService besitzt jetzt Passwort-/PIN-/Biometrie-Sequencing, KDF-/Scope-/Epoch-
Prüfung, Repository-Begin/-Failure, OS-Evaluation, scoped Reads, opaque SDK-Crypto, PIN-Zähler/
Fallback, best-effort Shared-Publikation und Pending-Ownership-Transfer. UnlockModel ist nur
Presentation; State und Route enthalten nonsecret Domain-Account/Availability/Commands statt
StoredAccount, Wrapped Keys, TokenScope oder Client. Alle fünf Auth-Models und alle Routen sind
Domain-only. Die appweite PIN-Serialisierung bleibt über mehrere Command-Instanzen erhalten;
der Service ist für Plattformprompts/Gate MainActor-isoliert, nicht eine neue globale SDK-Autorität.

Nachreview-Fix: Scope allein überlebt Lock und war für Returning-Mutationen zu schwach. Data
prüft den erfassten Epoch nach jedem Repository-/Biometrie-/Crypto-Await; PIN-Increment/-Reset
und PIN-/Biometrie-Cleanup verlangen denselben Epoch zusätzlich direkt im Write-Lock. Scope-only
Produktions-APIs sind entfernt; Komforthelpers stehen nur in Testtargets. Ein spätes nicht-
Cancellation-PIN-Fehlerergebnis nach Lock verbraucht keinen Versuch; eine späte notEnrolled-
Biometrieantwort entfernt keine Enrollment. Persistierte PIN-Eignung/Key/Budget wird bei jeder
Submission neu gelesen, auch ohne .appeared. Counter-Reset-/Fallback-/Cleanupfehler bleiben
getrennte typisierte Fälle mit no-retry Guidance; akzeptierter PIN ohne Reset wird nicht übergeben.
OS-/Keychain-Cancellation bleibt still. Jede erfolgreiche Unlock-Art teilt AutoFill erneut.

Erfolg schließt den Returning-Command und überträgt dieselbe Ressource/Provider an PendingAuthSession;
späterer Widerruf der alten Route beendet den Nachfolger nicht. Bei Abbruch werden Ressourcen vor
Repository-Failure widerrufen. Auch vom Begin-Port selbst gemeldete Cancellation reconciliert den
angeforderten Übergang. Das Model leert beide Eingaben vor Callback und revokiert late Capabilities.

Entfernt: produktive SDKClientFactory, StoredAccount/StoredTokens/VaultUnlockService-Aliases,
raw-Client-/Token-/Device-Bridges aus AuthDependencies. BitwardenSdk, AutoFillContract und
SecurityStorage sind keine direkten AuthFeature-Produktabhängigkeiten mehr; notwendige Test-
Fixtures sind explizit im Testtarget. Paketmanifest geändert, project.yml/Projektprodukte unverändert;
Xcode hat den lokalen Manifestgraph beim Build neu aufgelöst, kein XcodeGen nötig.

Final tatsächlich ausgeführt und bestanden: 510 AppModules-Swift-Testing-Tests in 65 Suites plus
zwei XCTest-Tests und 65 AuthFeature-Tests in acht Suites, insgesamt 577 Tests. 14 neue Data- und
drei neue Domain-only Model-Testmethoden sind ergänzt, keine alten Assertions entfernt. No-Handle-
Ressourcen, In-Memory-Stores und Continuation-Gates prüfen normale Transfers, Crypto-Cancellation/
Lock, late PIN-Fehler, stale Biometrie, Ersatzaccount, Budgetprüfung, Counter-/Cleanupfehler,
Publikations-/Transition-Abbruch und epochgebundene Writes. Beide finalen unsigned macOS-arm64-/
generischen iOS-Simulator-App-/Extension-Builds bestehen. Offizielle SDK-/Subrepos unverändert.

S-303/U-504 bleiben teilweise: Data-shaped Restore-/Root-Handoff und Service-Komposition sowie
die Migration ins vollständige Live-AuthPresentation/Package-Cleanup fehlen. Durables Recovery,
vollständige operation-eigene Commit-/Cancellation-Semantik, Settings-/Key-Replacement-/Multi-
Scene-/Server-/signierte Geräte-/Cross-process-Matrix bleiben offen. Separate Keychain-Writes sind
keine Multi-Item-Transaktion, kein Zeroization-/Rollback-Versprechen. Kein SDK-Crypto-/Server-Smoke,
UI-Launch, Release-Produkt-Build oder signierter OS-Prozess in diesem Block. Keine neuen Features
oder Kompatibilitätsadapter; kein Release-Gate geschlossen. Entscheidung: Docs/ADR/012-returning-unlock-commands.md;
ausgeführte Befehle/Ergebnisse: Docs/Verification.md.

**A-203 / S-303 / U-504 / C-901 bis C-903 – Domain-only Restore/Handoff und Auth-Paketauflösung (2026-09-28):**
Domain.AuthFlowCommands/AuthRestoreResult/AuthenticatedSessionCapability schließen die verbleibende
Data-shaped UI-Grenze. Data.DefaultAuthFlowService besitzt Restore-Mapping, Command-Komposition und
Single-use Runtime-Preparation gegen denselben injizierten Store/Repository. AuthCoordinator und
AuthRootView konsumieren ausschließlich Domain-Ports; der opaque Runtime-Capability-Callback gibt
keinen Store, TokenScope, SDK-Ressource oder Repository-Factory frei. Die konkrete Data-Session wird
nur in AppComposition für den bestehenden Session-Adapter verwendet. AppFeature.AppSessionResource
ist Alias desselben Domain-Runtime-Vertrags, keine zweite Session-Autorität.

Restore erfasst den persistenten Epoch vor Repository-Suspension und verweigert stale Cancellation,
Lock/Logout/Ersatzaccount/-Scope sowie Repository-/Storage-Widerspruch. Reine Anzeige startet nicht
mehr beginUnlock; nur die Returning-Submission tut dies. Split-Legacy-Metadaten bleiben erhalten und
verlangen echten Passwort-Login; unsichere HTTP-Altdaten autorisieren keinen Unlock. Unlesbare/
beschädigte Records zeigen Recovery statt First Run. Obsoleter Controller-Restore revokiert einen
late Returning-Command. Data installiert Expiry vor Session-Rückgabe: gleiche Runtime widerrufen,
Repository runtime-ID-gebunden markieren, dann MainActor-App-Callback. Controller prüft Authority/
Route/Access vor Übergabe, revokiert abgelehnte Runtime/Context und erhält accepted Ownership.

Alle Auth-Produktquellen sind jetzt im Domain-/SharedUI-only AppModules.AuthPresentation; alle 65
bestehenden Auth-Methoden und ihre Fixtures/Assertions in AuthPresentationTests. Separate Testtarget-
Namespace erhält bestehende Helpers ohne Public-Produkt-Mocks. AuthDependencies existiert nur dort.
AuthServices und das AuthFeature-Manifest sind gelöscht, sämtliche Consumer auf AuthPresentation
umgestellt. project.yml und Testscript enthalten nur AppModules/VaultwardenSDK; XcodeGen regeneriert
das ignorierte Projekt. Historischer privater .AuthFeature-Keychain-Service-Suffix bleibt unverändert.

Final ausgeführt/bestanden: 589 Swift-Testing-Methoden in 75 Suites plus zwei XCTest-Tests, insgesamt
591 Tests. Zehn neue Data- und vier Domain-only Controller-Methoden, portierte Methoden nicht als
neue Coverage gezählt. Continuation-/In-Memory-/No-Handle-Fixtures prüfen beide Restore-Hops,
Read/Decode-/Migration-/Transport-/Accountfehler, Security-Fences, Single-use Runtime, Expiry-
Reihenfolge, late Command/Runtime und accepted Teardown. Beide unsigned macOS-arm64-/generischen
iOS-Simulator-App-/Extension-Builds sowie xcodebuild -list -json bestehen. SDK-/Subrepos unverändert.

C-902 ist lokal erledigt; keine Phase/Release-Gate daraus abgeschlossen. S-303/U-504/C-901/C-903
bleiben teilweise: endgültiger repository-observation-only Workflow, app-eigener konkreter Session-
Adapter, operation-eigene Commit-/Cancellation-Semantik und durable Recovery sowie verbleibende
Extension-Orchestrierung offen. Keine Multi-Item-Keychain-Transaktion/Zeroization/Rollback-Zusage,
kein neuer Kompatibilitätsadapter. Kein SDK-FFI-/Server-Smoke, UI-Launch, signiertes Gerät/Entitlement,
Release-Produkt-Build oder Cross-process-Lauf in diesem Block.
Entscheidung: Docs/ADR/013-auth-presentation-and-handoff.md; Befehle/Ergebnisse:
Docs/Verification.md.

**X-601/X-602/X-603 – AutoFill-Query-/Assertion-Aufteilung (2026-09-28):** AutoFillVaultStore ist
von 419 auf 40 Zeilen reine Composition reduziert. AutoFillData.ExtensionVaultSession assembliert
eine invocation-eigene SDK-Resource, denselben injizierten Proof-/Cache-Source sowie CredentialQuery
und PasskeyService als Actors. Der synchrone ExtensionSession-Lease bleibt für SDK-Callbacks;
kein Lock wird über Crypto-/Network-await gehalten. Originalaccount, Unlock-Proof und feste
Cache-UUID werden erneut geprüft; Fehler/Wechsel revokieren permanent. Assembly-Deinit revokiert
auch bei retained Query. SDK-Konfiguration/KDF/Backing/Assertion-JSON liegen im Adapter;
AutoFillData hat keine direkte SDK-Abhängigkeit oder SDK-Imports, kein raw Client wird exportiert.

Picker tragen nur Summary-Metadaten, kein Passwort/TOTP-Seed/private Passkey-Key. Passwort und
TOTP werden frisch am ausgewählten Cipher aufgelöst; die Actors cachen keine Decrypt-Ergebnisse.
Listen melden einzelne unlesbare/mehrdeutige geeignete Items mit sichtbarer Partial-Warnung;
Proof-/Cachefehler und Cancellation werden nicht zu einem Teil-Erfolg heruntergestuft.
Passkey-Zeilen besitzen Cipher-plus-Credential-ID, direkte OS-Identitäten prüfen beide IDs.
Assertion entschlüsselt nur den ausgewählten Cipher, prüft eindeutige aktuelle Credential-Bytes
und exakte RP vor SDK-Callback, Authority/Cancellation danach und die zurückgegebene Credential-ID.
Actor-Busy-Guard verhindert parallele Assertions. Fehlender Picker-UserHandle verhindert nicht
den bestehenden SDK-Assertion-Pfad. Alte Store-Nested-Session/MatchedLogin/NoOp-Provider/
Request-JSON-Helper sind entfernt, nicht durch Aliases beibehalten.

Final ausgeführt: vollständige AppModules-Testtargets, 612 Swift-Testing-Methoden in 78 Suites
plus zwei XCTest-Tests (614 gesamt), 23 Methoden neu; beide regenerierten unsigned macOS-arm64-
und generischen iOS-Simulator-App-/Extension-Builds bestanden. Gated No-Handle-/synthetische
SDK-Model-Fixtures prüfen Partial-Fehler, doppelte IDs, Metadata-only/Redaction, frische Secrets,
RP/Request-Bytes, late Cancellation/Lock/Policy und Session-/Query-Lifetime. Keine realen SDK-
Crypto-/Server-/signierten OS-/Cross-process-/Release-Checks aus diesem Block ableiten.
SDK-/Subrepos unverändert. ADR: Docs/ADR/014-autofill-query-and-passkey-orchestration.md;
Befehle: Docs/Verification.md.

Weiter teilweise: SDK-geprägte FIDO-/Registration-Callbacks und Serverwriter verwenden ausdrücklich
markierte Adapterports (legacyView/perform), kein Picker-State. Silent SDK-Feld-Degradation,
Collection-Policy im Legacy-Cache, konkrete Controller-Fallbacks, OS-Context-/User-Verification-
Matrix und X-604 bestätigter Write/Recovery/Identity-Projektion bleiben offen; keine Phase/Gate
geschlossen und keine neue Vaultwarden-Kompatibilität eingeführt.

**X-602/X-603 – Identified-Request-Nachfix (2026-09-28):** Direkte OS-Passkey-Identität verwendet
jetzt PasskeyService.match für nur den ausgewählten Cipher und die exakten Credential-Bytes,
nicht mehr matching über den gesamten Vault. Gleicher Validator prüft aktuellen eindeutigen
Record/ID/RP in Direct-Match und Assertion. Falsche/unbekannte/mehrdeutige/foreign ID, fehlende
Passkeys und Decrypt-Fehler substituieren keine andere Credential. Drei neue parametrisierte
Methoden prüfen auch unrelated beschädigtes Item und late Cancellation/Lock/Policy. Vollständiger
Lauf: 615 Swift-Testing-Methoden in 78 Suites plus zwei XCTest-Tests (617 gesamt); beide unsigned
Plattform-Builds bestanden.

Ein konkreter Passwort-/TOTP-Fulfilment-Fehler cancelled jetzt, statt ohne Identifier den gesamten
Vault als Picker anzubieten. Manuelles Browsing bleibt ausschließlich am expliziten List-Entry-
Point. Der identified Debug-Log gibt die Record-ID nicht mehr aus. Controller-Cancel ist geprüft
und beidseitig gebaut, aber noch kein ausgeführter OS-Context-Test; Integration/Fehlermatrix
bleiben offen. SDK-/Subrepos unverändert; kein Gate geschlossen. ADR 014 und Verification ergänzt.

**X-604 – Registration-Write-/Recovery-Grenze (2026-09-28):** AutoFillData.PasskeyRegistrationWriter
besitzt die Mutation in eigener Task, unabhängig von UI-Consumer-Cancellation. Runtime-/Grant-
Widerruf bleibt wirksam. Ein Actor-Busy-/Terminal-Guard verhindert parallele und wiederholte
Creates nach unklarem/bestätigtem Write. Vor HTTP wird ein UUID-Mutationsmarker samt öffentlicher
Account-/Server-/RP-/Credential-/Target-ID-Metadaten atomar im App Group gespeichert. Kein Key,
Seed, Passwort, UserHandle, Attestation, ClientDataHash oder HTTP-Body im Journal. 0600, Datei-
Synchronisierung, Schema 1, injizierter gemeinsamer Token-/Grant-Prozess-Lock. Keine Fallback-
Container; future/corrupt/duplicate Records werden nicht verworfen. Pending Marker sperren weitere
Registrations dieses exakten Accounts auch bei Writer-/Store-/Invocation-/Unlock-Neuerzeugung.

Die bestehende SDK-Bridge prüft EncryptionContext-Owner, frische Cache-/Edit-Policy und SDK-
dekodierte Bytes: genau ein neuer Passkey für die RP, kein existierender Passkey entfernt.
SDKCipherService klassifiziert definite Pre-submit-/4xx-Rejection getrennt von Transport-/Timeout/
Conflict-/5xx-Unklarheit und erfolgreichem Status mit unlesbarer Antwort. Omitted-Update-ID bleibt
wie bisher; Create ohne ID oder fremde Update-ID wird nicht als reparierter Cache behandelt.
Nur definite Ablehnung entfernt ihren Marker; Cleanupfehler blockiert Retry. Bestätigter Write
mit Cache-/Journalfehler bleibt Servererfolg plus Repair-Receipt, nicht stilles try?. FFI-gewrapptes
Callback-/Post-Commit-SDK-Error wird aus dem Write-Actor typisiert; unbekannte/bestätigte Writes
lassen UI-Save nicht erneut zu. Cancel bleibt verfügbar.

Die produktive App-Komposition injiziert Data.PasskeyRegistrationRecoveryReconciler in denselben
Vault-Repository-Pfad. Nur vollständiger erfolgreicher Sync plus Cache-/OS-Publishing derselben
Revision darf exakte eindeutige Credential-/RP-/bekannte Cipher-ID-Marker auflösen. Abwesenheit,
falsche/mehrdeutige ID, Teil-Projektion, normaler CRUD-Commit oder Journalfehler lösen nicht auf.
Pending-/Storage-Recovery ist als eigener Domain-Warning im Vault sichtbar, ohne Item-Counts
zu verfälschen; Lock verhindert späten Snapshot. Das Journal bleibt über Logout/Neustart erhalten.

Finale vollständige Tests: 645 Swift-Testing-Methoden/81 Suites plus 2 XCTest (647 gesamt), 30 neu.
Reale temporäre Journaldateien/Recreation/0600, gated UI-Abbruch/Runtime-Lock/parallel callbacks,
Responses/ambiguous/confirmed/rejected/cleanup/foreign/future/corrupt/Cache-/OS-/Reconcile-Fehler
und Warnungserhalt sind geprüft; beide unsigned Plattform-App-/Extension-Builds bestanden.
Offizielle SDK-/Subrepos unverändert. ADR 015; Befehle/Abgrenzung in Verification.

X-604 bleibt teilweise: sofortiges extensionseitiges OS-Identity-Publishing/Revisionskopplung,
expliziter sicherer Auflösungsweg für Marker ohne beobachtbare Credential und echte Server-/FFI-/
Process-kill-/Power-loss-/signierte Geräte-/OS-Races offen. Unklarer Write ohne Match bleibt
bewusst accountweit gesperrt; nicht mit TTL/erfolgreichem aber fehlendem Sync blind löschen.
Journal/HTTP/Keychain/Cache/OS sind keine atomare Transaktion und kein Server-Idempotenzvertrag.
Keine Kompatibilitätsfeatures oder Gates aus diesem Block ableiten.

**X-604/V-403 – Inkrementelle Registration-Identitäten (2026-09-28):** Die zuvor offene direkte
OS-Projektion ist jetzt im produktiven Extension-Writer angeschlossen. AutoFillData-Actor schreibt
zuerst den bestätigten verschlüsselten Record und erhält einen nicht konstruierbaren redigierten
Receipt mit exaktem Proof, neuem UUID-/monotonem Fence und DTO-Bytes. Derselbe Grant-/Token-Lock
prüft vor/nach Metadata-Awaits und nach OS-Await den unveränderten eindeutigen Cache-Record.
SDKAdapter entschlüsselt die Serverantwort und selektiert genau die neue Credential/RP/Cipher
unter aktueller Edit-/Secret-Policy; Data nutzt seinen bisherigen Descriptor-ID-Mapper.

Domain.PasskeyIdentityUpdating erlaubt nur Add/Remove einer Passkey-Identity. Der bestehende
PlatformServices-Adapter verlangt enabled und supportsIncrementalUpdates; nie Replace-all aus
einem Extension-Teilstand. Striktes Mapping meldet ungültige Pflichtfelder statt stiller Auslassung.
Später Widerruf/Stale-Cache/unklarer Addfehler entfernt nur die gerade versuchte Identity; Cleanup-
Fehler ist typisiert. Der mutationseigene Writer erwartet die asynchrone Projektion unabhängig
von UI-Cancellation. Lokaler Fehler bedeutet Repair-Receipt, niemals zweiter Serverwrite. Das
Journal bleibt auch nach Erfolg bis zum vollständigen autoritativen App-Sync bestehen.

17 neue Methoden mit expliziten Gates: Cache-vor-OS, exakte Metadaten, veränderte Grant-/UUID-/
Revision-/DTO-/Owner-Fences, Metadata-/OS-Lock, gezieltes Cleanup/Fehler, parallele Projektion,
Legacy-Cache ohne monotone Revision und async UI-Cancellation. Vollständige Targets ausgeführt:
662 Swift-Testing-Methoden/84 Suites plus 2 XCTest (664 total), beide unsigned App-/Extension-
Builds bestanden. XcodeGen regeneriert; PlatformServices in beiden Extension-Targets ergänzt.
Offizielle SDK-/Subrepos unverändert; ADR 016 und Verification dokumentieren Details.

Keine globale OS-Write-Queue zwischen Prozessen: App-Replace/Clear und Extension-Add/Remove
können überlappen. Späte Compensation kann die gleiche Identity eines neueren Sync entfernen;
späterer vollständiger Sync repariert, nicht als atomare Konsistenz behaupten. Prozessende kann
Compensation überspringen. Signierte Prozess-/OS-/Server-/FFI-/Power-loss-Matrix ungeprüft;
kein Release-Gate geschlossen. Marker ohne beobachtbare Credential bleiben bewusst blockiert.

**X-604 – Explizites Review/Abandonment (2026-09-28):** Neue Journalreservierungen binden die
tatsächlich autorisierte originatingUnlockID unter dem bestehenden Shared-Grant-/Token-Lock.
Optionale additive v1-Metadaten; kein Schema-/Dateinamewechsel und kein Erraten alter Origins.
Ein fremd eingesetzter Origin wird verweigert. Alte Records bleiben lesbar und exakt automatisch
reconcilierbar, aber ohne bekannte Origin nicht manuell freigebbar.

Domain-RecoveryReview ist ein redigierter Metadata-only Nonce-/Revisions-/RP-/Statuswert. Data-
Reconciler ist ein Actor mit einmaligem Review und exaktem verstecktem Journalrecord. Vault-
Repository ordnet Review/Abandonment mit Sync/CRUD in dieselbe FIFO ein und verlangt einen frischen
vollständigen Sync ohne Stale-/Unavailable-Items und mit aktueller Cache-/OS-Projektion. CRUD,
fehlgeschlagener Sync und Lock invalidieren diese Bereitschaft; ein Initialsnapshot genügt nicht.
Unveränderter Record, exakter Account/Server/Proof und bekannte andere originatingUnlockID werden
in EINER Journaltransaktion vor gezielter Entfernung verglichen. Neue/gefälschte/geänderte/reused
Bestätigung schlägt fehl. Keine neue HTTP-Mutation, kein Retry, kein allgemeines Journalreset.

Die Vault-Warnung öffnet eine Domain-only Review-Sheet. Gleicher Unlock und Legacy-Origin sind
nur informativ. Ein ready Review benötigt explizite Checkbox nach Inspektion im offiziellen Client
und den destruktiven Button „Abandon Local Tracking“. Dismissal tut nichts; Busy blockiert doppelte
Actions. Geänderte Snapshots/Fehler/Lock schließen alte Prompts. Explizit eingereichte lokale
Bestätigung ist repository-eigen und schließt denselben bestätigten Prompt vor UI-Cancellation;
bereits abgebrochene Einreichung mutiert nicht. Runtime-Widerruf verhindert späte Veröffentlichung.

22 neue Methoden: 3 reale Journal-/Origin-/Legacy-Fixtures, 7 Recovery-Service, 6 Pipeline,
6 Model. Fresh/same/legacy Origin, Exact-Compare/Phasewechsel/fremder Server/future Schema,
Nonce-/Sync-/CRUD-/Partial-/Projektionsguards, Cancellation vor/nach lokaler Mutation, Lock,
late review, Doppeltap und redigierte Fehler sind ausgeführt. Komplette AppModules-Testtargets:
684 Swift-Testing-Methoden/85 Suites plus 2 XCTest (686 total); beide unsigned Plattform-App-/
Extension-Builds bestanden. Konkrete async Actor-Methoden entsprechen explizit den Protokollen,
damit deren negative Default-Adapter keine konkreten Aufrufe überschatten. Bestehende Assertions
erhalten; offizielle SDK-/Subrepos unverändert. ADR 017 und Verification.

Abandonment quittiert nur die lokale Unsicherheit. Frischer Unlock ruft bereits gesendetes HTTP
nicht zurück; nach Inspektion/Sync kann ein alter Request noch committen. Checkbox/UI warnen vor
Duplicate-Risiko statt neue Registrierung zu empfehlen. Kein Rollback-/Rejection-Beweis, keine
TTL, keine automatische Resubmission, kein auditierbarer Consent-Ledger. Atomarer Dateiaustausch
kann vor spätem Synchronisierungsfehler bereits erfolgt sein; dann Sync statt Erfolgsbehauptung.
Alte Origin-lose Marker und signierte UI-/Server-/Prozess-/Power-loss-/OS-Matrix bleiben offen.

### SDK-/FIDO-Callbacks und typisierte Registration-Ports (2026-09-28)

Fido2CredentialStore/Fido2UserInterface, WebAuthn-JSON, Delta-Validierung und Crypto-Result-Mapping
liegen jetzt in BitwardenSDKAdapter. legacyView ist internal, rohe SDK-Crypto-APIs private.
AutoFillData/Extension importieren BitwardenSdk nicht; direkte SDK-Produkte aus project.yml entfernt.
AutoFillFido2Bridge ist nur noch 24 Zeilen Composition; Registrierung 109 statt etwa 300 Zeilen.
Unbenutzte Extension-Base64URL-Datei entfernt (Git-recoverable), Encoder im Adapter.

Konkrete Defekte: Lookup ignorierte UserHandle, Auswahl nahm first, Metadatenfehler wurden als
leere Liste verschluckt. Jetzt exakte decoded Handle/ID/RP-Matches, eindeutiges aktuelles Ziel,
duplizierte/fremde/leere Matching-Metadaten fail-closed und keine verschluckten Decodefehler.
Geräteverifikation ist Domain-Port/PlatformServices-Adapter, kein neuer Vault-Unlock-/Re-Prompt-Grant.
Frischer LAContext je Evaluation; false bleibt false, späte Cancellation/Lock verweigert Ausgabe.

PasskeyRegistrationPersistence besitzt typed Crypto-/HTTP-/Projektionsports und dieselbe
Journal-/Write-Actor-Strecke. Originalcache nach Decrypt/vor HTTP, Zielpolicy/ID und genau ein
zusätzliches decoded Credential für die RP werden vor Reservation geprüft. Origin stammt aus
dem Proof. PasskeyRegistrationCoordinator sperrt die ganze Registrierung vor Crypto/Prompt,
erhält typisierte Write-Fehler trotz FFI-Wrapping und verlangt passenden bestätigten Receipt plus
Attestation. Bestätigte eigene Cache-Projektion wird nicht durch alten UUID-Read zurückgewiesen.
Mutation bleibt Task-owned trotz UI-Cancellation; Completion nicht. Runtime-Widerruf bleibt wirksam.

26 neue Methoden (8 Callback, 3 Request/Delta, 4 Platform, 5 Persistenz, 6 Coordinator),
710 Swift-Testing-Methoden in 90 Suites plus 2 XCTest, **712 total bestanden**. Beide regenerierten
unsigned App-/Extension-Builds bestanden. Explizite Gates statt Sleeps; SDK-Struct-/Callback-
Fixtures und fake LAContext-Port, keine echte FIDO-Crypto-/FFI-Callback-Ausführung oder OS-Prompts.
Offizielle SDK-/Subrepos unverändert; keine neue Kompatibilitätsfunktion. ADR 018 dokumentiert
Ownership, Defekte und Grenzen. Signed/Server/Release/Process-kill/Power-loss/OS-Context und
globale Cross-process-OS-Ordnung bleiben offen; keine Phase/Gate allein wegen Modulgrenzen schließen.

### Gemeinsame App-/Extension-OS-Mutationsordnung (2026-09-28)

Domain.CredentialIdentityMutationCoordinating und SecurityStorage.AsyncCrossProcessFileLock
serialisieren jetzt teilnehmende OS-Mutationsblöcke über dieselbe stabile App-Group-Datei
.autofill-identities.lock. Ein FD-owned flock umfasst async Callbacks, ohne den Grant-/Token-
NSLock oder Swift-Executor während contention zu blockieren. LOCK_NB mit cancellable async
25-ms-Waits; 10-Sekunden-Waitlimit, aber keine TTL für erworbene Sperren. FD-Close/Unlock bei
jedem Exit. Kein process-only Livefallback, kein Unlink/Rotation der Lockdatei; fehlende Container,
Timeout, Symlink/FIFO/Directory/Storagefehler verhindern unkoordinierte OS-Mutationen.

Extension: Cache-Commit und Metadata vor der Sperre, Receipt nochmals nach Acquisition prüfen;
Add, Postcheck und gezielte Compensation im EINEN Block. App-Publish/Clear warten denselben
Block ab. Damit entfernt alte Compensation nicht mehr den gerade durch neueren teilnehmenden
App-Sync publizierten Passkey. App-Publish prüft Runtime und aktuell autorisierte exakte Cache-
Revision vor/nach OS-Replacement; unklarer/staler Ersatz wird im selben Block conditional cleared.
App-Clear verlangt denselben captured Unlock oder keinen aktuellen Grant. Alter Unlock darf
keine neuere Session löschen; Cleanup benötigt keine noch aktive alte Runtime. Ausfall der
Koordination meldet stale/unavailable statt unguarded OS-Fallback; alte Vorschläge können bis
Repair verbleiben, Grant-/Fulfilment-Grenzen widerrufen ihre Nutzbarkeit trotzdem.

Kurze Grant-Transaktionen dürfen innerhalb der Identity-Sperre laufen, niemals umgekehrt.
Kein HTTP/SDK-Crypto und kein Grant-Lock über OS-awaits. Cache kann sich zwischenzeitlich ändern;
Postchecks verweigern alte Gesundheit. Konflikt kann Vorschläge vorübergehend löschen und
erneuten vollständigen Sync benötigen; kein automatisches Merge/Retry/Serverwrite.

18 neue Methoden, kompletter Lauf 728 Swift-Testing/94 Suites + 2 XCTest = **730 bestanden**;
beide regenerierten unsigned App-/Extension-Builds bestanden. Real-temp-file/independent-FD-
Fixturen und explizite Gates/Contention-Probes prüfen Exclusion, Throwing/Cancellation/Timeout,
0600 und unsichere Dateien sowie Add-Cleanup-before-Replace, Lock-Drain, stale App-Replace nach
inkrementellem Cache-Commit und stale Extension-Waiter vor OS. Alte Assertions erhalten.
Erster neuer Testcompilerlauf benötigte getrennte Actor-Assertions/Read vor Require-Macro.
Offizielle SDK-/Subrepos unverändert; kein Credential-/Journal-Schemawechsel/Kompatibilitätsfeature.

Kein echter paralleler signierter Prozess-/OS-Store-Test: Die Tests öffnen unabhängige FDs im
selben Prozess, OS-Callbacks sind fake. Prozessabbruch kann die FD-Sperre freigeben, aber einen
schon beim OS-Daemon eingereichten Request nicht zurückrufen. Alte unkoordinierte Binaries,
hängende OS-Calls, Upgrade/Process-kill/Power-loss/Release/Entitlements und Server/FFI bleiben
offen. Kein durables OS-Fencing-Ledger, keine atomare Cache/Keychain/Journal/HTTP/OS-Completion-
Transaktion oder Garantie gegen später obsolete Health/Review-Freshness. X-604/V-403 bleiben
teilweise. Details ADR 019/Verification; keine Gate-Abkürzung durch neuen Lock.

### Terminal-Context, Completion und Fehlerpolicy (2026-09-28)

AutoFillData besitzt jetzt AutoFillRequestCompletion und den SDK-/OS-freien Context-Port mit
typisiertem transientem/redacted Output. Alle Controller-Terminals delegieren dorthin; Apple-
Callback-APIs starten nur im SystemAutoFillExtensionContext synchron. Lifecycle/Task/Cache/Proof,
Capability und leere Pflichtfelder werden vor Claim geprüft; kein await/Teardown vor Dispatch.
Reentrante OS-Dispatches dürfen neue Invocations nicht durch altes Retirement widerrufen.
Bestätigte Registration prüft Proof statt den selbst fortgeschriebenen Originalcache.

Typisierte Fehlerpolicy unterscheidet Route/Auth/Identity/Unsupported/User-Cancel, rendert keine
rohen Diagnosen und deaktiviert Save bei unklaren oder postcommit/output-invalid Fehlern.
Unbekannte Requests werden nicht als Password/Assertion interpretiert. Expliziter LA-userCancel
ist Domain-Fehler und callback-lokal sticky; kein preferred=false-Fallback/erneuter Prompt,
auch nach simuliertem FFI-Wrapping/returned Output. Bestätigter/unklarer Writer-Zustand hat
weiter Recovery-Vorrang; kein neuer Serverwrite/Kompatibilitätsfeature/Schemawechsel.

21 neue Methoden (10 Completion, 4 Query/Context, 4 Policy, 2 Callback, 1 Platform), zusätzlich
Postcommit-UserCancel-Argument. Gesamtlauf **749 Swift-Testing/97 Suites + 2 XCTest = 751 grün**,
beide regenerierten unsigned App-/Extension-Builds grün. Explizite Gates prüfen alte Decrypt-
Ergebnisse, Lock vor Ausgabe, Cancellation, genau einen terminalen Dispatch, Reentrancy,
Capabilities, malformed Outputs und frisch generierten TOTP nach Auswahl. Offizielle SDK- und
Subrepos unverändert. Details ADR 020/Verification.

Kein instanziierter Apple-Controller/OS-Context, keine realen Prompts/FIDO-Crypto/FFI-Callbacks,
kein signierter Server-/Process-kill-/Power-loss-/Release-Lauf. TOTP-at-selection ist KEIN
Expiry-Test; der code-only SDKAdapter verwirft noch period/timing-Metadaten. X-602/X-603/X-604
bleiben teilweise. Frühere offene Context-Harness-Hinweise beziehen sich auf damalige Stände;
der live verwendete terminale Paket-Harness ist jetzt vorhanden, echte OS-/UI-Integration nicht.

**TOTP-Ablaufgrenze umgesetzt (2026-09-28):** Domain.TimeBasedOneTimeCode erhält SDK-Periode
und explizite Generation. Query regeneriert bei lokalem Periodenwechsel höchstens einmal;
der Terminal-Context prüft nach letztem Access-Check denselben Epoch-Zeitbucket vor Claim.
Keine Picker-Seeds/-Codes behalten. 7 neue Methoden, 758 Tests und beide unsigned Builds grün.
Kein echter FFI-/OS-Akzeptanztest; Details ADR 021.

**Auth-Cleanup-Nachfolgeblock (2026-09-28):** Der gemeinsame Keychain erhält einen nichtgeheimen
`auth.cleanup.v1`-deny-Marker bis vollständiger Lock-/Logout-Bereinigung. Vor Restore wird er
in derselben Shared-Transaktion gelesen und wiederholt; alte Logout-Beobachtung kann damit keine
Nachfolgesession löschen. Fresh/Returning-Publication, Refresh und Extension-Grants bleiben bei
offenem/kaputtem/unlesbarem Marker gesperrt. Lock behält vor Marker die bereits bestätigte
Extension-Rotation; Cleanup versucht unabhängige Entfernungen auch bei Teilfehlern. 11 neue
Fixture-Methoden, keine echte Prozess-/Keychain-/Power-loss-Matrix. Marker-Schreibfehler und
alte Binaries bleiben Grenzen; kein Refresh-Journal. ADR 022. S-303/S-306 bleiben teilweise;
ihre früheren „Cleanup nur im Prozess“-Angaben beschreiben den damaligen Stand.

**Attachment-Dateitransport (2026-09-28):** Eigener Multipart-Body kopiert 64-KiB-Chunks in eine
exklusiv erzeugte 0600-Datei im vorhandenen registrierten Work-Verzeichnis. UInt64-Metadaten und
Content-Length; Blob-HTTP benutzt upload(fromFile:)/download(to:), same-origin und Redirect-Reject
unverändert. Download-Stage bewahrt bei Cancellation das alte Ziel und übernimmt nur neue
geschützte Metadaten; iOS Complete Protection, Unsafe Destinations und Cleanupfehler typisiert.
Late Secret-Policy wird vor Crypto nochmals geprüft. 14 neue Methoden, vollständige Targets:
784 Tests und beide unsigned Debug-Builds bestanden. ADR 023.

SDK-Datei-APIs lesen am gepinnten Stand selbst die ganze Datei (std::fs::read); File-Send nutzt
weiter Data/encryptBuffer. Ohne freigegebenen SDK-/Crypto-Umbau kein konstantes Gesamt-Peak-
Memory behaupten. Original-SDK/Subrepos unverändert; reale Server-/Disk-full-/OS-Matrix offen.
F-701/F-703/Quality Gate 7 ausdrücklich nicht geschlossen.

**Nachfolgender File-Send-Block (2026-09-28):** Der unmittelbar vorherige Absatz beschreibt den
Attachment-Zwischenstand. File-Send verwendet inzwischen das vorhandene SDK-encryptFile und
denselben geschützten Temp-/Multipart-/HTTP-File-Kern. 27 neue Methoden; final 811 AppModules-
Tests bestanden, dazu zuvor separat der echte SDK-Smoke (812 unterschiedliche Methoden).
Späte Picker-/Edit-Callbacks sind requestgebunden. Alte Sync-Consumer-Fixtures warten auf
tatsächlichen Join und lassen unerwartete Requests an Count==1 scheitern statt endlos zu warten.
Beide Plattformen unsigned Debug/Release bestanden; ADR 025/Verification. SDK-Whole-file-Heap
bleibt unverändert, kein abgeschlossenes Quality Gate 7.

**Aktueller Abschlussblock (2026-09-28):** Die bisher folgenden Punkte 1 und 2 sind lokal wesentlich
weiter umgesetzt: eigener Cross-Process-Network-Lock, durabler Refresh-Unsicherheitsmarker,
Epoch-Recheck vor Anfrage/Commit, typed Auth-Errors bis eigener UI/Registration, eindeutige Fresh-
Commit-Bestätigung, SDK-Feldverlustguard, KDF-Kostenlimits und feste Cache-Goldens. Unknown-
Cipher-Writes waren bereits durch ADR 026 gesperrt. Keine neue Serverkompatibilität und keine
SDK-/Subrepo-Änderung. [ADR 027](../ADR/027-refresh-request-recovery-and-decryption-integrity.md)
beschreibt die genaue Policy und ihre Grenzen. Vollständige lokale Regression und Build-Ergebnisse:
[Verifikation](../Verification.md).

Der kompakte, aktuelle Reststand steht in [Docs/RemainingReleaseWork.md](../RemainingReleaseWork.md).
Die originalen Abnahmen bleiben verbindlich; insbesondere vollständige Composition-/UI-/Apple-
Controller-Smokes, observation-only Handoff ohne Capability-Transfer, echte Server-/Prozess-/
Geräteprüfungen und Owner-Freigaben sind dadurch **nicht** abgeschlossen.

**Noch auszuführende Reihenfolge – keine nochmalige Wiederholung fertiger Modulmoves:**

1. S-302/S-303/U-504: implementierte Commit-/Refresh-Recovery gegen tatsächliche Prozess-/Storage-
   und End-to-End-UI-Kontexte abnehmen. Kein gespeicherter Response-/Server-Rollback-Beweis.
2. A-206/V-401: vorhandene Payload-/SDK-/KDF-Defektguards in der echten Crypto-/Server-/Geräte-
   Matrix abnehmen; keine neue Interpretation unbekannter Typen/Endpunkte einführen.
3. T-1002/C-904: tatsächliche App-/Extension-Composition-/UI-/Apple-Controller-Smokes mit
   synthetischen Ports ergänzen; Domain-only Views und bestandene Builds ersetzen diese nicht.
4. T-1003/O-05: Owner legt den echten Vaultwarden-Teststand fest; bestehenden Scope mit
   synthetischem Account testen. Keine echten Owner-Credentials oder ungefragte Servermutation.
5. Nur für spätere Apps: signierte P-801-/Entitlement-/Protection-/Scoped-Access-, Multi-Scene-,
   Shared-OS-/Legacy-Origin-/Process-kill-/Power-loss-Matrix aus der Freigabecheckliste ausführen.

Die Source-only-Vorbereitung (ursprüngliche MIT-Wahl, später auf GPL-3.0-only geändert; Notices,
Dokumentation, Kontakt, lokale Builds/Tests und isolierter SDK-Neubau) ist vorhanden. Remote-CI,
fremder Fresh-Clone-Rechner und abschließende Lizenzprüfung sind nicht ausgeführt. Keine
abgeschlossenen Hardening-Gates daraus ableiten.
Ohne freigegebenen SDK-Umbau lässt sich dessen linearer Heap nicht durch eigene File-Ports
wegbehaupten. Offizielle SDK-/Vaultwarden-Subrepos bleiben unangetastet.
Bei jedem weiteren Implementierungsblock betroffene Testtargets tatsächlich ausführen; nur
Ergebnisse mit realem Nachweis als erledigt markieren. Kein Push/Tag/Release/Upload im Scope.

**Integrationsblock (2026-09-29):** Punkte 3 und 4 der obigen Reihenfolge wurden als ein
Arbeitsprozess bearbeitet; die Task-Texte oben bleiben unverändert maßgeblich.

| Task | Stand | Nachweis | Noch offen |
| --- | --- | --- | --- |
| T-1002 / C-904 | teilweise | Hostlose macOS-/iOS-Simulator-Bundles kompilieren die echten `Composition/`-, `App/Sources/Shared/`- und `AutoFillExtension/Sources/Shared/`-Quellen: je 11 Composition-/Handoff-/Lifecycle- und 6 Hosting-/Controller-Methoden, beide lokal 17/17 bestanden. Signed out, locked, entsperrter Tab-Baum, Recovery und Controller-Invocation-Ersatz sind abgedeckt. | Launch-Argument-/XCUITest-Smokes, Vault leer/Inhalt/Fehler, Create/Edit/Delete-Bestätigung, Settings, Sends-UI, Screenshots, iPad-Simulator, echte Extension-Context-Completion. |
| U-504 / A-203 | Abweichung dokumentiert | Einmalige widerrufbare Capability-Übergabe statt observation-only Handoff; Duplikat/Konkurrenz/Widerruf/Lock-/Logout-während-Vorbereitung integrationsgeprüft. [ADR 028](../ADR/028-session-handoff-and-integrated-acceptance.md) | Die ursprüngliche U-504-Abnahme „onAuthenticated … durch AppModel-Sessionbeobachtung ersetzen“ ist nicht erfüllt. |
| T-1003 / O-05 | vorbereitet, NOT RUN | Opt-in Live-Test mit Einzelfeld-Konfigurationsverweigerung, RFC-6238-Referenz, Secret-/Revisionsprüfung, Cleanup nur eigener IDs; Runner verlangt Abschlussmarker. | Owner-Instanz, exakte Version, synthetischer Account samt Passkey-Login, Schreibfreigabe; danach tatsächlicher Lauf. |
| T-1005 | CI angebunden | Workflow ruft den gemeinsamen Runner (Packages + beide Bundles) und dessen Preflight-Fixtures auf; keine Server-/Signing-Secrets. | Kein Remote-Lauf, kein Fresh-Clone-Rechner. |

Ergebnisse, Befehle und Toolchain: [Verifikation](../Verification.md),
Ablauf und Grenzen: [Runbook](../IntegratedAcceptance.md), kompakt:
[Reststand](../RemainingReleaseWork.md). Keine Phase und kein Quality Gate wird dadurch abgehakt.

## 11. Aktueller Fortschritt

Die zwölf alten, durchgehend leeren Phase-Checkboxen wurden nach Einzelabgleich ersetzt durch
die Task-/Defekt-/Gate-Zuordnung in [RemainingReleaseWork.md](../RemainingReleaseWork.md).
Dieser Plan bewahrt Scope, Akzeptanzkriterien und datierte Geschichte; neue Arbeitsstände werden
ausschließlich in der zentralen Datei gepflegt. Keine Phase wird durch diese Dokumentpflege freigegeben.
