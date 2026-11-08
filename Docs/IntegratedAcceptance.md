# Gemeinsame Abnahme: Composition → Auth-Handoff → Serververtrag

> Integrations-Runbook mit datierter Evidenz, keine zweite aktuelle Arbeitscheckliste.
> Aktueller Lauf-/Reststatus ausschließlich in [RemainingReleaseWork.md](RemainingReleaseWork.md), insbesondere F-13/F-15/F-19/F-25.

Dieser Ablauf verbindet die bisherigen Restpunkte 1–3. Keine offiziellen Subrepos verändern,
keine neue Kompatibilität implementieren. Automatisierte Fixtures verwenden ausschließlich
synthetische Daten; die getrennte manuelle Owner-Prüfung weiter unten wird vom Owner selbst mit
der eigenen Instanz und den bewusst ausgewählten App-Aktionen ausgeführt.
Auth-Handoff-Entscheidung und Grenzen: [ADR 028](ADR/028-session-handoff-and-integrated-acceptance.md).
Letzte tatsächliche Ergebnisse: [Verifikation](Verification.md).

## Lokal ohne Server

SDK wie in README bauen, XcodeGen und eine iOS-Simulator-Runtime installieren. Dann:

```sh
bash Scripts/test-integration.sh
```

Vor jedem Build prüft der Runner Argumente, eine etwaige Server-Freigabe und wählt einen
verfügbaren iPhone-Simulator (gebooteter bevorzugt). Fehlt eine Runtime, bricht er sofort mit
klarer Meldung ab. Danach laufen nacheinander Architekturregeln, beide Package-Testtargets,
XcodeGen, das macOS- und das iOS-Integrationsbundle. Jeder fehlgeschlagene Schritt beendet den
Ablauf mit seinem Namen; nachfolgende Schritte laufen nicht. Ohne Freigabe meldet er
**SERVER CONTRACT: NOT RUN**, nicht bestanden.

Die nativen `xcodebuild test`-Aufrufe unterdrücken keine Ausgabe: Testfälle und Buildfortschritt
bleiben im CI-Log sichtbar. Für einzelne Integrationstests gilt eine Standardlaufzeit von 120
Sekunden, maximal 300 Sekunden; ein hängen gebliebener Test wird damit als konkreter Timeout
gemeldet. Der GitHub-Workflow führt Package-Tests in einem eigenen Schritt seriell mit einer
5-Minuten-Grenze aus. `SendModelTests`, `ReturningUnlockServiceTests` und der synthetische
Server-Konfigurationsvertrag laufen serialisiert und mit je einer Minute Testzeitlimit. Der native
Integrationsschritt ist auf 60 Minuten begrenzt.

Native Resultbundles liegen unter `${TMPDIR:-/tmp}/vaultwarden-platform-integration-<UID>/{macOS,iOS}/Logs/Test/`.
Der temporäre Default vermied eine beobachtete XCTest-Bundle-Ladeblockade auf einem externen
Workspace-Volume; die Ursache ist nicht bewiesen. `VW_INTEGRATION_DERIVED_DATA_ROOT` setzt einen
eigenen Pfad. `VW_IOS_TEST_DESTINATION` akzeptiert ausschließlich
`platform=iOS Simulator,id=<UUID>`; die ID muss genau einen verfügbaren iOS-Simulator bezeichnen.
Auch explizite Ziele (einschließlich iPad) werden vor jedem Build aufgelöst und gebootet.
Namen-/OS-Ausdrücke sind wegen möglicher Mehrdeutigkeit für diesen Runner nicht unterstützt.

`bash Scripts/test-integration-preflight.sh` prüft Runner-Preflight und Simulator-Auswahl mit
synthetischen JSON-/Umgebungs-Fixtures und gestubbten Build-Tools: unbekannte Argumente, fehlende
oder falsche Freigabe, jedes fehlende Pflichtfeld, bewegliche Versions-Tags, ungültige TOTP,
Nicht-Simulator-Destination, fehlende Runtime, nur iPad/fremde Runtime/ungültige UDID, malformed
JSON und Booted-Priorisierung. Kein Fixture-Wert darf in der Runner-Ausgabe erscheinen.

## Was die nativen Bundles abdecken

Beide hostlosen Bundles kompilieren die echten gemeinsamen Quellen aus `Composition/`,
`App/Sources/Shared/` und `AutoFillExtension/Sources/Shared/`, ohne `@main`-Start. Je Plattform
17 Testmethoden:

| Bereich | Fall | Nachweis |
| --- | --- | --- |
| Composition | First Run | `serverSetup`, Repository/Model `signedOut`, kein Request, keine Session-Dateivorbereitung |
| Composition | Returning Restore | gespeicherte Identität im Unlock-Route, Repository/Model `locked`, keine Session-ID, kein Request |
| Handoff | Übernahme und Lock | Repository bestätigt dieselbe Session-ID; Lock widerruft Runtime, behält Account, räumt Dateien |
| Handoff | Duplikat/Konkurrenz | doppelte Übergabe idempotent; zweite Runtime wird widerrufen; Snapshot unverändert |
| Handoff | widerrufene Capability | kein Entsperren, Repository `locked`, Account bleibt, sichtbare Fehlermeldung |
| Lifecycle | Lock bzw. Logout während Vorbereitung | per Gate blockierte Vorbereitung; Runtime sofort widerrufen; Cleanup erst nach Vorbereitung; kein spätes Öffnen |
| Dateien | Vorbereitung scheitert | Vault öffnet mit Dateihinweis; Store bleibt für Dateiarbeit geschlossen |
| Dateien | Cleanup scheitert | Recovery-Zustand, widerrufene Runtime, alte/neue Capability öffnen nicht, Retry → `locked` |
| Repositories | Logout | gehaltene Vault-/Send-Repositories verweigern ohne Request |
| Transport | Proxy-Route/503 | genau ein Request mit Proxy-Pfad und Bearer; kein veröffentlichter Sync |
| Hosting | Konfigurationsfehler | echtes Fenster, Layoutgröße > 0 |
| Hosting | RootView-Lebenszyklus | Erscheinen startet Model; entsperrter Tab-Baum erscheint und synchronisiert über die Composition; Recovery → Retry → `locked` ohne weiteren Sync |
| Hosting | Recovery-View allein | Layout nach fehlgeschlagenem Logout-Cleanup |
| Extension | Apple-Controller | Kind-Controller, vier Kanten-Constraints, Frame = Bounds; Ersetzen entfernt Kind, View und Constraints synchron |
| Extension | neue Invocation | vorherige Session sofort widerrufen, Inhalt entfernt |
| Extension | verspäteter Loader | per Gate verzögerter Loader liefert nach neuer Invocation: Session widerrufen, kein Inhalt veröffentlicht |

Isolation: In-Memory-Keychains, eigene `UserDefaults`-Suite, synthetische HTTP-503-Antworten und
injizierte Datei-Lifecycle-Hooks. Die Fixture verweigert den Lauf, falls der Testprozess eine
App Group auflöst; AutoFill-Projektion und OS-Identity-Mutationen scheitern ohne Container vor
jedem Owner-Container, Shared Keychain oder System-Identity-Store. `verify-configuration.swift`
erzwingt hostlose Bundles ohne Entitlements. UIKit-Containment nutzt `willMove`/`didMove`.

Grenzen: Der Accessibility-Baum hostloser Bundles war auf macOS leer; sichtbarer Text wird daher
nicht ausgelesen. Erscheinen wird über echte Lifecycle-Effekte belegt (Model-Start, Sync-Request),
nicht über `host.view != nil`. Keine XCUITests, keine echte `ASCredentialProviderExtensionContext`-
Completion, kein PluginKit/QuickType, keine Biometrie, keine signierten App-Group-Zugriffe.
Controller-Warteschleifen sind zeitlich begrenzte Polls; Composition-Fälle nutzen Gates,
Repository-Stream und beobachtbare Model-Änderungen.

## Server-Schritt ausdrücklich freigeben

Für einen regulären Lauf wird ein isolierter, entsorgbarer Vaultwarden mit exakter Version und
synthetischem Account verwendet. Keine Daten aus einem echten Vault importieren. Der vorbereitete
Passkey-Cipher dient nur als Read-Fixture und wird vom automatisierten Test weder verändert noch
gelöscht. Die Testversion und den Deployment-/Image-Nachweis getrennt dokumentieren; die Routine
bestätigt nicht automatisch den Image-Digest.

### Letzter tatsächlicher Lauf (2026-11-03)

Auf ausdrückliche Erlaubnis wurde eine kurzlebige lokale Docker-Instanz mit
`ghcr.io/dani-garcia/vaultwarden:1.37.5` und synthetischem Testkonto eingerichtet. Der verwendete
Image-Digest war
`sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f`. Der Vertragstest endete
mit `SERVER CONTRACT: all stages passed`; Login/Handoff, Refresh, Sync und Lesen des vorbereiteten
Passkey-Ciphers, Cipher/TOTP-Create/Update/Delete, Attachment-Upload/Download/Delete sowie Text-
und File-Send-Create/Update/Delete bestanden. Das Konto hatte keine Login-TOTP-Challenge, daher
wurde Login-TOTP nicht ausgeübt. Es gab keinen Zugriff auf die Produktionsinstanz; Container,
Netzwerk, synthetische Daten und temporäre Credentials wurden nach Abschluss der Verifikation
entfernt.

Der Lauf deckte zudem echte Vaultwarden-1.37.5-Vertragsdetails auf, die durch lokale Mocks nicht
sichtbar waren: `encryptedFor` ist bei Cipher-Writes erforderlich; Login-URIs werden zusätzlich als
Legacy-`login.uri` gespiegelt; die optionalen Cipher-Typen `bankAccount`, `driversLicense` und
`passport` können als `null` zurückkommen; und Attachment-Uploads liefern eine root-relative URL.
Die Request-/Response-Guards, eng begrenzte Null-/URI-Toleranz und URL-Auflösung wurden angepasst.
Primärquellen: [Cipher-API in Vaultwarden v1.37.5](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/api/core/ciphers.rs),
[Cipher-Modell in Vaultwarden v1.37.5](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/db/models/cipher.rs).

Der File-Send-Lauf deckte zusätzlich auf, dass der verschlüsselte Dateiname selbst Schrägstriche
enthalten kann. Diese Bytes werden im Send-Multipart-Teil bewahrt; vom Nutzer gewählte Attachment-
Dateinamen bleiben weiterhin bereinigt.

Diese Umgebungsvariablen lokal über einen privaten Terminal-/Secret-Manager setzen; **Werte nicht
in Chat, Git, Shell-Traces oder öffentliche Logs kopieren**:

| Variable | Bedeutung |
| --- | --- |
| `VW_TEST_ALLOW_WRITES` | Exakt `isolated-synthetic-account`: explizite Erlaubnis für Testmutationen |
| `VW_TEST_SERVER_URL` | HTTPS-Basisadresse, optional Proxy-Pfad; Debug erlaubt nur für Loopback HTTP |
| `VW_TEST_SERVER_VERSION` | Konkrete Owner-bestätigte Version wie `1.34.3`; `latest`/`1.34` werden verweigert |
| `VW_TEST_EMAIL` / `VW_TEST_PASSWORD` | Ausschließlich synthetischer Account |
| `VW_TEST_PASSKEY_CIPHER_ID` | UUID des vorbereiteten, nur gelesenen Passkey-Logins |
| `VW_TEST_TOTP` | Optional frischer sechsstelliger Login-2FA-Code; bei aktivierter 2FA erforderlich |

```sh
bash Scripts/test-integration.sh --with-server
```

Der Runner prüft Freigabe, Pflichtfelder, Versionsform und TOTP-Form vor dem langen Ablauf. Alle
`VW_TEST_*`-Werte werden aus Package-Baseline, XcodeGen und Xcode-Läufen entfernt. Nur der
finale Package-Schritt erhält sie zusammen mit `VW_TEST_LIVE=1` und nutzt den Baseline-Build.
Der Live-Test prüft alle Felder erneut, bevor Store, SDK-Client oder Request existieren. Kein
Container wird gestartet, kein Account erstellt, kein SDK-Checkout verändert, kein Remote beschickt.

Bestanden ist der Server-Schritt nur, wenn die Ausgabe die Zeile
`SERVER CONTRACT: all stages passed` enthält; ein übersprungener oder abgebrochener Test ist
NOT RUN bzw. FAILED. Die Rohausgabe wird danach gelöscht. Fehler nennen Stage und eine sichere
Klasse (z. B. `http-status-409`), nie Response-Bodies, SDK-Diagnosen oder Credential-Werte.

Bei Login-2FA den Code kurz vor dem finalen Schritt erneuern; für einen bereits bestandenen
nativen Ablauf kann der Server-Schritt separat gestartet werden (Abschlusszeile selbst prüfen):

```sh
cd Packages/AppModules && VW_TEST_LIVE=1 swift test --filter LiveServerContractTests --no-parallel
```

Erwartete temporäre Creates/Deletes: ein synthetischer Cipher samt Attachment und je ein
Text-/Datei-Send. Delete ist das bestehende Client-Delete, kein garantierter serverseitiger
Hard-Purge. Cleanup wird nur für bestätigte eigene IDs versucht; Cleanupfehler lassen den Test
scheitern. Bei unbekanntem Write-Ausgang oder Cleanupfehler Instanz/Account manuell prüfen oder
verwerfen; **nicht** wiederholt Create drücken und keine Namens-Sweeps bauen.

## Owner-manueller Funktionstest mit der Produktionsinstanz

Der Owner testet die App selbst mit der eigenen Instanz. Kein automatisierter CRUD-/Delete-Test
und keine Produktionszugangsdaten im Live-Test-Runner. Das ist eine praktische Prüfung des
ausgewählten App-Builds und kann die Version/Kompatibilität der Produktionsinstanz eingrenzen;
es ist kein vollständiger Serververtrag oder Sicherheitsnachweis.

1. Vor dem Login die in der App konfigurierte Serveradresse prüfen und bestätigen, dass es die
   eigene Instanz ist. Login und 2FA nur direkt in der App eingeben; keine Zugangsdaten, Codes,
   Serveradresse oder Accountidentität protokollieren.
2. Sync abwarten. Bestehende Einträge können lesend geprüft werden.
3. Für gewünschte Schreibpfade ausschließlich selbst ausgewählte, unkritische Testdaten verwenden.
   Ein eigens angelegter temporärer Eintrag kann erstellt, bearbeitet, nach Sync erneut gelesen
   und anschließend gezielt wieder entfernt werden. Attachments, Sends oder Passkeys nur mit
   synthetischem Inhalt und auf Wunsch des Owners prüfen; Geräte nicht versehentlich widerrufen.
4. App sperren und wieder entsperren, falls dieser Lebenszyklus Teil der Abnahme ist. Danach nur
   PASS/FAIL/NOT RUN, App-Buildkennung, OS-Version und bestätigte Serverversion notieren, ohne
   Vault-Inhalte oder Zugangsdaten.
5. Bei falscher Serveradresse, unerwarteter Mutation oder unklarem Write-Ausgang abbrechen und
   erst den konkreten Testdatensatz prüfen; keine ungezielten Wiederholungen durchführen. Rohe
   Logs/xcresult vor einer Weitergabe auf Zugangsdaten und Vault-Inhalte prüfen.

Dieser Owner-Test steht noch aus. Der synthetische Vertragstest oben ist bestanden, belegt aber
weder Produktions-Serverversionskompatibilität noch die Bedienung aller Funktionen in der App.

## Matrix und ehrliche Nachweise

`bash Scripts/test-disposable-server.sh` startet für den ergänzenden lokalen Vertrag einen
flüchtigen, nur an `127.0.0.1` gebundenen Container mit gepinntem 1.37.5-Image-Digest. Der Test
erzeugt Account und Schlüssel selbst, übt langen Dateinamen und Login-TOTP aus, aktualisiert einen
Cipher gleichzeitig mit zwei getrennten App-Sitzungen und bestätigt, dass der Einzelgeräte-Widerruf
auf diesem Server mit 404 scheitert. Der erste Konfliktlauf zeigte, dass zwei aus demselben Snapshot
gesendete Änderungen verschiedener Felder beide angenommen wurden und ein Feld verloren ging.
Daraufhin sendet die App bei Cipher- und Passkey-Updates `lastKnownRevisionDate`; Creates lassen das
Feld aus. Im wiederholten Lauf wartete der Test 2,1 Sekunden nach dem gemeinsamen Snapshot:
Vaultwarden 1.37.5 nahm den aktuellen Write an, lehnte den veralteten mit HTTP 400 ab, und der
angenommene Feldwert blieb erhalten. Der Server vergleicht mit einer Toleranz von einer Sekunde;
das schützt nicht vor jedem engeren Race und belegt keine atomare Merge-Garantie. Der Runner entfernt
Container und temporäre Logs; er greift nicht auf
Produktionsdaten oder konfigurierte Zugangsdaten zu.

| Pfad | Automatischer Nachweis | Stand | Zusätzlicher echter Nachweis |
| --- | --- | --- | --- |
| App/Auth | Composition-/Handoff-/Lifecycle-Fälle oben | lokal bestanden, beide Plattformen | Fenster-/Szenenwechsel, echte Eingabe im signierten App-Lauf |
| Native UI | Hosting- und Apple-Controller-Fälle oben | lokal bestanden, beide Plattformen | PluginKit, AutoFill-Auswahl, reale ExtensionContext-Completion |
| Konfiguration Live-Test | positiver Fall, 21 Einzelfeld-Verweigerungen, Redaction, RFC-6238-Referenzvektoren | lokal bestanden | – |
| Login/TOTP | Password-Login/Handoff und echter TOTP-Challenge-Login auf isoliertem synthetischem Account | bestanden auf Vaultwarden 1.37.5 am 2026-11-06 | signierte UI-/Gerätepfade und Produktionsversion |
| Refresh | abgelaufener testlokaler Datensatz, echte Lease/Intent/Rotation, höhere Generation, gleicher Scope/Account, neue Expiry | bestanden | zwei unabhängige Prozesse, Crash/Kill/Restart |
| Cipher/TOTP | Create, Read, Edit; Passwort/TOTP-Seed/Notiz/URIs erhalten, Revision steigt; Code gleich RFC-6238-Referenz im gemessenen Zeitfenster; Delete | bestanden auf Vaultwarden 1.37.5 | Org-/Collection-Datensätze |
| Konkurrierende Cipher-Writes | Zwei getrennte App-Sitzungen schreiben verschiedene Felder derselben Cipher aus demselben Snapshot; Update sendet `lastKnownRevisionDate` | Auf Vaultwarden 1.37.5 wurde nach 2,1 s der veraltete PUT mit HTTP 400 abgelehnt; der angenommene Feldwert blieb erhalten | Andere Serverversionen; Race innerhalb der serverseitigen 1-s-Toleranz; sichtbare Konflikt-/Recovery-UI |
| Attachments | Upload, Download, Bytevergleich, Delete mit kleiner synthetischer Datei | bestanden auf Vaultwarden 1.37.5 | große Dateien, Disk-full/Memory, Scoped-Access-Gerätepfade |
| Sends | Text und Datei: Create, Read/Edit, Update, Delete; echter SDK-Dateiname mit verschlüsselter Länge über 255 Bytes | bestanden auf Vaultwarden 1.37.5 | öffentlicher Empfangslink, Passwort/Limits, UI-Pfade |
| Geräte | Zwei synthetische Geräte listen; Einzelwiderruf meldet 404, Gerät bleibt bestehen | Einzelwiderruf auf Vaultwarden 1.37.5 nicht unterstützt; App zeigt Fehler | unterstützten Serververtrag finden und echten Widerruf nachweisen |
| Passkeys | vorbereitete Passkey-Metadaten lesen | bestanden; nur vorbereiteter Read-Fixture | OS-Registration, Assertion, User Verification, Server-Upsert |

Für manuelle Passkey-Abnahme: synthetische Test-RP, signierte App/Extension, exakte Plattform-
und Serverversion notieren; Register → Sync im offiziellen Client → Assert → Lock → erneute
Assertion muss erneutes Unlock verlangen. Nach jedem Schritt PASS/FAIL/NOT RUN mit redigiertem
Nachweis. Kein automatischer Live-Testpass schließt diese OS-Pfade.

Bei jedem Lauf Code-Commit, Xcode/OS/Simulator, Deployment-Version und PASS/FAIL/NOT RUN festhalten.
Keine Secrets oder unredigierten `xcresult`-/SDK-Logs hochladen. Der Ablauf ist kein Security-Audit.


## Signierter Installationslauf — 2026-11-08

Release-App und AutoFill-Extension (Build 3) wurden mit lokaler, ignorierter Team-Konfiguration für
macOS und echte iOS-Geräte gebaut. Die Installation und der Prozessstart auf iPhone (iOS 27.2),
iPad (iPadOS 27.0.1) und Mac wurden mit den Plattformwerkzeugen bestätigt. Vom Owner gezeigte
App-Ansichten belegen Login und Vault-Sync auf iPhone und Mac; daraus folgt noch keine vollständige
AutoFill-/Passkey-/Biometrie-/Lifecycle-Abnahme. Signierungsprofile und Gerätekennungen bleiben lokal.

Auf dem Mac verweigerte der geschützte App-Group-Container den Dateizugriff mit EPERM: Die
Signierungsprofile enthielten die App-Group-Freigabe nicht. `REGISTER_APP_GROUPS = YES` lässt
Xcode die Gruppe für App und Extension provisionieren, wie in
[Apples Anleitung](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
beschrieben. Neu erzeugte Bundles bestanden die tiefe, strenge Signaturprüfung; beide Profile
enthielten anschließend die konfigurierte Gruppe. Die installierte App konnte die gemeinsame
Lockdatei erstellen und der Startfehler trat nicht mehr auf. Die Speicherkennungen wurden nicht
geändert. Ein neuer negativer Konfigurationsfall verhindert das Abschalten der Registrierung.

Ein deaktivierter Systemanbieter wird als `suggestionsDisabled` bei weiterhin aktuellem Dateicache
getrennt von einem Cache-/Sync-Fehler geführt. Dieser Zustand erzeugt keine falsche Vault-Warnung,
bleibt aber für die Auflösung ungewisser Credential-Writes ausdrücklich nicht vollständig repariert.
Tests prüfen den Wechsel zu aktivierten Vorschlägen, den Erhalt offener Recovery-Vorgänge sowie
sichtbare Fehler bei veraltetem oder fehlendem Cache. 867 AppModules-Tests in 102 Suites bestehen;
Konfigurationsprüfungen einschließlich vier Ablehnungsfixtures bestehen ebenfalls.

Die iPad-Orientierungen werden nun als echte Info.plist-Eigenschaft erzeugt; Xcode übernahm den
vorherigen variantspezifischen Build-Setting-Schlüssel nicht. Produkttexte verwenden „client“
statt „learning client“. Der erfolgreiche SDK-CI-Nachweis für `4897c20` ist
[Lauf 42466566238](https://github.com/temmiland/vaultwarden-native/actions/runs/42466566238);
die Änderungen aus diesem Installationslauf benötigen einen neuen CI-Lauf. Der lokale native
Integrationslauf mit der neuen Clock-Session besteht mit 18 macOS- und 19 iOS-Simulatortests.
Build 3 ist auf Mac und iPad installiert und gestartet; die iPhone-Installation benötigt aktuell
eine wiederhergestellte Geräteverbindung.


### Gerätebefund: iOS-Freigabe und monotone Zeit

Die erste Gerätefassung verwendete für persistierte AutoFill-Freigaben `kern.bootsessionuuid`.
[Apple dokumentiert die Sperre dieses Sysctls seit iOS/iPadOS 18](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-18-release-notes).
Ein Simulatornachweis reichte hier nicht aus: Auf echten iOS-Geräten ließ sich damit die
Freigabe nicht publizieren; der nachfolgende Cache blieb gesperrt.

Build 3 ersetzt den Boot-Identifier durch einen ausdrücklich anders benannten, lebenden
Clock-Session-Nachweis im App Group Container. App und Extension können einen gemeinsamen
Kernel-Dateilock weitertragen. Ohne lebenden Teilnehmer wird immer eine neue zufällige ID erzeugt;
persistierte Dateien allein beleben die alte ID nicht wieder. Ein Geräteneustart beendet alle
Teilnehmer und ihre Locks. Die Änderung verwendet weder einen Wall-Clock-/Uptime-Schätzwert noch
einen privaten Systemaufruf. Auch ein vollständiges Beenden aller beteiligten Prozesse kann nun
erneutes Entsperren in der Haupt-App erforderlich machen; „never“ überlebt diesen Verlust nicht.

Grant-Schema 5 trennt diesen Nachweis vom alten Boot-UUID-Schema 4. Alte Freigaben werden unter
dem bestehenden Token-Store-Lock widerrufen; private Kontodaten werden nicht gelöscht. Derselbe
Container-/Lock-Kontext wird an Token-Transaktionen weitergereicht. Tests prüfen mehrere
Teilnehmer, einen separaten Prozess, das Ende des letzten Teilnehmers, persistierte Restdateien,
Symlinks und die Migration alter Freigaben. Der echte Geräte-Neustart und die anschließende
manuelle AutoFill-Abnahme bleiben ausdrücklich noch zu prüfen.


## App-Icon und Tool-Download-Korrektur — Build 4

Das offizielle Vaultwarden-SVG (Upstream `17b159beff4b892f07f61f38ce2fe452e55251c1`)
ist als Quelle erhalten; alle elf App-Icon-Rastergrößen wurden daraus neu erzeugt. iOS/iPadOS
verwenden ein opakes 1024px-Icon, macOS einen weißen abgerundeten Hintergrund. SVG-Masken werden
beim Rendern geometriegleich in Vektor-Clipping umgesetzt, damit die fünf Aussparungen scharf bleiben.
Quelle, Autorenangabe und AGPL-Lizenztext stehen in den Third-Party-Notices und im Materialinventar.
Beide signierten Release-Builds einschließlich Extensions und strenger Signaturprüfung bestanden.
Build 4 wurde auf iPhone, iPad und Mac installiert. Mac und iPad starteten; der automatische
Start auf dem iPhone wurde wegen der Gerätesperre abgelehnt, nicht wegen eines Installationsfehlers.

Der erste CI-Versuch für `bb11cbf` endete vor dem SDK-Build mit Curl-Transferfehler 56 beim
XcodeGen-Download; die Quellenprüfung bestand. Der Owner startete denselben Commit erneut,
und der Download gelang. Die Downloader haben nun jeweils zwei offizielle Endpunkte mit
unverändert gepinnter SHA-256 und Versionsprüfung. Fehlerhafte/partielle Antworten werden
nicht in den Tool-Cache übernommen. Zehn deterministische Offline-Fixtures prüfen beide
Wrapper bei erfolgreichem Download, Transportfehler, Prüfsummenfehler und vollständigem
Ausfall; dieser Test läuft künftig vor der echten Formatierung in CI. Zusätzlich bestanden
frische echte Downloads beider Tools ohne vorhandenen Cache.
