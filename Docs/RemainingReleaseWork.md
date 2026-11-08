# Zentrale Review- und Arbeitscheckliste für GPT-6-Luna

Stand: 2026-11-08; vorherige Review/Umsetzung vom 2026-11-02 und lokaler Serververtrag vom 2026-11-03. Repository: `vaultwarden-macos`; geprüfter HEAD:
`de5bd0aed51dc87d95ff97d1ca3680968d8f72c3` **plus vorhandene uncommittete Codeänderungen**.
Ein Commit allein reproduziert diesen Arbeitsstand nicht. Nach dem Review folgte der ausdrückliche
Auftrag, die Liste umzusetzen. Die vorhandenen Änderungen wurden erhalten und die unten genannten
Fixes ergänzt. Kein Commit, Push, Tag oder Release. Die aktuelle Freigabeentscheidung bleibt
Quellcode; Geräteabnahmen sind auf ausdrückliche Owner-Antwort separat.

## Vertieftes Code-Review — eigener Code, abgeschlossen am 2026-11-06

**Ergebnis:** Der untersuchte Stand ist für eine öffentliche Quellcode-Veröffentlichung noch
nicht abschließend freigegeben. Die konkreten offenen Punkte stehen in dieser Datei: insbesondere
F-16 (SDK-Kryptografie-Advisories), F-18/F-21 (vollständiger Release-Stand), F-19
(reproduzierbarer Build) und die unten aufgeführten Produktbefunde F-26–F-35. F-17
(SDK-Lizenz/Notices) wurde am 2026-11-07 für Source-only geklärt.
Für mehrere davon sind Codekorrekturen umgesetzt; ihre noch offenen Nachweise stehen unmittelbar
beim jeweiligen Befund. Für eine installierbare App kommen die separat vereinbarten Geräte-,
Server- und Sicherheitsabnahmen hinzu. Die Prioritäten kennzeichnen den Handlungsbedarf; ein Geräte- oder
Servereffekt wird nur dort als bestätigt bezeichnet, wo er tatsächlich nachgewiesen wurde.

**Umfang und Methode:** Die eigenen Produktionsbereiche App und Extension, Composition,
AppFeature, AuthPresentation, AutoFillContract und AutoFillData, AutoFillFeature,
SecurityStorage, PlatformServices, Networking, Data, Domain, BitwardenSDKAdapter sowie Vault-,
Settings- und Send-Presentation wurden anhand des Quelltexts auf Sicherheitsgrenzen,
Datenintegrität, Fehlerbehandlung, Lebenszyklus und Aufrufketten untersucht. Auch die zuvor
abgeschnittenen Vault-Ansichten wurden nachgelesen. Konfiguration, CI und die eigenen Build-,
Prüf- und Integrationsskripte wurden in die Prüfung einbezogen. Drittbibliotheken und generierte
SDK-Bindings waren nicht Gegenstand einer Implementierungsprüfung; deren Mitveröffentlichung und
bekannte Abhängigkeiten bleiben unter F-16/F-17 erfasst.

Alle 137 eigenen Paket- und Plattformintegrationstestdateien (24.679 Zeilen) wurden inventarisiert
und automatisiert auf Teststruktur, Assertions und auffällige Konstrukte untersucht; Testfälle und
Fixtures zu den risikoreichen Aufrufketten wurden zusätzlich manuell mit dem Produktcode
abgeglichen. Dies ist **keine vollständige zeilenweise manuelle Prüfung sämtlicher Testdateien**
und kein unabhängiges Sicherheitsaudit. Bestehende lokale Änderungen gehören zum geprüften
Arbeitsstand; der angegebene HEAD allein bildet ihn nicht ab.

**Früherer Prüfaufruf am 2026-11-06:** `bash Scripts/test-packages.sh` bestanden: SDK-Smoke 1,
AuthPresentation 69 und AppModulesArchitecture 830 Swift-Testing-Tests sowie 2 XCTest-Tests;
`existingServerFlows()` wurde mangels aktivierter synthetischer Testumgebung übersprungen.
`swift Scripts/check-architecture.swift`, `swift Scripts/check-source-secrets.swift` und
`swift Scripts/check-source-materials.swift` bestanden; der Secret-Scan ist heuristisch und die
Materialprüfung keine Lizenzfreigabe. Auch `test-architecture-rules.sh`,
`test-configuration.sh` und `test-source-secrets.sh` bestanden einschließlich ihrer negativen
Fixtures. Der Konfigurationstest belegt keine signierten Entitlements. Testprotokoll:
`${TMPDIR:-/tmp}/vw-review-20261106-packages.log`. Es wurden in dieser Runde weder ein Live-Server
noch Geräte, Signing, Remote-CI oder ein isolierter SDK-Neubau erneut abgenommen; ältere Nachweise
weiter unten bleiben auf ihren jeweiligen Stand begrenzt.

**Umsetzungsnachweis 2026-11-06:** Nach den Codekorrekturen bestanden Pakettests mit
841 Swift-Testing-Methoden im Architekturpaket (Live-Server-Test übersprungen), 69 im
AuthPresentation-Paket, ein SDK-Smoke und zwei XCTest-Tests. Der native Integrationsrunner
bestand für macOS und den iOS-Simulator; ein Live-Server wurde nicht gestartet. Beide Apps und
Extensions bauten unsigned in Debug unter Xcode 27.2. Nach anschließenden zusätzlichen Tests und
der PSL-Validierung bestanden die gezielten Passkey- und URI-Matching-Suites. Die Paket-/Build- und
Integrationsprotokolle liegen unter `${TMPDIR:-/tmp}/vw-implement-20261106-final3.log`,
`${TMPDIR:-/tmp}/vw-implement-build-final.log` und `${TMPDIR:-/tmp}/vw-implement-integration-20261106.log`.
Der aktualisierte RustSec-Audit meldet weiterhin elf Vulnerability-Einträge (F-16). Ein signierter
Geräte-, Produktions- oder finaler Fresh-Clone-Nachweis folgt daraus nicht.

**Aktuellster isolierter SDK-Kandidatentest 2026-11-06:** Das experimentell aktualisierte
XCFramework wurde außerhalb des Arbeitsbaums gegen eine Kopie des aktuellen Quellstands geprüft:
SDK-Smoke 1, AuthPresentation 69, AppModulesArchitecture 845 und 2 XCTest bestanden; zwei
Live-Server-Tests waren übersprungen. Native Integrationsschemata bestanden macOS und iOS
Simulator jeweils 18/18. macOS-/iOS-App und AutoFill-Extensions bauten unsigned in Debug/Release.
Der installierte SDK-Pin im Arbeitsbaum wurde nicht ersetzt. Zwei Advisories (F-16), signierte
Geräte und Remote-CI bleiben offen; die Source-only-Lizenzwahl wurde später in F-17 geklärt.

**Nachprüfung nach F-35 2026-11-06:** `bash Scripts/test-packages.sh` bestand mit SDK-Smoke 1,
AppModulesArchitecture 846 Tests/100 Suites, AuthPresentation 69 Tests und 2 XCTest; die
eingebetteten Live-Serverfälle waren übersprungen. Der getrennte
`bash Scripts/test-disposable-server.sh`-Lauf gegen den gepinnten flüchtigen Vaultwarden-1.37.5-
Container bestand Login-TOTP, langen verschlüsselten Send-Dateinamen und stale-write-Ablehnung;
Einzelgeräte-Widerruf bleibt auf diesem Server nicht unterstützt. SwiftFormat-, Architektur-,
Source-Material- und `git diff --check`-Prüfungen bestanden nach den letzten Dokumentations- und
Inventaränderungen. Geräte, Produktion, Signing und Remote-CI wurden dadurch nicht abgenommen.
Die spätere F-17-Änderung klärt die Lizenzwahl für Source-only; daraus folgt keine Freigabe eines
Binärartefakts.

### F-26 — P1 — Systemvorgaben für Passkey-Assertion werden nicht weitergegeben

**Umsetzung 2026-11-06:** Erlaubte Credential-IDs werden in der Liste gefiltert und bei der Assertion erneut geprüft. Beide Apple-Anfragewege reichen die Verification-Präferenz weiter; `required` verlangt zusätzlich das UV-Flag in ausreichend langen Authenticator-Daten. Synthetische Pakettests bestehen; Geräteabnahme bleibt offen.

- [x] Apple-Anfrage und Assertion an erlaubte Credential-IDs und User-Verification binden;
  mehrere Credential-IDs und fehlende Verifikation synthetisch prüfen.
- [ ] Beide Passkey-Anfragewege auf signierten Geräten abnehmen.

**Fundstellen:** `AutoFillExtension/Sources/Shared/CredentialProviderViewController.swift:420`, `Packages/AppModules/Sources/BitwardenSDKAdapter/SDKWebAuthnAssertionRequest.swift:10`.

**Beleg:** `ASPasskeyCredentialRequestParameters` enthält `allowedCredentials` und
`userVerificationPreference` (lokaler Apple-SDK-Header). Der Listenpfad übergibt an `matching`
nur die RP-ID, und `SDKWebAuthnAssertionRequest.swift` setzt `userVerification` stets auf
`preferred`. Somit können unzulässige Vorschläge erscheinen und die Anforderung `required`
wird im SDK-Aufruf abgeschwächt. Ob das Betriebssystem bzw. der Relying Party die konkrete
Antwort anschließend ablehnt, ist nicht geprüft; dies ist keine Behauptung eines bestätigten
Fremdzugriffs.

### F-27 — P1 — AutoFill-Identitäten ignorieren URI-Match-Einstellungen

**Erweiterung auf Owner-Auftrag 2026-11-07:** Passwort-/TOTP-QuickType wird für explizite und
standardmäßige Base-Domain-Regeln wiederhergestellt. Die SDK-Projektion erhält diese Regeln
getrennt von den übrigen URIs; PSL und private Suffixe bestimmen die publizierte Domain.
Identifizierte Anfragen müssen eine neue Domain-Identität tragen und werden vor Ausgabe gegen
aktuelle URI-Regeln, Benutzername, Cache und Unlock-Proof geprüft. Host/Port, Prefix, Exact,
Regex und Never werden nicht als breitere Domain-Identitäten publiziert. Alte URL-Identitäten
bleiben abgelehnt. Geräte-/OS-Abnahme steht weiterhin aus.

**Umsetzung 2026-11-06:** Sicherheitsseitig konservative Übergangslösung: Passwort- und TOTP-Systemidentitäten werden nicht mehr publiziert; bereits im OS vorhandene identifizierte Passwort-/TOTP-Anfragen werden abgelehnt, da die Anfrage keine verlässliche Ziel-URL enthält. Die interaktive, anhand der Anfrage gefilterte Auswahl und Passkey-Identitäten bleiben bestehen. Dadurch entfallen zunächst Passwort-/TOTP-QuickType-Vorschläge. Gerätetests und eine später nachgewiesene sichere Wiederherstellung der Vorschläge bleiben offen.

- [x] Password-/TOTP-QuickType und alte direkte Identitäten bis zum Nachweis einer sicheren
  Abbildung unterbinden; interaktive gefilterte Auswahl und Passkeys erhalten.
- [ ] `never`, exakte Pfade und Regex auf signierten Geräten abnehmen und eine sichere
  Wiederherstellung der Passwort-/TOTP-QuickType-Vorschläge prüfen.

**Fundstellen:** `Packages/AppModules/Sources/BitwardenSDKAdapter/SDKVaultSessionSource.swift:137`, `Packages/AppModules/Sources/Data/CredentialIdentityPublisher.swift:8`.

**Beleg:** `SDKVaultSessionSource.currentOutput()` übergibt sämtliche `login.uris` nur als
Strings an `CredentialIdentityMapper`. Dieser publiziert sie ohne Match-Modus als Passwort- und
TOTP-Identitäten. Der QuickType-Pfad in `CredentialProviderViewController` löst anschließend
anhand der Cipher-ID auf, ohne URI-Matching erneut anzuwenden. Der reguläre Picker dagegen nutzt
`URIMatching`. Ob und für welche Anfrageformen das OS diese Identität anbietet, benötigt eine
Geräteprüfung; die Missachtung der Einstellung im Publikationspfad ist im Code sichtbar.

### F-28 — P1 — Send-Erfolg mit unlesbarer Antwort kann als erneut speicherbar erscheinen

**Umsetzung 2026-11-06:** Text-/Datei-Registrierung unterscheidet jetzt vor Versand erkennbare Fehler und eindeutige 4xx-Ablehnungen von unbekanntem Ausgang nach Transportfehler, Redirect, 408/409/429, 5xx oder unlesbarer 2xx-Antwort. Bei unbekanntem Ausgang schließt die Oberfläche den Entwurf, aktualisiert die Liste und verlangt Serverprüfung vor einer erneuten Erstellung; ein gleichzeitiger Cleanup-Fehler bleibt sichtbar. Synthetische Tests decken Antworten, Transportabbruch, Dateiregistrierung und UI ab. Kein dauerhaftes serverseitiges Idempotenzprotokoll; Live-Nachweis separat.

- [x] Mutationen nach Versand in sicher nicht gesendet, abgelehnt, unklar und bestätigt
  unterscheiden. Bei unklarer oder erfolgreicher, aber unlesbarer Antwort die Erstellung nicht
  blind erneut anbieten; Serverzustand laden und Wiederherstellung sichtbar machen. Text- und
  Datei-Send sowie Transportabbruch, 2xx mit beschädigter Antwort und Fehler nach Registrierung
  mit synthetischem Transport prüfen.

**Fundstellen:** `Packages/AppModules/Sources/Data/DefaultSendRepository.swift:112`, `Packages/AppModules/Sources/SendPresentation/Models/SendModel.swift`.

**Beleg:** `DefaultSendRepository.performSave` erhält eine erfolgreiche HTTP-Antwort und wirft
bei `decodeResponse`-Fehler `.invalidResponse`. `SendModel.saveDraft` behandelt diesen Fehler
nicht als bestätigte/unklare Mutation und belässt den Entwurf. Auch ein Transportfehler kann nach
Serverannahme eintreten. Dadurch ist eine doppelte Erstellung beim erneuten Speichern möglich.

### F-29 — P2 — Clipboard-Cleanup hängt an der Lebensdauer des View-Clients

**Umsetzung 2026-11-06:** Der Callback hält den Pasteboard-Adapter statt des Service fest. Regression prüft Service-Freigabe und unverändertes bzw. zwischenzeitlich geändertes Clipboard. Prozessende unter macOS und Geräteabnahme bleiben separate Plattformgrenzen.

- [x] Den geplanten Cleanup unabhängig vom Lebenszyklus des Clipboard-Service ausführen und
  weiterhin nur bei unverändertem `changeCount` löschen. Fall: kopieren, View/Session freigeben,
  Ablauf ausführen; anderer Clipboard-Inhalt darf nicht gelöscht werden.

**Fundstelle:** `Packages/AppModules/Sources/PlatformServices/SecurePasteboardClient.swift:119`.

**Beleg:** `ClipboardAutoClearService.copySecret` verwendet im geplanten Callback `[weak self]`;
`RootView` erstellt den Service für die jeweilige View. Wird er vor Ablauf freigegeben, kehrt der
Callback ohne Löschen zurück. Auf macOS existiert laut Adapter keine OS-seitige Ablaufzeit.
Ein tatsächlicher Leak oder eine konkrete SwiftUI-Freigabereihenfolge wurde nicht reproduziert.

### F-30 — P2 — Fehlende Public-Suffix-Datei erweitert Matching statt zu sperren

**Umsetzung 2026-11-06:** Fehlende, leere und ohne vollständige Abschnittsmarkierungen gebündelte Listen liefern keine registrierbare Domain. Regression prüft leere Listen und getrennte `github.io`-Mandanten.

- [x] Ressourcenfehler als ungültige Liste behandeln und Domain-Matching verweigern; Regression
  mit fehlender/leerer Ressource und getrennten Mandanten einer privaten Suffix-Domain ergänzen.

**Fundstelle:** `Packages/AppModules/Sources/AutoFillData/PublicSuffixList.swift:37`.

**Beleg:** `PublicSuffixList.loadBundled()` erzeugt bei fehlender Ressource eine leere Liste.
`registrableDomain` verwendet daraufhin trotzdem die implizite `*`-Regel. Für z. B. verschiedene
`github.io`-Mandanten kann dadurch dieselbe Basisdomain berechnet werden. Dies widerspricht dem
Kommentar zum Fail-closed-Verhalten; regulär ist die Dataset-Datei gebündelt.

### F-31 — P2 — Dateiname eines verschlüsselten Sends wird ab 256 Bytes ersetzt

**Umsetzung 2026-11-06:** Der Multipart-Builder übernimmt gültige opake Dateinamen unverändert unabhängig von 255 Bytes; ungültige opake Namen werden vor Body-Erstellung abgelehnt. Multipart- und Direct-Upload-Regressionen decken lange synthetische Ciphertexte ab. Ergänzend bestand am 2026-11-06 ein Ende-zu-Ende-Lauf mit echten, frisch erzeugten SDK-Schlüsseln auf einem flüchtigen lokalen Vaultwarden-1.37.5-Container: Der beim Server registrierte verschlüsselte Dateiname war länger als 255 Bytes, Upload, erneutes Lesen des entschlüsselten Namens und Löschen bestanden. Der Container wurde entfernt.

- [x] Gültige opake Send-Dateinamen unverändert transportieren und lange synthetische
  Ciphertexte beim direkten Upload prüfen.
- [x] Lange Dateinamen mit echter SDK-Verschlüsselung und synthetischem Server end-to-end prüfen.

**Fundstellen:** `Packages/AppModules/Sources/Data/DefaultSendRepository.swift:250`, `Packages/AppModules/Sources/Networking/MultipartFileBody.swift:98`.

**Beleg:** `DefaultSendRepository.upload` setzt `preserveSlashesInFileName: true`, dennoch ersetzt
`MultipartFileBody.sanitizedFileName` jeden Namen über 255 UTF-8-Bytes durch `attachment`.
Die Länge bezieht sich hier auf den verschlüsselten Wert, nicht den ursprünglichen Dateinamen.
Eine konkrete Serverauswirkung ist noch nicht live reproduziert.

### F-32 — P3 — macOS-Menü kann geschlossenes Hauptfenster nicht neu erstellen

**Umsetzung 2026-11-06:** Das Hauptfenster ist eine eindeutig benannte `Window`-Scene; Menü und Hotkey verwenden den gespeicherten SwiftUI-`openWindow`-Aufruf. Die signierte macOS-Geräteabnahme bleibt offen.

- [x] Menü und Hotkey öffnen die benannte Hauptfenster-Scene über den Scene-Mechanismus.
- [ ] Nach Schließen des Hauptfensters Menüeintrag und Hotkey auf einem signierten macOS-Build prüfen.

**Fundstelle:** `App/Sources/VaultwardenMac/VaultwardenMacApp.swift:24`.

**Beleg:** `AppDelegate.bringToFront()` aktiviert die App und sucht ausschließlich ein vorhandenes
`NSApp.windows`-Fenster mit `canBecomeKey`. Es erstellt selbst kein Fenster; ob SwiftUI in der
konkreten Lebenszykluskonfiguration ein passendes Fenster vorhält, ist noch nicht abgenommen.

### F-33 — P2 — Vaultwarden 1.37.5 unterstützt den verwendeten Gerätewiderruf nicht

- [x] Den bestätigten 404 verständlich anzeigen und die vorhandene Geräteliste erhalten; den
  Fehlerfall im UI-Modell und gegen den lokalen Server prüfen.
- [ ] Vor einem Versprechen von Einzelgeräte-Widerruf eine tatsächlich unterstützte
  Server-Schnittstelle für die Zielversion nachweisen und den bestätigten Effekt erneut testen.

**Beleg 2026-11-06:** Auf einer kurzlebigen lokalen Vaultwarden-1.37.5-Instanz erzeugte der
Test zwei synthetische Geräte. `GET /api/devices` lieferte beide, `DELETE /api/devices/{id}`
antwortete mit 404; erneutes Lesen zeigte das Gerät weiterhin. Das [Server-Routing der getesteten
Version](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/api/core/accounts.rs)
enthält das Listing, aber keinen entsprechenden Delete-Endpunkt. Die App meldet deshalb bei 404 oder 405,
dass das Gerät fehlen oder der Server den Einzelwiderruf nicht unterstützen kann, und verweist
zur Prüfung auf die Geräteverwaltung im Web Vault. Daraus folgt keine Zusicherung, dass diese dort
Einzelwiderruf anbietet. Die übrige Servermatrix bleibt unter F-13 offen.

### F-34 — P2 — SDK-Artefaktinventar scheitert bei `/tmp`-Alias

- [x] Framework-Wurzel und aufgezählte Dateipfade vor der relativen Pfadberechnung identisch
  kanonisieren und bei Verlassen der Wurzel abbrechen.

**Nachweis 2026-11-06:** Der experimentelle SDK-Neubau lag unter `${TMPDIR:-/tmp}`; Foundation gab
für die kanonisierte Wurzel `/tmp`, für Einträge aber `${TMPDIR:-/tmp}` zurück. Das bisherige
Inventar meldete deshalb trotz vorhandenem `Info.plist` ein ungültiges Framework. Das korrigierte
Skript erzeugte unter diesem Alias ein Inventar und verifizierte es bytegleich gegen eine Kopie
außerhalb des Repositories (76 Dateien). Symlink-Prüfung und Begrenzung auf die Framework-Wurzel bleiben aktiv.

### F-35 — P2 — Gleichzeitige Vault-Edits brauchen Versionsschutz

- [x] Bei Updates `lastKnownRevisionDate` aus der bearbeiteten Cipher-Revision senden; bei Creates
  auslassen. Cipher- und Passkey-Updatepfade sowie Wire-Format abdecken.
- [ ] Konflikt-/Recovery-Verhalten auf der tatsächlichen Zielserverversion und im signierten UI
  abnehmen; Restrisiko der Server-Toleranz von einer Sekunde dokumentieren.

**Befund und Korrektur am 2026-11-06:** Der erste isolierte Vaultwarden-1.37.5-Zwei-Sitzungs-Lauf
reproduzierte Datenverlust: beide aus demselben Snapshot gestarteten Feldänderungen wurden
angenommen, danach fehlte ein Feld. Die App sendet jetzt bei Cipher- und Passkey-Updates
`lastKnownRevisionDate` aus der Basisrevision; Create-Requests enthalten es nicht. Ein Wire-Contract-
Test prüft beide Fälle. Der wiederholte isolierte Serverlauf wartete 2,1 Sekunden nach dem
gemeinsamen Snapshot, erhielt für den aktuellen Write Erfolg und für den veralteten HTTP 400; nach
erneutem Sync blieb der angenommene Feldwert erhalten. Verwendet wurden nur ein synthetischer
Account und flüchtiger Loopback-Docker.

Der geprüfte [Vaultwarden-1.37.5-Handler](https://github.com/dani-garcia/vaultwarden/blob/1.37.5/src/api/core/ciphers.rs#L2880-L2949)
lehnt eine Revision nur ab, wenn der Zeitabstand die ganzzahlige Ein-Sekunden-Schwelle übersteigt.
Damit bleibt ein enger Race innerhalb dieser Toleranz; die Implementierung ist keine atomare
Compare-and-swap-Garantie und verhindert nicht jeden möglichen Last-write-wins-Verlust. Die erste
Reproduktion und die erfolgreiche Wiederholung sind in [IntegratedAcceptance.md](IntegratedAcceptance.md)
festgehalten. Produktionsserver und sichtbare Konflikterholung wurden nicht getestet.

### F-36 — Produktauftrag 2026-11-07 — Natives Passwortspeichern vor Veröffentlichung

Auf ausdrücklichen Owner-Auftrag kommt Passwortspeicherung auf iOS/iPadOS ab 26.2 zum Umfang
hinzu. Apple stellt `ASSavePasswordRequest` nicht für macOS bereit; dort bleibt der vorhandene
App-Editor zuständig. Eine zusätzliche Browser-Erweiterung ist nicht beauftragt.

Implementiert sind die Apple-Speicheranfrage samt Capability, Bestätigungsoberfläche, neue
Login-Einträge und ausdrücklich ausgewählte Updates vorhandener Einträge. Der SDK-Draft-Mapper
erhält beim Update bestehende Felder, URI-Regeln und Passkeys; der HTTP-Aufruf verwendet die
ursprüngliche Serverrevision. Ohne sichtbare Bestätigung erfolgt kein Schreiben. Re-Prompt,
Read-only, unerkannte Payloads und veraltete Unlock-/Cache-Zustände bleiben gesperrt.

Das gemeinsame Mutationsjournal enthält ausschließlich Metadaten und unterscheidet jetzt
Passwort- von Passkey-Writes. Unklare Ergebnisse werden nicht automatisch wiederholt. Bestätigte
Passwörter werden in den verschlüsselten Cache übernommen; abbildbare Domain-Identitäten werden
inkrementell publiziert. Eine vollständige autoritative Synchronisierung kann den exakten
bestätigten Cipher anhand von ID und SHA-256-Hash des gesendeten Passwort-Ciphertexts auflösen,
auch wenn strikte URI-Regeln keine QuickType-Identität erlauben. Die bloße Existenz der ID reicht
bei einem Update nicht; Klartext oder ein Klartext-Passwortprüfwert wird nicht gespeichert.
Ein unbestätigter Create bleibt bis zur bewussten Wiederherstellungsprüfung gesperrt.

Pakettests prüfen QuickType-Regeln, Widerruf, Journal-Roundtrip, unklare/erfolgreiche Writes,
exakte Wiederherstellung und den Server-Revisionsschutz. Native iOS-Tests prüfen das Hosting des
neuen Apple-Anfragewegs mit isoliertem Fehlerzustand. Echte signierte Systemanfragen und der
Servereffekt dieser neuen Extension-Strecke bleiben eine Geräte-/Serverabnahme; synthetische
Tests ersetzen diesen Nachweis nicht.

## Historischer Publikationsreview — 2026-11-03

Die nachfolgenden Aussagen und Prüfläufe beziehen sich auf den damaligen Stand; neuere Befunde und Nachweise stehen im Abschnitt oben.

**Ergebnis:** Der aktuelle Arbeitsbaum ist technisch weit vorbereitet, aber noch kein
abschließend freigegebener Veröffentlichungsstand. Für die beauftragte **Quellcode-Veröffentlichung**
sind vor allem die Lizenzprüfung der tatsächlich enthaltenen SDK-Materialien, die Auswahl und
Prüfung des finalen Source-Stands, ein reproduzierbarer Build-Nachweis und die Korrektur der
öffentlichen Statusangaben offen. Eine installierbare Passwortmanager-App benötigt zusätzlich
Sicherheits-, Server- und Geräteabnahmen. Diese beiden Veröffentlichungsziele haben unterschiedliche
Abschlusskriterien; fehlendes Signing allein verhindert keine Source-Veröffentlichung.

Dieser Abschnitt ist der neue Reviewbericht innerhalb der bestehenden einzigen Arbeitsliste.
Die F-IDs unten bleiben die ausführbaren Aufgaben. Der Auftrag dieser Runde war Review und
Dokumentation; Produktcode und bestehende Änderungen wurden erhalten.

### Befunde für die Quellcode-Veröffentlichung

| Priorität / Aufgabe | Konkreter Befund und Beleg | Noch zu erledigen / Abschlusskriterium |
| --- | --- | --- |
| Hoch — F-17 (für Source-only erledigt) | Der gepinnte Bitwarden-Upstream stellt seine SDK-Quellen standardmäßig unter GPLv3 **oder** Bitwarden SDK License v2; für die SDK-Bestandteile dieses Source-Pakets wurde die upstream angebotene GPLv3-Option gewählt. | Erledigt: Originallizenztexte/Notices erhalten, Source-Scope und Drittmaterialien im Inventar abgleichen. Keine Fremdsoftware wird umgelizenziert. |
| Hoch — F-18/F-21 | HEAD ist weiterhin `de5bd0aed51dc87d95ff97d1ca3680968d8f72c3`; zahlreiche Fixes, Tests und CI-Änderungen sind uncommittet, darunter neue notwendige Dateien wie `SystemBootSession.swift`, Inventare und Build-/Guard-Skripte. Ein Release nur dieses HEAD enthält den geprüften Arbeitsstand nicht. | Vollständigen beabsichtigten Source-Stand zusammenstellen, Diff einschließlich neuer Dateien prüfen, privaten Handoff, lokale Konfiguration und SDK-Binaries ausschließen. Erst auf Veröffentlichungsauftrag finalen Commit/Tag erstellen und dessen tatsächlichen Inhalt prüfen. Festlegen, ob Git-Historie oder nur ein Source-Snapshot veröffentlicht wird; den gewählten Umfang scannen. |
| Mittel — F-19 | `.github/workflows/verify-source.yml` verwendet Xcode 26.3 auf `macos-15`. Die früheren Läufe `42366690224`/`42379652835` erreichten kein Gesamtergebnis. `42382979226` wurde während des Package-Schritts abgebrochen; die zuletzt sichtbaren Tests waren bestanden. `42386509488` blieb beim parallelisierten Package-Test stehen und wurde ersetzt. Im Lauf `42388933951` bestanden Source-Policy, SDK-Neubau und serielle Pakettests; danach crashte die native macOS-Integration beim Recovery-Hosting-Test. Im folgenden Lauf `42395598098` bestand der Package-Schritt; der Prozess crashte während `testRealRootDrivesLifecycleThroughFirstRunUnlockedRecoveryAndLockedStates`. Der Stack endet in `XCTWaiter`, kurz nach einer AppKit-Warnung zu rekursivem Layout. Lokal bestehen die betroffenen Lifecycle-/Recovery-Tests fünfmal hintereinander und das macOS-Bundle 18/18 mit Xcode 27.2 nach Umstellung der betroffenen XCTest-Wartepunkte auf begrenztes Polling und Entfernen eines doppelten Layout-Aufrufs. | Pakettests laufen seriell, mit Ein-Minuten-Grenzen für `SendModelTests`, `ReturningUnlockServiceTests` und den synthetischen Serververtrag sowie fünf Minuten Gesamtgrenze für den Package-Schritt. `xcodebuild`-Ausgabe ist sichtbar, native Tests haben 120/300-Sekunden-Grenzen und der native Integrationsschritt 60 Minuten. Noch erforderlich: derselbe Hosting-Lauf auf Xcode 26.3 remote sowie anschließend erfolgreicher iOS-Integrations- und Debug/Release-Build. |
| Mittel — F-20 (erledigt) | Historisch wurden README-Testzahlen und Aussagen zum Serververtrag abgeglichen. Die aktuelle README verweist auf datierte Nachweise und nennt ausdrücklich verbleibende Server-, Geräte-, Signierungs- und SDK-Gates. | Bei späteren Code-/Serveränderungen die Versionen, Zählungen und Skips erneut mit `Verification.md` und `IntegratedAcceptance.md` abgleichen; F-20 bleibt erledigt, solange keine neue Abweichung entsteht. |
| Mittel — F-16/F-21 | Das eingecheckte SDK-Advisory-Inventar dokumentiert bekannte Abhängigkeitsrisiken. CI prüft Source-Materialien und Builds, enthält aber keinen erneuten RustSec-Audit-Schritt. | Den bestehenden Audit als datierten Befund kennzeichnen, vor einer Freigabe aktualisieren und die Bewertung zum tatsächlich gewählten SDK-Pin sichern. Für Source-only Einschränkungen ausdrücklich beibehalten; für eine App-Auslieferung verbleibt F-16 ein Sicherheitsgate. Ein neuer Audit-Job wäre eine sinnvolle dauerhafte Absicherung. |
| Niedrig — F-18 | Der bisherige Asset-Review dokumentiert ausschließlich schwarze App-Icons. | Als bewussten Platzhalter kennzeichnen oder vor einer App-Präsentation ersetzen. Für die Veröffentlichung von Quellcode allein ist ein neues Icon kein technischer Blocker. |

**Owner-Entscheidung 2026-11-07:** Projekt-eigene Dateien (Code, Dokumentation und Assets) werden
unter GPL-3.0-only veröffentlicht. Drittmaterialien werden nicht umlizenziert und behalten ihre
Upstream-Lizenzen. Source-only bleibt das erste Publikationsziel. `welcome@temmi.land` ist erreichbar.
Signing, Store-Wahl und Geräteabnahmen bleiben separat.

### Zusätzliche Arbeit vor einer installierbaren App

| Bereich / bestehende IDs | Fehlender Nachweis und konkrete nächste Prüfung |
| --- | --- |
| SDK-Sicherheit — F-16 | Vorhandenes Advisory-Inventar fachlich nach tatsächlicher Ziel-/Feature-Erreichbarkeit bewerten; kompatible Abhilfe prüfen und danach SDK neu bauen und App-Regressionen ausführen. Die alten Trefferzahlen werden in dieser Runde nicht als frisch online verifiziert ausgegeben. |
| Lock, Logout, Refresh und Neustart — F-02/F-10/F-11/F-23 | Signierte App und Extension parallel ausführen; Lock/Logout während Refresh, Prozessende, Keychain-Fehler, Reboot und abgelaufene Unlock-Lease prüfen. `SystemBootSession.currentID()` muss auf echten Zielgeräten verfügbar sein; bei Fehler verweigert der Code persistierte Grants. Lokale Tests ersetzen diesen OS-Nachweis nicht. |
| AutoFill/Passkeys — F-12 | Echte Credential-Provider-Anfragen in Safari/Apps, QuickType, Registrierung und Assertion einschließlich Abbruch, Credential-Wechsel und Re-Prompt-Sperren abnehmen. Der lokale Serverlauf hat nur einen vorbereiteten Passkey gelesen. |
| Server-Datenintegrität — F-13 | Login mit tatsächlicher TOTP-Challenge und der begrenzte stale-write-Test sind auf synthetischem Vaultwarden 1.37.5 belegt. Einzelgeräte-Widerruf wird dort mit 404 abgelehnt; Organisations-/Collection-Daten, andere Serverversionen, die Ein-Sekunden-Race und UI-Recovery fehlen. Der Produktions-Smoke bleibt beim Owner. |
| Dateien und Ressourcen — F-08 | Große Dateien, voller Datenträger, Abbruch/Lock und Crash-Cleanup auf Geräten prüfen. Der Transport begrenzt Downloads; die SDK-Dateikrypto verarbeitet weiterhin ganze Dateien im Speicher. Deshalb keine konstante Gesamtspeichernutzung versprechen. |
| UI und Plattform — F-05/F-06/F-14 | Hotkey-Berechtigung und Launch-at-Login auf signiertem macOS-Build, sichtbare Fehler-/Recovery-Texte, PIN/Biometrie, Clipboard, Privacy Shield, iPad/Multi-Scene und Accessibility abnehmen. Auf macOS hängt das Clipboard-Ablaufen an einem laufenden Prozess; der Code besitzt dort keine OS-seitige Ablaufzeit. |
| Distribution — F-21 | Team/Bundle-/App-Group-/Keychain-Konfiguration, tatsächliche Entitlements, Verteilungsweg und gegebenenfalls Notarisierung festlegen und prüfen. `project.yml` setzt für die macOS-Haupt-App derzeit `app-sandbox: false`; die Extension ist sandboxed. Daraus folgt keine geprüfte Eignung für einen bestimmten Store. |

### Was in dieser Runde tatsächlich geprüft wurde

Statische Durchsicht von Package-/Target-Struktur, Release-Konfiguration, CI, SDK-Build und
Publikationsguards; gezielte Codelektüre von HTTP-Limits/Redirects/Dateitransport, URL-Policy,
Token-Refresh, Session-Widerruf, Timeout/Boot-Bindung, Cipher-Payload-/Re-Prompt-Schutz,
Temporary-File- und Clipboard-Lifecycle sowie AutoFill-Logging. Öffentliche Status-/Lizenz-/
Security-Dokumente wurden mit dem zentralen Aufgabenstand und den neueren Nachweisen abgeglichen.
Das ist keine zeilenweise Vollprüfung aller Quellen oder unabhängige Krypto-Sicherheitsprüfung.

Dabei wurde **kein zusätzlicher reproduzierter Produktcodefehler** festgestellt. Die dokumentierte
Statusabweichung ist hingegen direkt belegt. Die vorhandenen Schutzmaßnahmen für HTTPS,
Secret-Redirects, Antwortlimits, Session-Widerruf und schreibgeschützte unbekannte Cipher-Payloads
sind im untersuchten Code vorhanden; das ist keine pauschale Freigabe ihrer gesamten OS-Matrix.

Neu ausgeführt am aktuellen Arbeitsbaum:

| Prüfung | Tatsächliches Ergebnis |
| --- | --- |
| `swift Scripts/check-architecture.swift` | Bestanden, 205 eigene Swift-Quelldateien. |
| `swift Scripts/check-source-secrets.swift` | Bestanden, 481 getrackte/unignorierte Textdateien vor dieser Dokumentergänzung; heuristische Musterprüfung, keine neue vollständige Historienprüfung. |
| `swift Scripts/check-source-materials.swift` | Bestanden, 29 Dateien/Hashes; verbotene private/generierte Materialien nicht getrackt. Keine Lizenzfreigabe. |
| `bash Scripts/test-packages.sh` | Exit 0. SDK-Smoke: 1 Test; AuthPresentation: Summary 69 Tests/9 Suites; AppModulesArchitecture: Summary 830 Tests/100 Suites, zusätzlich 2 XCTest. `existingServerFlows()` ausdrücklich übersprungen. Wiederholte XCTest-Summary-Zeilen nicht mehrfach zählen. |
| `git diff --check` | Bestanden vor der Dokumentänderung; nach der Ergänzung erneut geprüft. |

Pakettest-Log lokal: `${TMPDIR:-/tmp}/vaultwarden-publication-review-packages.log`.
Native App-Builds, Simulatorintegration, Live-Server, RustSec-Datenbank, Remote-CI, echte Geräte und
SDK-Neubau wurden in **dieser** Reviewrunde nicht erneut ausgeführt. Die dafür unten genannten
früheren Erfolge bleiben datierte Evidenz ihres jeweiligen Laufs.

### Empfohlene Reihenfolge

F-17 ist für das konkrete Source-Paket geklärt. Danach F-20 korrigieren und den vollständigen
Release-Kandidaten für F-18/F-21 zusammenstellen. Gegen diesen Stand F-19 nachweisen und die
bekannten Risiken datiert dokumentieren. Anschließend kann über die Quellcode-Veröffentlichung
entschieden werden. Die zusätzlichen App-Abnahmen bleiben vor einer installierbaren Freigabe
abzuarbeiten; sie müssen nicht als Voraussetzung für einen Source-only-Review vorgetäuscht werden.

## Ergebnis und Verwendung

**Nicht alle offenen Punkte sind erledigt.** Dies ist die einzige gepflegte Arbeitscheckliste.
Sie vereinigt die bisherigen Home-Verzeichnis-Reviews, `Docs/ReleaseChecklist.md`, den früheren
Reststand, die Aufgaben aus dem ursprünglichen Plan und die noch offenen ADR-/Runbook-Grenzen.
`[x]` bedeutet nur den jeweils beschriebenen lokalen Abschluss; offene Geräte-/Server-/Owner-Gates
werden dadurch nicht geschlossen. Ein fehlender Nachweis ist kein nachgewiesener Exploit.

Die erste Veröffentlichung bleibt **Quellcode eines unauditierten Lernprojekts** unter GPL-3.0-only
für eigene Dateien und die im Upstream dual lizenzierten Bitwarden-SDK-Bestandteile, für die hier
die upstream angebotene GPLv3-Option gewählt ist. Andere Drittmaterialien behalten ihre jeweiligen
Lizenzen. Installierbare Apps sind separat zu bewerten. Für Source-Publikation fehlen vor allem
Source-Umfang F-18, Remote-CI F-19 und
der Source-Commit-Teil von F-21; bekannte Code-/SDK-Risiken müssen korrekt
sichtbar bleiben. F-16 und die Sicherheits-/OS-/Servergates schließen eine Produktionsfreigabe aus.
Keine Behauptung, dass alle Funktionen fertig oder alle Quellcodezeilen unabhängig auditiert sind.

### Aktueller Umsetzungsstand und externe Voraussetzungen

Lokal umgesetzt: F-22 Upload-Cancellation, F-23 Boot-Bindung, F-24 beide Regex-Budgets,
F-25 expliziter Simulator-Preflight; der lokale Runtime-/Runner-Anteil von F-15 ist abgeschlossen.
F-08 erhielt zusätzlich tatsächlich begrenzte Datei-Downloads mit geschützter Stage und
Abbruch des echten Netzwerk-Tasks. F-09 weist auch GET-Uploads mit Dateibody bei Redirects ab.
F-17/F-18 haben konkrete Source-/Dependency-/Advisory-Inventare und einen CI-Material-Guard;
XcodeGen ist lokal und in CI auf 2.46.0 samt Archivhash gepinnt (F-19).
Die öffentlichen Kandidatenläufe `42366690224`, `42379652835` und `42382979226` bestanden
Source-Policy und SDK-Neubau. Die ersten beiden erreichten kein Gesamtergebnis. Der dritte wurde
im separaten Package-Testschritt nach knapp zehn Minuten abgebrochen; die letzte vom Owner
mitgeteilte Zeile war ein bestandener `SendModelTests`-Fall, kein Testfehler. Die 21 negativen
Konfigurationsfälle sind jetzt eine normale Schleife; Package-Tests laufen mit bis zu vier
SwiftPM-Test-Workern. `SendModelTests` und der synthetische Serververtrag sind serialisiert und
haben je Test ein 1-Minuten-Limit. `xcodebuild` gibt Build- und Testfortschritt aus; native
Einzeltests haben ein Limit von 120 Sekunden (maximal 300), die native Integration endet nach
spätestens 60 Minuten. Lokal bestanden SDK-Smoke (1), AppModules (846/100 Suites), macOS-Integration
(18/18) und iOS-Simulatorintegration (18/18) mit Xcode 27.2. F-19 bleibt offen, bis der frische
Xcode-26.3-Remote-Lauf samt späteren Builds erfolgreich ist.

Owner-Antworten dieser Umsetzung:

- Weiterhin ausschließlich Quellcode; signierte Geräteabnahmen bleiben separat.
- Der Owner stellt keine isolierte Testinstanz bereit und testet die App manuell mit der eigenen
  Produktionsinstanz. Auf ausdrückliche Erlaubnis wurde stattdessen eine kurzlebige lokale
  Vaultwarden-1.37.5-Instanz mit synthetischem Konto eingerichtet; der mutierende Vertragstest
  lief ausschließlich dort und nicht gegen Produktion. Der lokale Vertragstest bestand, deckt
  aber weder alle F-13-Pfade noch die Version/Kompatibilität der Produktionsinstanz ab. Die
  getrennte manuelle Smoke-Strecke steht in [IntegratedAcceptance.md](IntegratedAcceptance.md).
- `welcome@temmi.land` ist vom Owner als erreichbar bestätigt; keine Testmail gesendet.
- Die separate SDK-Lizenz-/Notices-Prüfung (F-17) wurde für den Source-only-Umfang abgeschlossen;
  binäre Artefakte bleiben durch ihre eigenen Distributionsgates erfasst.

Die offenen F-02/F-05/F-06/F-10–F-14 betreffen die beschriebene Geräte-/OS-/Prozess-/Servermatrix,
keine Aufforderung, fertige lokale Architektur erneut zu implementieren. F-16 benötigt einen
kompatiblen Upstream-Sicherheitsfix; auch der neu geprüfte Upstream hat weiterhin Audit-Treffer.
F-17 ist für Source-only geklärt, F-18 benötigt den final gewählten Publikationsumfang und F-19
echte Remote-CI/Fresh-Machine-Evidenz. F-21 betrifft nur noch den
finalen Source-Commit/Veröffentlichungsakt und die separat belassenen App-Entscheidungen.
Diese Nachweise werden nicht durch lokale Fixtures oder zusätzliche Markdown-Häkchen ersetzt.

Keine zweite Aufgabenliste anlegen. Pro bearbeiteter ID hier Ursache, geänderte Dateien, Befehl,
tatsächliches Ergebnis und verbleibende Grenzen aktualisieren. Neu erkannte Fehler erhalten eine
neue F-ID. Im Folgenden sind frühere F-IDs stabil erhalten; neue Befunde stehen bei F-22–F-25.

## Verifizierter Abschluss der lokalen Umsetzung

Der abschließende gemeinsame Lauf sowie Debug/Release liefen nach dem letzten App-Codefix.
Danach wurden nur Veröffentlichungsscan, Inventare, Ignore-Regeln und Dokumentation präzisiert;
die betroffenen Source-Guards/Fixtures wurden separat erneut ausgeführt. Keine App-Quelle wurde
nach dem finalen nativen Build geändert.

| Prüfung | Endergebnis |
| --- | --- |
| `bash Scripts/test-integration.sh` | Historischer Lauf vom 2026-11-02: Exit 0. SDK-Smoke: 1; AuthPresentation: 69 Methoden/9 Suites; AppModulesArchitecture: Framework-Summary 823/100 Suites plus 2 XCTest. Live-Serverfall ausdrücklich übersprungen. |
| `bash Scripts/test-packages.sh` (2026-11-03) | Exit 0. SDK-Smoke 1; AuthPresentation 69 Tests/9 Suites; AppModulesArchitecture 830 Tests/100 Suites plus 2 XCTest, alle bestanden. Regressionen für DTO, Payload-Safety, Attachment-URLs und verschlüsselte Send-Dateinamen enthalten. |
| `bash Scripts/swiftformat.sh --lint` (2026-11-03) | Exit 0; 0/366 Dateien benötigen Formatierung. |
| `bash Scripts/build-unsigned.sh Debug` / `Release` (2026-11-03) | Exit 0; macOS und generischer iOS-Simulator samt Extensions in beiden Konfigurationen erfolgreich. Alle vier Builds unsigniert. |
| `bash Scripts/test-integration.sh` (2026-11-03) | Exit 0; Pakete bestanden, macOS-Integration 17/17 und iOS-Simulator 17/17 ohne Fehler/Skips. Der darin opt-in Serverfall war mangels gesetzter Live-Testvariablen NOT RUN; der separate synthetische Live-Lauf unten bestand. |
| `LiveServerContractTests` (2026-11-03) | Vaultwarden 1.37.5, Image-Digest `sha256:4fe17f415f90087377d37c755e0ea3cf189dcc6794e49cdd2a9adbb4937d9e1f`, lokale kurzlebige Instanz/synthetischer Account. `SERVER CONTRACT: all stages passed`; Login/Handoff, Refresh, Sync/Passkey-Read, Cipher/TOTP, Attachment und Text-/File-Sends bestanden. Login-TOTP-Challenge wurde mangels Challenge nicht ausgeübt. Kein Zugriff auf Produktionsdaten. |
| Source-Publikationsguards (2026-11-03) | Secret-Heuristik: 481 Textdateien, keine Muster; synthetische Negativfixtures bestanden. Drittmaterial-Inventar: 29 Dateien/Hashes bestanden. Lokale Markdown-Links und `git diff --check` sauber. |
| `test-configuration.sh` | Debug/Release, alle vier Bundle-/Entitlement-Templates und drei negative Konfigurationsfälle bestanden. |
| Format/Architektur | 0/366 Dateien zu formatieren; 205 eigene Swift-Quellen und sechs negative Architektur-Fixtures bestanden. |
| `check-source-secrets.swift` / Fixtures | 481 veröffentlichbare UTF-8-Dateien geprüft, inklusive generierter/neuer Quellen, LICENSE, Dotfiles und .dat-Dateien. Keine geprüften Tokenmuster gefunden. Neue/generated/extensionlose/Dataset-Negativfälle ohne Inhaltsausgabe abgelehnt. Kein vollständiger Nachweis gegen beliebige Passwörter oder persönliche Informationen. |
| `check-source-materials.swift` | Alle 29 Drittmaterial-Dateien mit Hashes verifiziert. Manipuliertes Inventar und ein synthetisch versehentlich gestagter privater Handoff abgelehnt. |
| Simulator-Preflight | Drei positive/fünf negative automatische und ein positiver/vier negative explizite Selector-Fälle; 19 Runner-Ablehnungen und ein positiver Boot-vor-Build-Fall bestanden. |
| Gepinnter XcodeGen | 2.46.0 mit offiziellem Release-Archivhash gebootstrapt und tatsächlich zur Projektgenerierung verwendet. Manipuliertes Archiv wird vor Ausführung verweigert. |
| Lokale frische Quellkopie | 492 Dateien aus Clone plus ausdrücklich uncommittetem Overlay byteweise verglichen; kein privater Handoff, Local.xcconfig oder SDK-Binary übernommen. Source-/Material-Guards und Tool-Bootstrap bestanden. Gleiche Maschine, kein neu gebautes SDK und kein App-/CI-/Fresh-Machine-Nachweis aus dieser Kopie. |
| SDK-/Lizenzinventar | 731 deklarierte Packages; Normal-/Build-Tree: iOS 428, macOS 427 eindeutige Paketversionen, Feature-Union je Ziel dokumentiert. Keine Lizenzfreigabe aus den Metadaten abgeleitet. |
| SDK-Sicherheitsbewertung | Pinned Lockfile weiterhin elf Vulnerability-Einträge, acht unmaintained, ein unsound, zwei yanked. Am 2026-11-02 gelesener Upstream `ca53f727…` ebenfalls elf. Kein nachgewiesener kompatibler Upstream-Gesamtfix; keine generierten SDK-Dateien verändert. |
| Dokumentprüfung | Genau eine öffentliche Checkbox-Arbeitsliste, vollständige Zuordnung der 63 ursprünglichen Tasks/27 Defekte/zwölf Gates; lokale Markdown-Links und `git diff --check` werden im Abschluss erneut geprüft. |

Rohlogs außerhalb der Veröffentlichung:
`${TMPDIR:-/tmp}/vaultwarden-final-{integration,debug,release,configuration,guards}.log`,
`${TMPDIR:-/tmp}/vaultwarden-final-source-check.log`, `...-source-fixtures.log`;
Native Summaries: `...-macos-summary.json` / `...-ios-summary.json`.
Lokale Clone-Grenzen: `${TMPDIR:-/tmp}/vaultwarden-final-source-clone.json`.
Die dokumentierten Counts beziehen sich auf getrennte Targets; Skips und Wiederholungsläufe
werden nicht als zusätzliche erfolgreich ausgeführte Testmethoden addiert.

**Abschlussgrenze:** Die eigenen konkret bestätigten Codebefunde sind bearbeitet und lokal
verifiziert. Eine vollständige Freigabe aller 25 Einträge wird ausdrücklich nicht behauptet:
SDK-Upstream-Fix, endgültiger Source-Release-Commit/-umfang und echte
Remote-CI/Fresh-Machine-Evidenz bleiben offen; der Owner-Smoke-Test gegen seine Produktionsinstanz
und Geräteabnahmen sind separat. Der lokale Serververtrag ist keine Produktionsfreigabe.
Das ist kein Grund für erneute bereits abgeschlossene Modulmoves oder für das Abschwächen von
Guards. Kein Commit, Push, Tag oder Release aus diesem Umsetzungsauftrag vorgenommen.

## Historische Review-Prüfung vor Umsetzung

Umgebung: macOS arm64, Xcode 27.2 (27B52), Swift 6.4.2. Keine echten Accounts, keine
Server-Schreibtests, kein Push/Tag/Release, keine Signierungs- oder Lizenzentscheidung.

| Prüfung | Tatsächlicher Nachweis am 2026-11-02 |
| --- | --- |
| `bash Scripts/test-packages.sh` | Exit 0: SDK-Smoke 1; AuthPresentation 69/9 Suites; AppModulesArchitecture Zusammenfassung 809/99 Suites; 2 XCTest bestanden. Der opt-in Live-Serverfall wurde übersprungen. Die Zusammenfassungen sind getrennte Targets, nicht nur 809 Tests über das ganze Repository. |
| `bash Scripts/swiftformat.sh --lint` | 0/363 Dateien zu formatieren |
| Architektur-Check und `test-architecture-rules.sh` | 204 eigene Swift-Quelldateien; sechs negative Fixtures korrekt abgelehnt |
| Source-Secret-Check und `test-source-secrets.sh` | 444 getrackte Textdateien; synthetische Token-Fixtures korrekt abgelehnt; heuristisch |
| `test-integration-preflight.sh` | drei positive/fünf negative Selector-Fixtures und 14 Runner-Ablehnungen bestanden; F-25 ist eine zusätzlich nachgewiesene Abdeckungslücke |
| `git diff --check` | Vor und nach Dokumentpflege sauber; Markdown-Links geprüft, nur diese Datei enthält Aufgaben-Checkboxen |
| `bash Scripts/build-unsigned.sh Debug` | Exit 0; macOS und generischer iOS-Simulator samt Extensions, zweimal `BUILD SUCCEEDED`; frisches temporäres DerivedData |
| `bash Scripts/build-unsigned.sh Release` | Exit 0; beide Plattformen samt Extensions, zweimal `BUILD SUCCEEDED`; frisches temporäres DerivedData |
| `bash Scripts/test-configuration.sh` | Debug/Release und alle vier Targets samt positiven/negativen Konfigurationsfällen bestanden; keine Provisioning-/Signed-Entitlement-Freigabe |
| `bash Scripts/test-integration.sh` | Exit 0: automatischer Boot-Preflight, beide Packages und echte hostlose macOS-/iOS-Bundles bestanden; aus beiden aktuellen xcresult-Summaries je 17/17 Tests, 0 Fehler/Skips. `SERVER CONTRACT: NOT RUN`. Kein signierter Geräte-/echter ExtensionContext-Nachweis. |
| `bash Scripts/build-sdk.sh --check` | Exit 0, vorhandene XCFramework-Slices/Hashes read-only inventarisiert; kein neuer SDK-Build und keine externe Provenance-Attestation |
| Git-History und App-Icons | History erneut: 2.167 Text-/7 Binär-Blobs, keine der zehn geprüften Tokenfamilien gefunden. Elf PNG-App-Icons pixelweise geprüft, alle vollständig RGB-schwarz; F-18. |
| Upload-Reproduktion | Unveränderte Networking-Produktionsdateien mit synthetischem pausierendem URLProtocol kompiliert: nach `Task.cancel()` kein Transportabbruch, später HTTP 200; F-22 |
| Timeout-Reproduktion | Gegen die tatsächlich gebauten Data-/Domain-/SecurityStorage-Objekte gelinkt: neuer Store über denselben synthetischen Bytes akzeptiert überlappende neue Uptime; F-23 |
| RustSec-Audit | Erneuter Lauf mit Datenbank-Fetch gegen gepinntes Lockfile: 11 Vulnerabilities, 8 unmaintained, 1 unsound, 2 yanked; erwarteter Exit 1. Datenbank weiterhin Commit `263a4d951a0867d4bddc29dddd6d59427c78f9a7` vom 2026-11-02 12:45:44+01:00, 1.402 Advisories. Vier Advisory-Primärquellen zusätzlich online abgeglichen. |

Build-/Integrationsresultate dieser Runde stehen in der Tabelle. Ältere erfolgreiche Läufe in
`Verification.md` sind historische Evidenz, kein Beleg für den heutigen Arbeitsbaum.
Die temporären Reproduktionen verwenden ausschließlich synthetische Werte und bleiben außerhalb
des Source-Release-Pakets. Dauerhafte Regressionen sind Teil der jeweiligen Implementierungsaufgabe.

Lokale Rohlogs: `${TMPDIR:-/tmp}/vaultwarden-review-20261102-{packages,guards,debug,release,integration,configuration,sdk-check,history}.log`;
die zwei xcresult-Summaries liegen unter `${TMPDIR:-/tmp}/vaultwarden-review-20261102-{macos,ios}-summary.json`.
Der Release-Nachweis bezieht sich auf unsigned Builds mit vorhandenem SDK und lokal vorhandenen
Toolchains; die frischen Build-DerivedData-Verzeichnisse sind kein Fresh Clone auf anderer Maschine.

### Reviewumfang und Grenzen

Geprüft wurden der vorhandene Code-Diff und die zentralen Auth-/Session-/Timeout-, AutoFill-/
Passkey-/Projektions-, Netzwerk-/Dateitransport-, Settings-/macOS-Integrationsgrenzen, Package-/
Build-/CI-Konfiguration sowie die Markdown-Aufgaben-/Freigabedokumente. Die Dokumentinventur
erfasst 46 öffentliche Markdown-Dateien im Repository vor der Konsolidierung; ihre alten Restangaben sind
unten den F-IDs und ursprünglichen Task-/Defekt-IDs zugeordnet. ADRs bleiben Entscheidungen,
Runbooks bleiben Testanleitungen. Generierte SDK-Quellen wurden nicht manuell zeilenweise auditiert;
keine eigenständige Rust-Krypto-, Real-Device-, Live-Server- oder unabhängige Security-Freigabe.
Auch die private unversionierte `CLAUDE_HANDOFF.md` wurde auf noch offene Aufgaben abgeglichen:
ihr alter Integrations-/Handoff-/Server-/Publikationsauftrag ist durch F-10–F-21 abgedeckt;
die dort überholten Baseline-/CI-/Layout-Aussagen sind keine neuen Aufgaben. Sie bleibt als
vorgefundene private Datei unverändert und außerhalb der Publikation; keine Remote-/Zugangsdaten
daraus in die öffentliche Checkliste übernehmen. Ihre damalige Commit-Anweisung ist kein neuer
Commit-Auftrag dieser Reviewrunde.

## Regeln für GPT-6-Luna

1. Vor Arbeit Git-Status, CONTRIBUTING und den eingefrorenen Scope in
   `Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md` lesen. Vorhandene Änderungen bewahren.
2. Genau eine kleine Aufgabe bzw. zusammenhängende Fehlerursache bearbeiten. Kein Commit/Push/
   Tag/Release aus dieser Liste ableiten. Bei später beauftragten Commits bestehende
   Gitmoji-/Signaturkonvention beachten und Signatur prüfen; keine Historie umschreiben.
3. Keine neuen Features/Endpunkte/2FA-Verfahren/Cipher-Editoren, Multi-Account, Offline-Vault
   oder Background Sync. Kein künstliches Deaktivieren vorhandener Scope-Funktionen.
4. Generierte SDK-Dateien und offizielle Checkouts nicht manuell verändern; `project.yml`
   bleibt Xcode-Quelle. Keine neue Dependency ohne konkrete Aufgabenbegründung/Scope.
5. Verdachtsfälle zuerst reproduzieren. Proof-/Account-/Revision-/Epoch-/Cancellation-Fences
   nicht zur Optimierung entfernen. Keine Testfixtures als Geräte-/OS-/Servererfolg ausgeben.
6. Lock/Logout und Abbruch bleiben sicher; bestätigte oder unklare Serverwrites dürfen nicht
   als sicher ungeschehen/erneut ausführbar erscheinen. Keine blinden Retries oder erfundenen Rollbacks.
7. Am Aufgabenende relevante Regressionen ausführen; am Meilenstein vollständige lokale Matrix.
   Neue Ergebnisse hier eintragen; Rohlogs nur ohne Secrets. Owner-Gates nicht durch Fakes schließen.

Priorität: P1 = zuerst Sicherheits-/Datenintegritätsgrenze, P2 = Funktionsfehler/Härtung,
P3 = Pflege. Ein Gate braucht den angegebenen externen Nachweis/Owner-Entscheid; unabhängige
lokale Aufgaben können weiterlaufen, ohne auf ein solches Gate zu warten.

## Bereits vorhandene Schutzmaßnahmen und aktualisierte Grenzen

- SEC-01: Katastrophales Regex-Backtracking wird mit kooperativen Progress-Callbacks begrenzt.
  Die im Review gefundene Lockerung des Einzelschutzes ist behoben: 25 ms pro Regex plus
  100 ms für den URI-Filter; Einzelabbruch macht das Ergebnis sichtbar unvollständig (F-24).
- SEC-02: `HTTPStatusError` enthält ausschließlich Status/Retry-After; beliebige Bodies werden
  seit `de5bd0a` verworfen. Alte Texte über gespeicherte redigierte JSON-Felder sind überholt.
- Read-only für unbekannte Payloads/Re-Prompt ohne Grant, Refresh-Intent/Network-Lease,
  Auth-Cleanup-Replay und SDK-KDF-/Decryption-Guards existieren. Keine Parallelarchitektur bauen.
- FFI-Modulauflösung nicht ohne Reproduktion als weiter bestehenden Codefehler behandeln.
- GPL-3.0-only-Datei, Upstream-Lizenztexte/Pin/Patchhash, Architecture, ThreatModel, SECURITY, CONTRIBUTING,
  Changelog und heuristische Source-Guards existieren. Sie ersetzen keine Publikationsprüfung.
- Historisch bestand ein isolierter SDK-Neubau mit FFI-Smoke; Herkunft/Hashes und Grenzen stehen
  in `SDKRebuildVerification.md`. Kein heute neu gebautes SDK und keine Fresh-Machine-Attestation.

## Aufgaben F-01–F-21 aus den bisherigen Reviews

### F-01 — P1 — Projection-Initialisierung wird trotz Lese-/Cleanupfehler als fertig markiert

- [x] F-01 im beschriebenen Umfang abschließen.

**Status:** Behoben und fokussiert regressionsgeprüft am 2026-11-02 (9/9 bestanden).
**Ort:** `Packages/AppModules/Sources/Data/AutoFillProjectionWriter.swift:114–143`; Tests `AutoFillProjectionWriterTests.swift`.

Vor der Änderung wurde `isInitialized = true` gesetzt, bevor `fileStore.readProjection()` oder notwendiges `removeProjection()` erfolgreich waren. Nach einem temporären Lesefehler lieferte der erste `project()`-Aufruf unavailable; der zweite konnte die initiale Revision-/Accountprüfung überspringen und eine kleinere Revision über eine neuere Projektion schreiben. Auch ein fehlgeschlagenes Entfernen einer korrupten/alten Projektion wurde nicht erneut initialisiert.

**Umsetzung:** `isInitialized` wird erst nach erfolgreichem Read und erfolgreicher Übernahme oder Bereinigung gesetzt. Read- und Cleanupfehler lassen die Initialisierung offen, sodass der nächste `project()`-Aufruf sie wiederholt. Ein erfolgreich gelesener leerer Store gilt als initialisiert. Die bestehenden Same-/Older-Revision-Prüfungen bleiben erhalten.
**Abnahme:** `swift test --package-path Packages/AppModules --scratch-path ${TMPDIR:-/tmp}/vaultwarden-f01-build --filter AutoFillProjectionWriterTests` — 9 Tests bestanden. Neue Regressionen decken einen zunächst fehlschlagenden Read bei gespeicherter Revision 9, einmalig fehlschlagendes Entfernen eines Foreign-Account-Envelopes und ein korruptes Envelope ab.
`SessionVaultProjection.make` verwendet weiterhin `try? ... ?? 0` für `initialRevision`. Das ist hier fail-safe: `AutoFillProjectionWriter` liest die gespeicherte Projektion selbst erneut, lehnt eine ältere Revision ab und schreibt bei eigenem Readfehler nicht. Ein separater Umbau des Session-Zählers ist für F-01 nicht erforderlich.

### F-02 — P1 — Timeout hängt von laufender Haupt-App ab, Extension-Proof hat keine Deadline

- [ ] F-02 im beschriebenen Umfang abschließen.

**Status:** Codehärtung umgesetzt; signiertes Geräteverhalten und Schlaf-/Neustartsemantik bleiben offen.
**Umsetzung:** Shared AutoFill-Unlock-Schema auf Version 4 mit Boot-Session-ID angehoben; unbekannte/alte Schemata fail-closed. Persistierte Timeout-Lease nutzt monotone Zeit statt Wall Clock und wird bei wiederholten Inactive-Events nicht verlängert. Abgelaufene Leases werden verweigert. In-App-Watchdog misst mit `ContinuousClock`; App-Treiber schreibt und löscht die Lease passend zu Active/Inactive. `SharedAutoFillUnlockTests` bestehen nach der Boot-Bindung mit 17 Methoden; die vorhandenen
Watchdog-Fälle bleiben erhalten. Auch `.never` bewahrt AutoFill nur innerhalb desselben Systemstarts.
Frühere Shared-Unlock-Schemata werden nicht autorisiert oder still gelöscht; nach Upgrade ist eine
neue App-Authentifizierung für einen aktuellen Grant nötig. Private Accounts werden nicht migriert.
**Zusatzprüfung 2026-11-06:** Der native Integrationstest liest `SystemBootSession.currentID()`
zweimal erfolgreich und mit identischem Ergebnis im macOS-Testhost und im iOS-Simulator;
jeweils 18/18 Integrationstests bestanden. Das belegt weder signierte physische Geräte noch
Wechsel der Boot-ID nach einem echten Neustart.
**Grenze:** Suspendierung, Prozessbeendigung, Geräteschlaf/-entsperrung und Verhalten über echte Neustarts wurden nicht auf signierten iOS-Geräten geprüft. Aus Unit-Tests folgt keine OS-Garantie über Fortsetzung einer monotonen Uhr während Schlaf.
**Abnahme:** Signierte App und Extension, Timeout 1 Minute, App suspendiert/terminiert, Gerät schlafen/entsperren, AutoFill ohne App-Rückkehr; Lock und Logout getrennt; Systemzeitänderung, Multi-Scene und „never“ prüfen.

### F-03 — P2 — Regex-Fix begrenzt Einzelvergleich, nicht die gesamte AutoFill-Abfrage

- [x] F-03 im beschriebenen Umfang abschließen.

**Status:** Gemeinsames URI-Filterbudget und sichtbarer Abbruch umgesetzt; Einzelschutz separat offen in F-24.
**Umsetzung:** Ein gemeinsames monotones Budget von 100 ms gilt über die URI-Filterphase; Cache-Lesen und SDK-Entschlüsselung liegen davor und haben dadurch kein 100-ms-End-to-End-Limit. Regexe werden pro Anfrage wiederverwendet; Cancellation wird innerhalb der Schleifen geprüft. Teiltreffer werden mit sichtbarem Hinweis als unvollständig markiert statt als vollständiges Ergebnis ausgegeben. Cache-Ergebnisse werden vor Ausgabe erneut autorisiert. `URIMatchingTests` und `CredentialQueryTests` nach Budgetkorrektur zusammen 33 Methoden bestanden.
**Grenze:** Synthetische Regressionen belegen das Budgetverhalten, nicht Latenz auf allen Geräten oder bei jeder Foundation-Regex-Implementierung. Der im Review vermisste 25-ms-Einzelschutz wurde in F-24 wiederhergestellt; das 100-ms-Filterbudget bleibt zusätzlich aktiv.

### F-04 — P2 — AutoFill lädt und durchsucht denselben Cache wiederholt vollständig

- [x] F-04 im beschriebenen Umfang abschließen.

**Status:** Anfragegebundener Snapshot und Index umgesetzt; 100/1.000/10.000-Einträge-Regressionen bestanden.
**Umsetzung:** Login- und Passkey-Anfragen bauen einen verschlüsselten Cache-Snapshot samt ID-Index pro Operation. Batch-Abfragen lesen den vollständigen Cache einmal am Anfang und einmal am abschließenden Ausgabefence; direkte Auswahl durchsucht nicht mehr wiederholt alle Ciphers. Ein separater Access-Check bleibt von der Cache-Decodierung getrennt. Der Live-Check enthält Keychain-/Lock-I/O und ist kein gemessener konstanter Laufzeitnachweis. Snapshot speichert keine entschlüsselten Secrets; finale Account-/Revision-/Berechtigungsprüfungen bleiben erhalten. `CredentialQueryTests` und `PasskeyServiceTests` liefen über alle drei Parametergrößen.
**Grenze:** Regressionen messen Read-Anzahl und funktionale Korrektheit, nicht Peak-RAM oder Geräte-Laufzeit. Auf echten Extension-Geräten weiter messen; Revision-, Lock- und Accountwechsel bleiben Sperrbedingungen.

### F-05 — P2 — Globaler Hotkey behauptet fälschlich, keine Accessibility-Freigabe zu benötigen

- [ ] F-05 im beschriebenen Umfang abschließen.

**Status:** Code und Einstellungsstatus korrigiert; TCC-/Geräteabnahme offen.
**Umsetzung:** Falsche Aussage zur Accessibility-Freigabe entfernt. Lokaler Shortcut funktioniert unabhängig; globaler Monitor wird nur bei Accessibility-Vertrauen registriert und kann nach Statusänderung erneut registriert werden. Einstellungen zeigen fehlende Freigabe bzw. fehlgeschlagene Registrierung samt Wiederherstellungshinweis. App-Status wird beim Erscheinen und bei Aktivierung aktualisiert.
**Abnahme:** Sauberer macOS-Testaccount: Freigabe abgelehnt/erteilt/widerrufen, App aktiv/inaktiv und Neustart. Keine Keystroke-Inhalte protokollieren.

### F-06 — P2 — Launch-at-Login-Schalter kann einen nicht gespeicherten Zustand anzeigen

- [ ] F-06 im beschriebenen Umfang abschließen.

**Status:** Typisierter Systemstatus und Fehlerbehandlung umgesetzt; Systemfreigabe-Matrix offen.
**Umsetzung:** `LaunchAtLoginService` unterscheidet enabled, disabled, requiresApproval und unavailable; `setEnabled` wirft Fehler, statt sie zu verschlucken. Die View liest den realen Status neu ein, zeigt ausstehende Freigabe und meldet fehlgeschlagene Änderungen verständlich. Status wird beim Anzeigen und bei App-Aktivierung aktualisiert.
**Abnahme:** Auf unterstützten macOS-Versionen Register-/Unregister-Fehler sowie ausstehende/erteilte/widerrufene Systemfreigabe prüfen.

### F-07 — P2 — Späte Gerätelistenantwort kann jüngere UI-Ergebnisse überschreiben

- [x] F-07 im beschriebenen Umfang abschließen.

**Status:** Request-Generation und deterministische Regressionsfälle umgesetzt.
**Umsetzung:** Jeder Fetch erhält eine Generation; verspätete Erfolge und Fehler dürfen weder Geräteliste noch Loading-/Fehlerzustand überschreiben. Ein Revoke invalidiert vorherige Fetches; nach Erfolg wird das Gerät entfernt und die Operation abgeschlossen. `SettingsModelTests`: 25/25 bestanden, einschließlich verspäteter Fetch-Antwort nach erfolgreichem Widerruf.
**Grenze:** Belegt wird UI-Konsistenz; keine Aussage über serverseitige Revocation oder Live-Serververtrag.

### F-08 — P2 — Ressourcenlimits für HTTP-Antworten, Cache und SDK-Dateikrypto fehlen als Gesamtbudget

- [ ] F-08 im beschriebenen Umfang abschließen.

**Status:** Teilweise umgesetzt; Gesamtbudget bleibt Release-/Plattformgate.
**Umsetzung:** HTTP-Antworten werden inkrementell gelesen und bei Überschreitung des tatsächlichen Byte-Limits abgebrochen, auch ohne verlässlichen `Content-Length`. Standardgrenze 4 MiB, Vault-Sync 64 MiB. Upload-Antworten erhalten eine eigene URLSession-Streamingbegrenzung. Der Legacy-Cache wird inkrementell mit 64-MiB-Obergrenze gelesen. SDK-Sync ist explizit auf 64 MiB konfiguriert. `URLSessionHTTPClientTests` (7) und `LegacyAutoFillCacheStoreTests` (3) bestanden, einschließlich gestreamter Antworten.
**Zusätzlich umgesetzt:** Datei-Downloads lesen `URLSession.AsyncBytes` in 64-KiB-Chunks in eine
exklusiv angelegte 0600-Stage (iOS: vollständiger Dateischutz). `maximumResponseBytes` gilt für
angekündigte und tatsächliche Bytes. Attachment-Downloads erhalten explizit 64 MiB. Auf jedem
Abbruch wird der echte `bytes.task` gecancelt; die alte Zieldatei bleibt bis zur vollständigen,
autorisierten Veröffentlichung erhalten. Auch begrenzte JSON-Reads cancellen bei frühem Abbruch
den echten Task. Erfolgs-, exakte Limit-, Chunked-/Content-Length-, Abbruch- und Cleanup-Fälle
bestehen lokal. **Offen:** SDK-internes Reqwest und Rust-Dateikrypto haben weiterhin kein
plattformübergreifendes gemeinsames Gesamtlimit; Disk-full, Peak-RAM und Gerätebudgets sind nicht abgenommen. Keine Aussage über konstante Speichernutzung des gesamten Systems.
**Quellpfad präzisiert 2026-11-06:** Im gepinnten SDK verwenden sowohl
[Attachment-`encrypt_file`/`decrypt_file`](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/crates/bitwarden-vault/src/cipher/attachment_client/mod.rs)
als auch [Send-`encrypt_file`/`decrypt_file`](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/crates/bitwarden-send/src/send_client.rs)
`std::fs::read`, anschließend erzeugen sie den vollständigen Chiffre-/Klartextpuffer und schreiben
ihn wieder auf Platte. Ein willkürliches Swift-seitiges Datei-Maximum würde einzelne Eingaben
begrenzen, aber weder den gemeinsamen Prozessspeicher noch SDK-Sync/HTTP als Gesamtbudget
absichern und könnte größere bestehende Vaultwarden-Dateien ausschließen. Ein solcher Produkt-
Grenzwert wurde daher nicht eingeführt. Für ein echtes Ende-zu-Ende-Ressourcenbudget braucht es
eine getestete Streaming-API im SDK und Messungen auf Zielgeräten; Peak-RAM und Disk-full bleiben
offen.

### F-09 — P2 — Redirect-Fallback ist bei künftigem Aufrufer mit Secret-Body unsicher

- [x] F-09 im beschriebenen Umfang abschließen.

**Status:** Sicherer Default und eng begrenzte Follow-Policy umgesetzt.
**Umsetzung:** Requests lehnen Redirects standardmäßig ab. Folgen ist nur für explizite bodylose GETs möglich. Ein separater Dateibody sperrt Redirects auch bei einem GET-Upload. Bei Originwechsel werden Authorization-, Proxy-Authorization- und Cookie-Header entfernt; HTTPS-Downgrade und Body-Redirects werden verweigert. `URLSessionHTTPClientTests` decken Default, same-origin, Headerentfernung, Downgrade und Body-Abweisung ab.
**Grenze:** Tests verwenden synthetische Daten; bestehende öffentliche Download-Aufrufer bleiben separat auf Kompatibilität zu überwachen.

### F-10 — P1 — Lock/Logout bei gleichzeitigem Marker- und Revocation-Fehler

- [ ] F-10 im beschriebenen Umfang abschließen.

**Status:** dokumentiertes Restrisiko; kein neuer reproduzierter Exploit.
**Orte:** `Data/AuthCredentialStore.swift:548–619`, `AuthCleanupIntent.swift`, `DefaultAuthRepository.swift`, ADR 022.

Bei persistenter Keychain-Störung können sowohl Cleanup-Intent als auch Capability-Entzug scheitern. Laufender App-Prozess verweigert weitere Freigabe; dauerhafte Sperrung über Neustart/andere Prozesse ist nicht bewiesen. Fehler werden bereits geworfen – keinen kosmetischen zweiten Catch-Fix hinzufügen.
**Aufgabe/Abnahme:** Fehlerkombination mit unabhängigen App-/Extension-Prozessen, Kill/Restart und anschließendem Storage-Recovery nachweisen. Können Berechtigungen bei vollständig ausgefallener Persistenz prinzipiell nicht dauerhaft widerrufen werden, das verbleibende Risiko und eine sichere, sichtbare Recovery spezifizieren statt absolute Garantie behaupten.

### F-11 — P1 — Auth-/Refresh-Recovery und echte Prozessraces unvollständig geprüft

- [ ] F-11 im beschriebenen Umfang abschließen.

**Status:** Gate, keine fehlende neue Refresh-Funktion.
**Orte:** TokenCoordinator, TokenRefreshIntent, SharedTokenStore, PendingAuthSession; ADR 027/028; bestehender Implementierungsplan S-302/S-303/U-504.

Lease, Intent, Epochs und bestätigter Commit sind implementiert. Verlorene Serverantworten sind weiterhin unklar und benötigen erneute Anmeldung. Reale Process-kill-/Upgrade-/Altbinary-/Storage-Races fehlen als Nachweis.
**Abnahme:** Unabhängige Prozesse, Tokenrotation direkt vor Lock, Kill vor/nach Antwort/Commit, fehlerhafte Markerwrites, älterer Client. Kein blindes Replay oder Löschen von Credentials bei temporärem 5xx. ADR-028-Capability-Handoff ist eine beschlossene Abweichung, kein automatisch neu zu implementierender observation-only Umbau.

### F-12 — P1 — Echte AutoFill-/Passkey-OS-Grenzen unbestätigt

- [ ] F-12 im beschriebenen Umfang abschließen.

**Status:** Gate für belastbare Funktions-/App-Freigabe.
**Orte:** CredentialProviderViewController, SystemAutoFillExtensionContext, AutoFillRequestCompletion, PasskeyRegistrationWriter/RecoveryStore, Docs/AutoFillLifecycleChecks.md.

Hostlose Tests sind kein Beleg für echte ExtensionContext-Completion, PluginKit, QuickType, signierte App Groups, Keychain Sharing und Biometrie. Unklare Passkey-Writes sind absichtlich recovery-pflichtig.
**Abnahme:** Signed macOS/iOS: Passwort, TOTP kurz vor Ablauf, Passkey Assertion/Registration, Abbruch, Account-/Revision-/Lockwechsel, OS-Identität nach Löschung/Update, unbekannte Recovery-Schemas und Neustart. Keine volle Vault-Auswahl bei konkretem Nichttreffer. Kein neues Extension-Unlock-Feature.

### F-13 — P2 — Serververtrag und tatsächliche CRUD-Datenintegrität teilweise live abgenommen

- [ ] F-13: Verbleibende Live-Matrix vor einer Server-/Produktionsfreigabe abnehmen.

**Status:** `LiveServerContractTests` bestand am 2026-11-03 auf einer eigens kurzlebig
eingerichteten lokalen Vaultwarden-1.37.5-Instanz mit synthetischem Account. Login/Handoff,
Refresh, Sync mit vorbereitetem Passkey-Eintrag, Cipher/TOTP-CRUD, Attachment-Transfer und
Text-/Datei-Send-CRUD bestanden. Der damalige Serverlauf übte keine Login-TOTP-Challenge aus. Ein neuer flüchtiger lokaler
1.37.5-Lauf am 2026-11-06 aktivierte TOTP für einen synthetischen Account und bestand die echte
Login-Challenge. Derselbe Lauf fand, dass der Einzelgeräte-Widerruf mit 404 abgelehnt wird und das
Gerät bestehen bleibt (F-33); er ist daher nicht als erfolgreicher Widerruf zu werten. Der erste
Zwei-Geräte-Lauf am 2026-11-06 ließ beide gleichzeitigen Cipher-PUTs durch und reproduzierte den
Verlust eines unabhängigen Feldwerts. Nach der Korrektur aus F-35 sendet die App
`lastKnownRevisionDate`; ein wiederholter Lauf wartete 2,1 Sekunden nach dem gemeinsamen Snapshot,
worauf Vaultwarden 1.37.5 den veralteten Write mit HTTP 400 ablehnte und der angenommene Feldwert
erhalten blieb. Das ist keine atomare Merge-Garantie: der geprüfte Handler hat eine Ein-Sekunden-
Toleranz. Andere Serverversionen und enger getaktete Writes bleiben zu prüfen. Weiterhin nicht
getestet wurden Organisations-/Collection-Datensätze,
OS-Passkey-Registrierung/Assertion und die tatsächliche Produktions-Serverversion. Der Owner-Smoke-Test gegen Produktion steht aus und bleibt vollständig manuell
und vom Owner gesteuert; automatisierte Test-Runner verwenden keine Produktionsdaten.
F-13 ist damit teilweise belegt, aber offen für einen Anspruch auf Server-/Produktionsreife.
Der Testserver wurde nach dem Lauf entsorgt; Details und Image-Digest stehen in
[IntegratedAcceptance.md](IntegratedAcceptance.md).
**Orte:** Tests/AppModulesArchitectureTests/LiveServerContractTests.swift; Docs/IntegratedAcceptance.md.

Der lokale Zwei-Geräte-Vertrag und die stale-write-Ablehnung ergänzen die Matrix; die Wiederholung
auf der tatsächlichen Zielserverversion sowie sichtbare Konflikterkennung/-wiederherstellung in der
App bleiben offen. Testserver-Zugang nicht aus gefundenen Konfigurationen übernehmen.
**Abnahme:** Login/TOTP/Refresh, Sync, alle schon unterstützten Editoren, Attachments, Text-/File-Send und Device Revocation. Vor/nach Roundtrip: nicht dargestellte Felder, History und URI-Metadaten unverändert. Unknown-Payload read-only, Re-Prompt-Secret-Sperre, partielle Decryptfehler und bestätigte Writes mit lokaler Reparatur prüfen.

### F-14 — P2 — UI-/Lifecycle-Matrix aller bestehenden Scope-Funktionen unvollständig

- [ ] F-14 im beschriebenen Umfang abschließen.

**Status:** Gate, keine pauschal bewiesenen UI-Bugs.
**Orte:** VaultPresentation, SendPresentation, AuthPresentation, SettingsPresentation, App/RootView, Docs/FeatureStatus.md und ursprünglicher Plan.

Visible-text-/XCUITest-Nachweise, iPad/Fenstergrößen, Multi-Scene, Accessibility, Privacy Shield, PIN/Biometrie, Timeout, Clipboard und native Menüs fehlen als abgeschlossene Matrix.
**Abnahme:** Jede unterstützte Funktion unten mit Codepfad, Unit-/Integration-Nachweis und Geräteabnahme dokumentieren. Fehler und Recovery sichtbar; keine zugeklappten/globalen Fehlertexte, die einen bestätigten Write zum Retry verleiten. Nicht unterstützte Features bleiben explizite Nicht-Ziele.

### F-15 — P2 — Simulator-/Build-Reproduzierbarkeit und Preflight

- [x] F-15: Lokale Runtime und Runner prüfen; Remote-CI separat F-19.

**Status:** Automatische Simulatorauswahl, Boot und kompletter nativer Integrationslauf bestehen jetzt. Auch explizite Ziele werden jetzt vor dem Build validiert und gebootet (F-25); Remote-CI bleibt F-19.
**Umsetzung:** `Scripts/test-integration.sh` führt für das ausgewählte Gerät vor Paket-/Build-Arbeit `simctl bootstatus <ID> -b` aus. `Scripts/test-integration-preflight.sh` simuliert einen als verfügbar gelisteten, aber nicht bootfähigen Simulator und prüft 14 Ablehnungsfälle; Script bestanden.
**Historische Umgebung des vorherigen Reviews:** Lokales `simctl list devices/runtimes` meldete „CoreSimulatorService connection became invalid“ und „unable to discover runtimes“. iOS-Simulatorintegration und Gerätetests waren damit nicht möglich. Kein Runtime-Download oder globales Cache-Löschen vorgenommen. macOS-Integration bestand separat.
**Aktuell:** `simctl list devices available -j` meldete zwölf verfügbare iOS-Simulatoren. Der gemeinsame Runner bootete sein automatisch gewähltes Ziel und bestand anschließend 17/17 iOS-Integrationstests; beide Plattformen bauen außerdem Debug/Release. Der frühere lokale Runtime-Blocker ist damit für diesen Lauf nicht mehr vorhanden. F-25 ist lokal behoben; **offen bleibt Remote-CI (F-19)**. Keine Runtime installiert und keine globalen Caches gelöscht.

### F-16 — P1 — RustSec-Treffer in eingebautem SDK benötigen Upstream-Fix

- [ ] F-16 im beschriebenen Umfang abschließen.

**Status:** Gepinntes SDK und aktueller offizieller HEAD auditiert; zwei Vulnerabilities verbleiben
im relevanten Zielgraphen. Der Owner hat am 2026-11-08 die Fortsetzung mit diesen
verbleibenden Upstream-Befunden beauftragt; behoben sind die beiden Findings damit nicht. Ein Source-only-Paket führt den SDK-
Code nicht aus, enthält ihn aber samt Buildweg; Befunde müssen dabei sichtbar bleiben. Die
Rechtefrage für diese SDK-Materialien ist separat F-17.
**Übernahme 2026-11-08:** SDK-Pin auf `a13b4c4e1fa3685280241f417920fd19d7ef24a6`, Rust
1.99.0 und UniFFI 0.32.0 aktualisiert; kompatible Cargo-Updates werden jetzt durch den
verbindlichen Patch `0003-update-sdk-dependencies.patch` reproduzierbar im normalen Build
angewendet. Alle fünf Release-Slices sind gebaut und installiert. Aktuelles Lockfile:
`4d87866952641365ab38c937087c1b1e2f42d343a5c45b48353b10acc764ae38`.
Der erneute Audit (RustSec-DB `309392b18f6b17022f82c701f300433126901068`, 1.422 Advisories)
meldet zwei Vulnerabilities (`crypto-bigint` 0.5.5 und `rsa` 0.10.0-rc.19) sowie acht
Unmaintained-Warnungen; frühere Unsound-/Yanked-Warnungen entfallen.
Der Owner hat ausdrücklich entschieden, mit den kompatiblen Aktualisierungen und verbliebenen
Upstream-Befunden fortzufahren. Die Findings bleiben offen und sichtbar; daraus wird keine
Aussage über dieselbe Exposition der offiziellen App abgeleitet. Inventare und Rebuildnachweis
sind aktualisiert. Die nachfolgenden Versuchsstände sind historische Evidenz, keine Beschreibung
des jetzt eingebundenen SDKs.

**Aktualisierung 2026-11-06:** `cargo-audit` gegen das unveränderte gepinnte `Cargo.lock` mit RustSec-Datenbank `5c26bd59903e07edadefe5af8a7350e4c588e199` (1.417 Advisories) erneut ausgeführt: dieselben 11 Vulnerability-Einträge, 8 unmaintained, 1 unsound und 2 yanked. Exit 1 entspricht den gemeldeten Advisories. JSON-Nachweis lokal `${TMPDIR:-/tmp}/vw-review-audit-20261106.json`; Bewertung und Abhilfe bleiben offen.
**Isolierter Abhilfeversuch 2026-11-06:** Ein separater Checkout des Pins aktualisierte nur
Cargo-Lockfile-Abhängigkeiten: `h2` 0.4.16, `rustls` 0.23.46 (mit `rustls-webpki` 0.103.16),
`ctutils` 0.4.4 sowie `webpki-roots` und `webpki-root-certs` 1.0.10. Der Audit meldet in diesem
Versuch noch zwei statt elf Vulnerability-Einträge: `crypto-bigint` 0.5.5 und `rsa` 0.10.0-rc.18.
`cargo check --locked -p bitwarden-uniffi` bestand mit Rust 1.96.0 für `aarch64-apple-darwin` und `aarch64-apple-ios`.
Der verbleibende `crypto-bigint`-Pfad führt über `elliptic-curve`/`p256` in die FIDO- und
Passkey-Abhängigkeiten; der Fix benötigt mindestens 0.7.6 statt der transitive gebundenen 0.5.5.
Für das RSA-Timing-Advisory ist laut RustSec weiterhin kein gepatchtes Release angegeben.
Der gepinnte SDK-[Quellpfad](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/crates/bitwarden-crypto/src/enc_string/asymmetric.rs)
verwendet `rsa_private_key.decrypt(Oaep, data)` bei der Entkapselung asymmetrisch geteilter Schlüssel;
das ist mehr als eine ungenutzte optionale SSH-Funktion. RustSec beschreibt den Marvin-Angriff als
netzwerkseitig beobachtbaren Timingkanal mit hoher Angriffskomplexität. Dieser Aufrufpfad macht
das Advisory für Vault-/Organisationsschlüssel relevant, beweist aber weder eine praktisch
ausnutzbare Timingmessung in dieser App noch einen erfolgten Angriff. Die beiden Befunde bleiben
offen, bis sichere Upstream-Abhilfe und Regressionen vorliegen.
**Zusätzlicher Versuchsnachweis (Dokumentationsstand vor der erneuten App-Integration):** Der vollständige experimentelle SDK-Neubau für alle fünf
Apple-Architekturen bestand. Die neu erzeugten Swift-Bindings stimmen byteweise mit den vorhandenen
Bindings überein; der SDK-FFI-Smoke mit dem neu gebauten Framework bestand. Die damaligen
offenen App-/Extension-Tests sind im weiter unten datierten Nachweis erledigt; eine Übernahme in
den regulären SDK-Build steht weiterhin aus.
Das ist **kein** aktualisiertes ausgeliefertes SDK: Der Release-Pin, das vorhandene Binary und
seine elf Befunde bleiben unverändert; ein Check ersetzt keinen Multi-Target-Release-Build, FFI-/App-
Regressionen oder die Klärung der beiden verbleibenden Advisories. Die isolierte Versuchskopie und
das Audit liegen lokal unter `${TMPDIR:-/tmp}/vw-sdk-dependency-trial.OMI54N`. Der reproduzierbare [experimentelle Lockfile-Patch](../Scripts/patches/0002-sdk-dependency-mitigation-experimental.patch) wird vom regulären Build noch nicht angewendet. Cargo änderte dabei
auch einige Windows-Abhängigkeitsauflösungen; vor Übernahme den vollständigen Lockfile-Diff prüfen.
**Audit:** SDK-Pin `fbd21679c1c3690cba424ad3dbb0ba662eb9863e`; zugehöriges offizielles `Cargo.lock` SHA-256 `1a8918fba61d5823bb9be7a4b15c30d2184a70fcbb1d9dd3416eba945bb742fd`, 731 Dependencies. `cargo-audit` 0.22.2 mit RustSec-Datenbank vom 2026-11-02 12:45:44+01:00 (1.402 Advisories) meldete 11 Vulnerabilities, 8 unmaintained, 1 unsound und 2 yanked Packages.
**Treffer und Reichweite:** Vulnerabilities: `crypto-bigint 0.5.5` (RUSTSEC-2026-0387), `ctutils 0.4.2` (0385), `h2 0.4.15` (0258), `rsa 0.10.0-rc.18` (2023-0071), `rustls 0.23.42` (0346/0285/0348/0349), `rustls-webpki 0.103.13` (0382), `webpki-root-certs 1.0.9` (0383) und `webpki-roots 1.0.9` (0381). `cargo tree` für `bitwarden-uniffi`/`aarch64-apple-ios` bestätigte insbesondere crypto-bigint über P-256/FIDO, rsa über `bitwarden-crypto` und rustls/h2/Reqwest über den SDK-HTTP-Pfad. Rustls wurde mit `ring, logging, std, tls12` gebaut; die Brotli-Funktion von 0348 ist in dieser Featurekombination nicht aktiv. Tokio 1.53.1 ist als unsound gemeldet (0386). Als unmaintained gemeldet: basic-toml, bincode, buf_redux, fxhash, multipart, safemem, twoway und unsafe-libyaml. Yanked: chacha20 0.10.1 und wnaf 0.14.0. Das Audit meldet diese Pakete; es beweist nicht für jeden Advisory eine praktisch ausnutzbare Schwachstelle im App-Kontext.
**Früherer Upstream-Abgleich (vor dem direkt folgenden neueren Vergleich):** Im vorherigen Review
enthielt der damals geprüfte Stand `36e5096b274ecfd82c1eccd9aeec3277ca43effb` die zentralen
betroffenen Versionen. Der am 2026-11-06 geprüfte Snapshot `ca53f727655ae58acc278fa8bea3894636445286`
meldete elf Vulnerability-Einträge. Dieser Snapshot ist inzwischen durch den unten dokumentierten
HEAD `a13b4c4e1fa3685280241f417920fd19d7ef24a6` ersetzt; der Pin-Audit bleibt unverändert. Das
iOS-Normal-/Build-
Dependency-Tree für den Pin enthält 428 eindeutige Paketversionen (macOS: 427); er ist kein Runtime-
Exploitability-Beweis. Ergebnisse und gepatchte Versionsbereiche stehen in
[SDKAdvisoryInventory.json](ThirdParty/SDKAdvisoryInventory.json). Kein blindes Pin-Upgrade und keine manuelle Änderung generierter SDK-Dateien vorgenommen. Benötigt wird ein kompatibler Upstream-Fix und danach neuer Lockfile-Audit samt SDK-/App-Regression.
**Primärquellen:** [crypto-bigint timing advisory](https://rustsec.org/advisories/RUSTSEC-2026-0387.html), [RSA Marvin timing advisory](https://rustsec.org/advisories/RUSTSEC-2023-0071.html), [ctutils advisory](https://rustsec.org/advisories/RUSTSEC-2026-0385.html), [rustls Brotli advisory](https://rustsec.org/advisories/RUSTSEC-2026-0348.html), [rustls-webpki advisory](https://rustsec.org/advisories/RUSTSEC-2026-0382.html). Der Audit beweist nicht, dass jeder gemeldete Pfad praktisch ausnutzbar ist; die genannten Pfade sind im Zielgraphen vorhanden.

**Kandidat gegen App-Quellstand geprüft 2026-11-06:** Das experimentelle Framework wurde in eine
isolierte Kopie des aktuellen Quellstands eingesetzt; das reguläre SDK-Artefakt im Arbeitsbaum
blieb unberührt. `Scripts/test-packages.sh` bestand dort mit SDK-Smoke 1, AuthPresentation 69,
AppModulesArchitecture 845 und 2 XCTest (die beiden Live-Server-Tests waren übersprungen).
Die nativen Integrationsschemata bestanden auf macOS 27.2 und iPhone-18-Pro-Simulator/iOS 27.2,
jeweils 18/18. macOS- und iOS-App samt AutoFill-Extension bauten außerdem unsigned in Debug und
Release. Das bestätigt die Swift-/FFI-/App-Kompatibilität dieses Kandidaten für diese Toolchain;
es ist weder ein signierter Geräte-/Servernachweis noch eine Freigabe des SDK-Patches. Zwei
RustSec-Advisories bleiben, Cargo änderte auch Windows-Auflösungen, und der Patch wird weiterhin
nicht vom regulären Build angewendet. Die Versuchskopie und Testresultate lagen außerhalb des
Repositories und werden nicht mitveröffentlicht. Vor einer SDK-Übernahme müssen die beiden
Restbefunde und der vollständige Lockfile-Diff geklärt werden.

**Erneuter offizieller Upstream-Abgleich 2026-11-06:** Der aktuelle öffentliche `sdk-internal`
HEAD `a13b4c4e1fa3685280241f417920fd19d7ef24a6` wurde frisch geklont und sein unverändertes
`Cargo.lock` mit `cargo-audit` 0.22.2 gegen RustSec-Datenbank
`309392b18f6b17022f82c701f300433126901068` (1.422 Advisories, aktualisiert 2026-11-06)
geprüft. Ergebnis: weiterhin zwei Vulnerabilities, `crypto-bigint 0.5.5` (RUSTSEC-2026-0387)
und `rsa 0.10.0-rc.19` (RUSTSEC-2023-0071); der Passkey/FIDO-Zielgraph zieht ersteres über
`elliptic-curve 0.13.8`/`p256 0.13.2`, und der iOS-`bitwarden-uniffi`-Graph enthält RSA. Die
RSA-Entschlüsselung von Shared Keys ist im aktuellen SDK-Quellpfad weiterhin vorhanden. Damit
behebt auch der aktuelle offizielle HEAD die zwei blockierenden Advisories nicht. Das ist ein
neuerer Upstream-Audit, keine Freigabe des gepinnten SDK und kein getestetes Ersatz-Framework;
Revision, Lockfile-Hash (`ab52599f2acf0954f5b85214ffc96d9357d8819bc23171e066bc9d11170ce93b`),
Audit-JSON (`${TMPDIR:-/tmp}/vw-upstream-current-audit.json`) und Checkout
(`${TMPDIR:-/tmp}/vw-upstream-current.ibCL4E/sdk`) sind lokal festgehalten. Insbesondere bleibt
eine RSA-Ersetzung oder das Deaktivieren kompatibler Organisations-/Passkey-Funktionen eine
Upstream-/Produktentscheidung und wird hier nicht durch einen selbst gebauten Krypto-Patch
ersetzt.

### F-17 — P2 — SDK-/Source-Lizenz für Source-only geklärt

- [x] F-17 für den beschriebenen Source-only-Umfang abschließen.
- [x] Gepinnten Upstream-Lizenzrouter, UniFFI-Manifest, Swift-Subtree-Lizenz und beigefügte
  Lizenztexte abgleichen; vorhandene Upstream-Alternativen und Gesamtwerk-Frage dokumentieren.
- [x] Owner wählt GPL-3.0-only für eigene Dateien (Code/Dokumentation/Assets), ohne Fremdcode
  umzulizenzieren.
- [x] Für SDK-Bestandteile, die der gepinnte Upstream dual lizenziert, GPLv3 als die vom Upstream
  ausdrücklich angebotene Lizenzoption für diesen Source-Release wählen; GPL-Pflichten des
  kombinierten Werks und Source-Notices erfassen.
- [x] SDK-Source-Umfang, Upstream-Ausnahmen, generierte Bindings und Dependency-Lizenzdeklarationen
  anhand der Inventare abgleichen; Drittmaterialien mit abweichender Lizenz separat kennzeichnen.

**Abschluss 2026-11-07:** Owner hat GPL-3.0-only für eigene Dateien (Code/Dokumentation/Assets)
gewählt. Für SDK-Quellen, die der gepinnte Upstream standardmäßig unter GPLv3 **oder** Bitwarden
SDK License v2 anbietet, ist hier die upstream angebotene GPLv3-Option gewählt. Das ist keine
Umlizenzierung: Bitwarden bleibt Rechteinhaber; die Option stammt aus dessen Lizenzrouter und
UniFFI-Crate-Manifest. Die App und ihre eigenen Dateien werden unter GPL-3.0-only zusammen mit
diesen GPLv3-SDK-Bestandteilen als Source-Release angeboten. Vorhandene Upstream-Lizenztexte und
Notices bleiben enthalten. Dateien mit abweichenden Upstream-Hinweisen oder ausgenommenen
Bereichen werden nicht von dieser Wahl erfasst. Die Quellenliste/Hashes, 731-Paket-Inventar,
Zielgraph-Zuordnung und MPL/Public-Suffix-List-Notice sind dokumentiert; nicht eingebundene
Abhängigkeiten werden beim Build nach den eigenen Upstream-Lizenzen bezogen. Drittmaterialien mit
abweichender Lizenz behalten diese. Damit ist F-17 für die Source-only-Publikation abgeschlossen;
dies ist keine Freigabe eines kompilierten Binärprodukts, für das konkrete Artefakte und deren
Notices separat zu bewerten sind, und keine externe Rechtsberatung.
**Orte:** THIRD_PARTY_NOTICES.md, Docs/ThirdParty, Packages/VaultwardenSDK/Sources, SDK-Cargo-Features.

[SourceMaterialInventory.json](ThirdParty/SourceMaterialInventory.json) erfasst 30 tatsächliche
Source-/Support-/Dataset-/Lizenz-/SDK-Patch-Dateien mit Bytehashes;
[SDKDependencyInventory.json](ThirdParty/SDKDependencyInventory.json) erfasst 731 Pakete und die
Upstream-Lizenzdeklarationen sowie tatsächliche Feature-Unionen der iOS-/macOS-Build-Trees. Drei Workspace-Pakete verwenden einen Lizenzdateinamen statt einer
SPDX-Expression und liegen nicht im geprüften iOS-Normal-/Build-Tree. `check-source-materials.swift`
prüft die tatsächlichen Dateien, ihre Hashes und ausgeschlossene private/build/signing-Materialien
im Git-Index. Manipuliertes Inventar wird korrekt abgelehnt; das ersetzt keine Lizenzprüfung.
Die Root-Lizenz deckt projekt-eigene Dateien (Code, Dokumentation und Assets) ab. Upstream-SDK-
Quellen, Fremd-Dependencies und Dataset behalten ihre jeweiligen Lizenzbedingungen. Quellcode-
Publikation enthält generierte Upstream-Materialien. Notices allein sind keine geprüfte
Distributionsberechtigung.
**Inventarabgleich 2026-11-06:** Die bestehende Zielgraph-Union enthält 428 unterschiedliche
Paketversionen, darunter 41 mit deklarierter Alternative `GPL-3.0-only OR
LicenseRef-Bitwarden-SDK` und zehn mit deklarierter `MPL-2.0`; der Rest hat überwiegend
permissive oder mehrfache Lizenzdeklarationen. Diese Zählung umfasst Normal- und Build-Abhängigkeiten,
nicht nur in einem konkreten Binary enthaltenen Code. Die [Bitwarden-Lizenz des Pins](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/LICENSE)
enthält ausdrückliche Verzeichnis-/Dateiausnahmen; [MPL 2.0](https://www.mozilla.org/en-US/MPL/2.0/)
ist separat zu beachten. Das Inventar ist der Scope-Nachweis, nicht selbst die Lizenzwahl; die
upstream angebotene GPLv3-Option und die getrennte Behandlung der MPL-Dateien sind in diesem F-17
Abschluss festgehalten.
**Zusätzliche Upstream-Einschränkung:** Das README des festgepinnten SDK-Commits erklärt das
Passwortmanager-SDK als nicht für öffentliche Nutzung bestimmt und von Bitwarden nicht unterstützt;
die Schnittstelle sei instabil. Das entscheidet die konkrete Lizenzfrage nicht, ist aber ein
separates Support-/Veröffentlichungsrisiko. Das öffentliche offizielle Swift-Paket
`bitwarden/sdk-swift` ist eine reale Alternative für iOS; sein aktueller `Package.swift` deklariert
aber nur `.iOS(.v13)` und bezieht ein iOS-XCFramework von einem Bitwarden-Blob-Endpunkt. Es liefert
keinen macOS-Slice für dieses macOS-/iOS-Projekt. Das erklärt den lokalen Mehrplattform-Neubau,
belegt aber weder eine Berechtigung noch die Sicherheit des verwendeten SDKs. [Hinweis im gepinnten
Upstream-README](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/README.md),
[offizielles Swift-Paketmanifest](https://github.com/bitwarden/sdk-swift/blob/main/Package.swift).
**Klauselabgleich 2026-11-06 (SDK-Lizenzpfad; nicht gewählt):** Der tatsächlich beigefügte SDK License v2 Text bindet eine Nutzung
an dessen Annahme (§ 2.1–2.2). Der begrenzte Grant (§ 3.1) erlaubt Entwicklung/Test/Demo einer
`Compatible Application`, aber verbietet, diese an Dritte anzubieten, zu lizenzieren oder zu
verkaufen; § 3.3 untersagt SDK-Nutzung für andere oder nicht kompatible Bitwarden-Implementierungen.
§ 3.4 untersagt Kopie/Änderung/Weiterverteilung des SDK, § 3.5 verweist SDK-Bestandteile mit
Open-Source-Lizenz auf deren jeweilige Bedingungen. Daneben nennt die Upstream-Root-Notice für
Quellen grundsätzlich GPLv3 **oder** Bitwarden SDK License v2, mit Verzeichnis-/Dateiausnahmen.
Die App zielt ausdrücklich auf Vaultwarden; diese SDK-Lizenzroute hat daher ungeklärte
Kompatibilitäts- und Drittoffer-Fragen und wird nicht gewählt. Grundlage: [gepinntes Upstream-Lizenzdokument](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/LICENSE_SDK.txt),
[gepinntes Root-Lizenzrouting](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/LICENSE).
**Upstream-Optionen und Projektwahl 2026-11-07:** Für Quellmaterial nennt das gepinnte
Root-`LICENSE` standardmäßig ausdrücklich zwei Wahlmöglichkeiten: GPLv3 oder Bitwarden SDK License,
außer bei abweichenden Dateiköpfen bzw. Inhalten in `bitwarden_license/`. `bitwarden-uniffi` deklariert
`GPL-3.0-only OR LicenseRef-Bitwarden-SDK`; der Swift-Upstream-Unterordner enthält zusätzlich eine
`LICENSE_GPL.txt`. Das beigefügte GPL-Dokument wurde gegen beide Upstream-Kopien geprüft; es stimmt
bis auf den abschließenden Zeilenumbruch überein. Die SDK-Lizenz § 3.5 verweist OSS-Komponenten
wiederum auf deren OSS-Lizenzbedingungen. Zum damaligen Prüfzeitpunkt war für SDK-Quellen noch keine
Option ausgewählt; der Owner hatte GPL-3.0-only für eigene Dateien festgelegt. Die spätere
Source-only-Auswahl der upstream angebotenen GPLv3-Option ist im Abschlussabschnitt dokumentiert.
Primärquellen:
[Upstream-Lizenzrouting](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/LICENSE),
[UniFFI-Crate-Manifest](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/crates/bitwarden-uniffi/Cargo.toml),
[Swift-GPL-Text](https://github.com/bitwarden/sdk-internal/blob/fbd21679c1c3690cba424ad3dbb0ba662eb9863e/crates/bitwarden-uniffi/swift/LICENSE_GPL.txt).

**Abnahme:** Für Source-only sind Projektcode und die vom Bitwarden-Upstream dual lizenzierten
SDK-Bestandteile unter der jeweils ausdrücklich verfügbaren GPLv3-Option erfasst. Andere Dritt-
materialien behalten ihre jeweiligen Lizenzen und Notices. Ein späterer Binär-Release benötigt
weiterhin die konkrete Prüfung seiner enthaltenen Artefakte, Buildmaterialien und Notices.

### F-18 — P2 — Secrets-/Assets-/Historienfreigabe nur teilweise belegt

- [ ] F-18 im beschriebenen Umfang abschließen.
- [x] Aktuellen getrackten/unignorierten Textbestand und neue/untracked Dateien mit dem
  synthetisch regressionsgeprüften Muster-Scanner prüfen; Fundinhalte nicht ausgeben.
- [x] Alle erreichbaren Git-Refs nach den zehn dokumentierten Tokenfamilien durchsuchen.
- [x] Source-CI lädt für diesen Guard die vollständige erreichbare Historie und führt den
  Historienmodus aus; der Remote-Workflow selbst bleibt bis zu einem CI-Lauf unter F-19 offen.
- [x] Den aktuellen Source-only-Kandidaten als Snapshot ohne Git-Historie festlegen; alle
  gegenwärtigen Dateien und Hashes sowie die Ausschlüsse im
  [Kandidatenmanifest](SourceReleaseCandidate.json) erfassen. Alte Einzelchecklisten bleiben
  entfernt, da ihre Aufgaben in dieser Liste zusammengeführt wurden.
- [ ] Finalen Release-Commit/Tag und den tatsächlichen Veröffentlichungsumfang festlegen und
  freigeben. Musterprüfungen decken nicht beliebige persönliche Daten oder alle Secret-Formate ab.
- [ ] Bei installierbarer App die Absicht hinter schwarzen Icons bestätigen oder Assets ersetzen.

**Status:** Der genaue aktuelle Arbeitsbaum ist als Source-only-Snapshot ohne Git-Historie
inventarisiert; maschinenspezifische Home-/Volume-/Scratch-Pfade sind aus den Review-Dokumenten
entfernt. Das Manifest enthält Hashes für 494 vorhandene Kandidatendateien; es selbst ist separat
aus der Hashliste ausgenommen. Bei der Erfassung bestanden 93 geänderte/getrackte Einträge,
9 ungetrackte Dateien und zwei bewusst entfernte alte Checklisten. Der Kandidat basiert auf HEAD
`de5bd0aed51dc87d95ff97d1ca3680968d8f72c3` plus den aufgeführten lokalen Änderungen. Es wurde
weder ein Release-Commit/Tag erstellt noch etwas veröffentlicht. Die abschließende Scope-Freigabe
und ein manueller Blick auf beliebige personenbezogene Inhalte bleiben offen.
**Aktualisierte Prüfung 2026-11-07:** Der Secret-Musterscan bestand für 484 Textdateien, der
Source-Material-Guard für 30 inventarisierte Dateien; die Pfade und SHA-256-Werte im Kandidaten-
manifest stimmen byteweise mit dem aktuellen Arbeitsbaum überein. `git diff --check` bestand.
**Prüfung:** Am 2026-11-06 erneut 2.167 UTF-8-Blobs und 7 Binär-Blobs aller erreichbaren Git-Refs
mit zehn Tokenfamilien durchsucht, keine Treffer. Das ist jetzt mit
`swift Scripts/check-source-secrets.swift --history` reproduzierbar. Der Swift-Scanner nimmt auch
neue unignorierte Dateien, generierten SDK-Source und alle UTF-8-Dateitypen auf. Auf dem aktuellen
Arbeitsbaum erkannte er 483 Textdateien, ebenfalls ohne Musterfund. `bash Scripts/test-source-secrets.sh`
prüft synthetische Tokens, neue Dateien, Lizenz-/Dataset-Dateien, generierten SDK-Source sowie
einen Commit mit anschließend gelöschter Token-Fixture in der Historie; der Fixture-Inhalt wird
nicht ausgegeben. Der private Handoff ist ausdrücklich in
`.gitignore` ausgeschlossen und bleibt unverändert lokal. Vorher waren nur 444 getrackte eigene
Dateien abgedeckt; der Scanner prüft jetzt auch neue und generierte Quellen. Der vorhandene Bericht
Ein lokaler Bericht enthält weiterhin nur die frühere Drei-Muster-Prüfung und wurde nicht
überschrieben; ein aktuelles historisches Scan-Log wurde nicht angelegt. Lokale Berichte werden
nicht mitveröffentlicht.
**Assets:** Alle elf getrackten PNGs sind App-Icons und wurden jetzt pixelweise geprüft: RGB-Kanäle überall exakt 0, keine Transparenz. Das 1024-px-Icon wurde zusätzlich visuell geprüft und ist vollständig schwarz. Design-/Asset-Owner muss bestätigen, ob das beabsichtigt ist; ein Ersatz wäre eine eigene Gestaltungsaufgabe. Keine vertraulichen Bildinhalte in diesen schwarzen Icons erkennbar.
**Grenze:** Keine beliebigen Passwörter, Kontaktdaten, reflog-only Objekte oder sämtliche Tokenanbieter abgedeckt. Die private `CLAUDE_HANDOFF.md` wurde auf Restaufgaben abgeglichen und bleibt unverändert/unversioniert; sie enthält private Arbeitskonfiguration und gehört nicht ins Source-Release. Historie nicht umgeschrieben; Originale/Backups/Signing-Dateien und den finalen Veröffentlichungsumfang separat prüfen.

### F-19 — P2 — Kein externer Fresh-Clone-/Remote-CI-Nachweis und Toolchain-Differenz

- [x] Lokalen SDK-Neubau aus gepinntem Upstream und Prüfung von Pin, Patch, Lockfile,
  generierten Bindings und Framework-Inventar in einem frischen Source-Overlay ausführen.
- [x] Source-Guards, Architekturregeln, beide Paket-Tests und die nativen macOS-/iOS-Simulator-
  Integrationsbundles im Overlay ausführen.
- [x] SwiftFormat-Lint, Contributor-Konfigurations-Fixtures, Simulator-Preflight-Fixtures und die
  gepinnte XcodeGen-Version ausführen.
- [x] macOS- und iOS-App samt AutoFill-Extension unsigned in Debug und Release bauen.
- [x] Produktstand `24dc262` aus unabhängigem Git-Checkout mit Xcode 26.3 in GitHub CI
  bauen: [Lauf 42416802473](https://github.com/temmiland/vaultwarden-native/actions/runs/42416802473) erfolgreich.
- [ ] Die SDK-Aktualisierung vom 2026-11-08 erneut in Remote-CI abnehmen.

**Lokaler SDK-Stand 2026-11-08:** Pin `a13b4c4` mit verbindlichen kompatiblen
Dependency-Updates: alle fünf Rust-Release-Slices, SDK-Smoke, 858 Architekturtests/101 Suites,
69 AuthPresentation-Tests sowie 18 macOS- und 19 iOS-Integrationstests bestanden. App und
AutoFill-Extension bauen in Release auf beiden Plattformen unsigned; Quellen-, Architektur-,
Format-, Konfigurations- und Preflight-Prüfungen bestehen. Der erste GitHub-Lauf für `b3ea723`
scheiterte beim Tool-Download mit Transferfehler 56 vor dem SDK-Build; beide Downloader
wiederholen nun begrenzt fehlgeschlagene Transfers und übernehmen nur vollständige,
prüfsummengeprüfte Archive. Der direkte Release-Download von SwiftFormat scheiterte trotz
Wiederholungen; derselbe offizielle Release-Asset über die GitHub-API ist erreichbar und hat
die identische gepinnte SHA-256. Beide Downloader verwenden daher den offiziellen
API-Asset-Endpunkt mit festem Asset-ID, Version und SHA-256.

**Neuester lokaler Nachweis 2026-11-06:** Eine frische Source-only-Kopie des vollständigen aktuellen
Arbeitsstands wurde als frische lokale Source-only-Kopie außerhalb des Repositories erstellt. Sie
übernahm weder `.git`,
ignorierte SDK-Binaries, lokale Konfiguration noch private Handoff-Dateien; der im Overlay neu
initialisierte Git-Index enthält den kopierten Quellstand einschließlich neuer unignorierter Dateien.
Mit Xcode 27.2 (Build 27B52), Swift 6.4.2 und macOS 27.2 SDK wurde dort
`bash Scripts/build-sdk.sh --install` erfolgreich ausgeführt: alle fünf SDK-Slices gebaut; Upstream-
Pin `fbd21679c1c3690cba424ad3dbb0ba662eb9863e`, Patch-Hash
`95f74e5f6d544be11f8b3542bbf90dd7ad4fc9ae00ad2ca5f3389041622748df`, Cargo.lock
SHA-256 `1a8918fba61d5823bb9be7a4b15c30d2184a70fcbb1d9dd3416eba945bb742fd` und beide generierten
Swift-Source-Bäume geprüft. Danach bestanden Architektur- (205 Swift-Dateien), Secret- (483 Textdateien)
und Source-Material-Guards (30 Materialien), beide Guard-Negativtest-Suites, SDK-Smoke, beide
Paket-Tests (AppModules: 846 Tests/100 Suites; AuthPresentation: 69; dazu 2 XCTest) und der vollständige
`Scripts/test-integration.sh`-Lauf (macOS und iOS Simulator, Exit 0). Der Live-Serververtrag war
ausdrücklich nicht aktiviert; `SERVER CONTRACT: NOT RUN`. `build-unsigned.sh`
bestand für Debug und Release, jeweils mit macOS- und iOS-Simulator-App plus AutoFill-Extension.
Die übrigen lokalen CI-Fixtures bestanden ebenfalls: SwiftFormat 0/366, Contributor-Konfiguration
(positive Debug-/Release-Matrix plus drei Ablehnungsfixtures), Simulator-Preflight (3 automatische
und 1 explizite positive Auswahl, 19 Ablehnungsfälle plus Boot-Reihenfolge) und XcodeGen 2.46.0.
`rustup` 1.29.2 und aktives Rust 1.97.1 wurden inventarisiert; der SDK-Build verwendete explizit
die gepinnte Toolchain 1.96.0. Der vollständige Historienmodus des Secretscanners wurde separat im
ursprünglichen Git-Repository ausgeführt und ist unter F-18 belegt.
Der vollständige SDK-Arbeitsbaum lag im ignorierten Scratch-Verzeichnis dieser Kopie und ist kein
Bestandteil des Source-Releases.

Dieser Lauf schließt den lokalen Neubau und die lokale Source-only Build-Matrix, aber weder einen
Git-Checkout des finalen Commits noch eine unabhängige Maschine oder Remote-CI. Der CI-Workflow pinnt
Xcode 26.3, während die lokale Toolchain Xcode 27.2 ist. Toolchain-Gleichheit und Remote-CI bleiben
offen; aus der Workflow-Konfiguration wird kein erfolgreicher Lauf abgeleitet. Signing, echte Geräte,
Produktionsserver und der optionale Live-Serververtrag sind ebenfalls nicht Teil dieses Nachweises.

**Historische Nachweise:**
**Vorheriger Nachweis:** Jeweils `VaultwardenMac` und `VaultwardenIOS` samt Extensions unter Xcode 27.2 Debug/Release erfolgreich; macOS- und iOS-Integration jeweils 17/17. Gemeinsamer Runner vollständig Exit 0, Server NOT RUN. CI pinnt in beiden Jobs Xcode 26.3; dessen Vorhandensein ist in der offiziellen macOS-15-Runner-
Inventarliste nachgewiesen, die Ausführung aber nicht. Lokale Xcode-27.2-Evidenz ersetzt diese
Compilerprüfung nicht. Die lokale frische Clone-/Overlay-Kopie mit 492 byteweise verglichenen
Dateien bestand Source-/Material-/Tool-Checks, ohne private Dateien/SDK-Binaries zu kopieren;
sie wurde nicht als kompletter Fresh-Clone-App-/SDK-Neubau auf anderer Maschine ausgegeben.
Das bewegliche `brew install xcodegen` wurde ersetzt durch dasselbe
`Scripts/xcodegen.sh` wie lokal: 2.46.0 und SHA-256 des offiziellen Release-Archivs. Version und
Projektgenerierung lokal erfolgreich; kein Remote-CI-Lauf und kein frischer Checkout mit vollständig neu gebautem gepinntem SDK nachgewiesen.
**SDK-Smoke 2026-11-06 (vor dem neuesten Neubau):** `Scripts/test-rebuilt-sdk.sh .build/sdk-isolated/build.7GBokw`
prüfte den bereits vorhandenen isolierten SDK-Neubau erneut gegen Pin, originales Lockfile und
generierte Bindings und bestand den FFI-Smoke. Der Neubau selbst stammt aus einem früheren Lauf;
es ist kein erneuter frischer SDK-Build und kein Remote-CI-Nachweis.
**Weiterer Snapshot 2026-11-06:** Eine danach erstellte lokale Clone-/Overlay-Kopie bestand
Architektur-/Secret-/Materialguards, alle Pakettests und beide unsignierten Debug-App-/Extension-Builds. Sie
nutzte das aus einem früheren isolierten SDK-Neubau übernommene Framework und geteilte Git-Objekte;
spätere Test-/Dokumentationsänderungen einschließlich des experimentellen Lockfile-Patches fehlen
darin. Es ist deshalb weiterhin kein Build eines finalen Commits oder unabhängigen Fresh-Clone.
**Zusätzlicher Quellstandstest 2026-11-06:** In einer isolierten lokalen Clone-/Overlay-Kopie
wurden die damals vorhandenen getrackten Änderungen und neuen unignorierten Dateien staged,
`git diff --cached --check`, Architektur-, Secret- und Materialchecks sowie beide Pakettests
bestanden. Das SDK-Framework wurde aus dem bereits vorhandenen isolierten SDK-Neubau in diese
Kopie übernommen; 844 Architekturtests einschließlich zwei explizit übersprungenen Serverfällen,
69 AuthPresentation-Tests, ein SDK-Smoke und zwei XCTest. Spätere Änderungen dieser Runde sind in
dieser Kopie nicht enthalten. Eine lokal geteilte Git-Objektdatenbank und ein vorhandenes Framework
sind kein unabhängiger frischer finaler Commit oder erneuter SDK-Build.
**Offen:** Unterstützte Toolchain festlegen und sauberen Clone mit exakten Versionen für SDK-Smoke, beide Packages, native Bundles sowie Debug/Release belegen. Kein CI-Erfolg aus Workflow-Datei ableiten.

### F-20 — P3 — Dokumente enthalten widersprüchliche/historische Abschlussstände

- [x] F-20: Öffentliche Statusangaben nach erneutem Review korrigieren.

**Status 2026-11-06:** README verweist auf datierte Nachweise, benennt den begrenzten lokalen Serververtrag und dessen offene Pfade; veraltete Testzahlen und die gegenteilige Aussage wurden entfernt. F-13 bleibt offen.
**Abnahme:** README mit `Verification.md`, Abschnitten 5/6, abgleichen; lokalen 1.37.5-Vertrag und offene Pfade korrekt benennen, historische Zahlen und Skips kenntlich machen. Auch F-13 muss als offener Teilnachweis in der einzigen Checkbox-Liste sichtbar bleiben.
**Umsetzung:** Auf ausdrücklichen Auftrag alle Arbeitslisten in diese Datei übernommen, neue Findings ergänzt, ursprüngliche Task-/Defekt-/Phasen-IDs zugeordnet und überflüssige Checklisten/Reviews entfernt. Plan, Statusübersicht und Nachweislogs verweisen hierher; deren datierte Implementierungsgeschichte bleibt als Historie erhalten. Die Aussagen aus den beiden alten Home-Reviews sind hier integriert und durch neuere Belege ausdrücklich korrigiert.

### F-21 — P2 — Distribution/Signing/Sandbox und Security-Kontakt brauchen Owner-Abnahme

- [ ] F-21 im beschriebenen Umfang abschließen.

**Status:** bewusst offene Owner-Gates; kein Source-only-Codefehler.
**Orte:** App/VaultwardenMac.entitlements (`app-sandbox=false`), ContributorConfiguration, SECURITY.md und die Source-/App-Gates dieser Datei.

Endgültige Bundle IDs, Team, App Groups, macOS-Verteilungsweg und tatsächliche Entitlements sind nicht abschließend freigegeben. Security-Mail-Adresse und Erreichbarkeit sind jetzt vom Owner bestätigt; keine Testmail gesendet.
**Abnahme:** Für spätere installierbare Apps signierte Zielkonfiguration und OS-Features prüfen. Für Source-Publikation den geklärten GPL-/Notice-Scope aus F-17, Secret-/Statusprüfung und unauditierten Lernstatus im finalen Source-Stand erhalten. Postfach-Gate durch Owner-Bestätigung erledigt; keine Testmail nötig. Store-Strategie nicht eigenmächtig wählen. Source-Commit/Tag und Veröffentlichung erst auf Auftrag.


## F-22–F-25: neue Review-Befunde, lokal behoben

### F-22 — P2 — Upload ignoriert Swift-Task-Cancellation

- [x] Den echten Upload-Task beim Abbruch kontrolliert abbrechen und Race-Regressionen ergänzen.

**Umsetzung:** Collector besitzt den echten Upload-Task unter demselben Lock wie die Continuation.
Ein Cancellation-Handler stoppt den Task vor oder nach dessen Anlage; Completion, Limitüberschreitung
und Cancellation reservieren die Continuation genau einmal. Nach terminalem Ergebnis werden die
Response-Puffer freigegeben. Regressionen: vorab gecancelt startet nicht, Abbruch ohne Serverantwort,
Lock cancelt den realen Transfer, Completion-/Cancel-Stress und bestehende Response-Limits.
Gezielter Networking-/File-/SDK-Lauf: 33 Methoden/4 Suites bestanden. Originalbefund vor Fix:

**Historischer Reviewstatus:** Mit den damaligen unveränderten Produktionsdateien reproduziert; oben genannter Fix ist jetzt aktiv.
**Ort:** `Packages/AppModules/Sources/Networking/URLSessionHTTPClient.swift`,
`upload(_:fromFile:)` und `LimitedUploadResponseCollector.upload`, ungefähr Zeilen 28–40/251–261.
Der bisherige native async URLSession-Upload wurde durch einen manuellen `uploadTask` mit
`withCheckedThrowingContinuation` ersetzt. Der Collector hält den Task nicht und besitzt keinen
`withTaskCancellationHandler`/Cancellation-Check. Das `finishTasksAndInvalidate()` im defer
wartet auf ausstehende Arbeit und ersetzt kein `cancel()`.

**Reproduktion:** Die drei unveränderten Networking-Dateien `HTTPTypes.swift`,
`HTTPRetryAfter.swift`, `URLSessionHTTPClient.swift` zusammen mit einem synthetischen
URLProtocol-Executable kompilieren. Das Protocol meldet `startLoading`, hält seine Antwort zurück;
aufrufenden Task abbrechen, `stopLoading` beobachten, anschließend synthetisches HTTP 200 liefern.
Tatsächlich: `transport stopped after cancellation: false`,
`cancelled upload returned HTTP 200`. Temporär ausführbar unter
`${TMPDIR:-/tmp}/vaultwarden-review-upload-cancel.swift` und gleichnamigem Binary.
Kein echter Server und keine vertraulichen Upload-Daten beteiligt.

**Folge:** Lock/Logout cancelt in `SessionRuntime` den Swift-Task, stoppt diesen Transport aber
nicht mehr; Dateitransfer/Servermutation kann bis zum Netzwerktimeout fortlaufen. Der äußere
Runtime-Fence verweigert späte Ausgabe weiterhin. Kein bewiesener Lock-Bypass und keine Garantie,
dass ein schon übertragener Serverwrite widerrufbar wäre.
**Umsetzung:** Task und Cancellation-State synchronisiert besitzen, Abbruch vor Taskanlage ebenso
wie während des Uploads weiterreichen; Continuation exakt einmal abschließen, auch bei zeitgleicher
Completion/Limitüberschreitung. Ein bereits bestätigter Write muss weiterhin operationseigen korrekt
behandelt werden, ohne einen sicheren Rollback vorzutäuschen.
**Abnahme:** Deterministische Tests für vorab gecancelten Caller, Abbruch nach Taskstart,
Cancel/Completion-Race, zu großen Upload-Response und Runtime-Revocation. Keine Requests nach
vorherigem Abbruch starten; blockierte Übertragung endet; keine Continuation-Leaks/Doppel-Resume.
Zuordnung: A-204, S-306, F-701/F-703, T-1001; ergänzt F-08/F-11.

### F-23 — P1 — Persistierte Timeout-Lease verwechselt Uptime verschiedener Systemstarts

- [x] Freigabe/Timeout zuverlässig an den Systemstart binden; Altdaten sicher behandeln.

**Umsetzung:** Schema 4 bindet jeden Grant an `SystemBootSession.currentID()` aus
`kern.bootsessionuuid`. Fehlende Boot-Identität wirft, fremde Boot-ID verweigert die Freigabe;
keine Timestamp-/Prozess-UUID-Ersatzwerte. Auch `.never` gilt nur im selben Systemstart.
Die publizierten alten Daten werden bei Verweigerung nicht gelöscht. 17 Shared-Unlock-Methoden
bestanden, einschließlich verschiedener Boot-IDs mit kleinerer/überlappender/größerer Uptime,
gleicher Boot-ID nach Prozessneustart, alter Schema-Version und fehlgeschlagener Boot-Abfrage.
Codefix abgeschlossen; reale Geräte-/Schlaf-/Upgrade-Abnahme bleibt ausdrücklich F-02/X-605.
Primärquelle: [Apple XNU sysctl declaration](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_sysctl.c).
Originalbefund vor Fix:

**Historischer Reviewstatus:** Alte Store-Grenze reproduziert; Codefix siehe oben, echte Geräteabnahme bleibt separat.
**Ort:** `Data/SharedAutoFillUnlock.swift`, `SharedSystemContinuousClock`,
`SharedAutoFillTimeoutLease.isExpired`, `SharedAutoFillUnlockStore.load`.
Das gespeicherte Envelope enthält Start-/Deadline-Nanosekunden, aber keine Boot-Identität.
`now < startedAt || now >= deadline` erkennt nur einen Teil möglicher Neustarts.

**Reproduktion gegen die gebauten Produktmodule:** Synthetisches In-Memory-Keychain,
Store A mit Uhr `10_000_000_000` ns; Grant speichern und 1-Minuten-Timeout setzen, damit Deadline
`70_000_000_000` ns. Store B über **dieselben Bytes** mit neuer Uhr `20_000_000_000` ns erstellen,
als neue Boot-Uptime nach beliebig langem ausgeschaltetem Gerät. `load() != nil` ergibt true,
`expiredTimeoutAction() == nil` ebenfalls true. Temporärer Test:
`${TMPDIR:-/tmp}/vaultwarden-review-reboot.swift`; gegen originale SwiftPM-Produktobjekte gelinkt.

Damit ist das Interpretationsproblem bestätigt; die Uhrwerte allein können die zwei Systemstarts
prinzipiell nicht unterscheiden. Der Test ist kein echter Geräteneustart und kein nachgewiesenes
Umgehen von iOS-Keychain- oder User-Verification-Schutz. Nach Unlock des Geräts können persistierte
WhenUnlocked-Werte wieder lesbar sein; deshalb reicht der bisherige Rollback-Test (`now = 1`)
als Reboot-Schutz nicht.
**Umsetzung:** Geeignete plattformübergreifende Boot-Bindung bzw. nachvollziehbare fail-closed
Neustart-Policy festlegen; keine Wall-Clock-only-Umstellung. Fehlende/unlesbare/andere Boot-ID
darf alten Grant nicht wieder authorisieren. Gewollte `.never`-Semantik explizit festlegen.
Bei Schemaänderung bestehende Recovery berücksichtigen; Credentials nicht still löschen.
**Abnahme:** Verschiedene Boot-IDs mit kleinerer **und größerer überlappender** Uptime verweigern,
gleiches Boot mit Prozessneustart korrekt behandeln, Deadline-Grenze, Uhrzeitänderung,
Schlaf, nicht verfügbare Boot-ID, alte Schemas; anschließend signiertes Gerät + Extension mit
Reboot/erster Geräteentsperrung prüfen. Zuordnung F-02, S-302/S-306, X-605/T-1004.

### F-24 — P2 — Gemeinsames Regex-Budget ersetzt den zugesagten Einzelschutz

- [x] 25-ms-Einzelbudget zusätzlich zum gemeinsamen 100-ms-Filterbudget erhalten.

**Umsetzung:** Jeder Regex hat wieder 25 ms zusätzlich zur gemeinsamen 100-ms-Deadline.
Auch die Compile-Phase wird danach an dieser Deadline geprüft. Ein einzelner Abbruch markiert
`isIncomplete`, beendet aber nicht unnötig die ganze Abfrage; spätere normale Treffer bleiben
möglich. Deterministische injizierte Uhren prüfen beide Grenzen und die partielle Ausgabe;
pathologischer Real-Regex sowie URI-/Query-Suite: 33 Methoden bestanden. Originalbefund vor Fix:

**Historischer Reviewstatus:** Im damaligen Code-Diff bestätigt; oben genannter Fix ist jetzt aktiv.
**Ort:** `AutoFillData/URIMatching.swift`, `URIQueryMatchingContext` und `.regularExpression`.
`de5bd0a` setzte vor jedem einzelnen Regex eine Deadline von 25 ms. Der aktuelle Diff entfernt
sie und verwendet ausschließlich die Context-Deadline, standardmäßig 100 ms. Die öffentliche
Einzelmatch-Funktion baut ebenfalls einen 100-ms-Context. Der bisherige Handoff behauptete
fälschlich, beide Grenzen blieben erhalten. Der vorhandene pathologische Test verlangt nur `< 2 s`
und erkennt die Lockerung nicht. Der Code bleibt begrenzt; kein neuer unbegrenzter ReDoS behauptet.

**Umsetzung:** Effektive Deadline als Minimum aus Anfrage-Deadline und eigener Einzeldeadline
prüfen. Ein nur einzelner überteurer Regex darf weitere normale Kandidaten nicht unnötig aus
dem Gesamtbudget verdrängen. Den vorhandenen unvollständigen Ergebnisstatus sauber fortführen;
keine Erweiterung der Match-Berechtigungen.
**Abnahme:** Injizierbare monotone Uhr/Progress-Fence für beide Grenzen; Regex-Caching,
Cancellation, gültige/ungültige/Unicode-Patterns und unveränderte Nonregex-Semantik. Reales
pathologisches Pattern zusätzlich mit großzügigem Hänge-Schutz; keine fragile 25-ms-Walltime-Assertion.
Zuordnung F-03, V-404/T-1001.

### F-25 — P2 — Explizites Simulatorziel umgeht den frühen Boot-Preflight

- [x] `VW_IOS_TEST_DESTINATION` vor jedem langen Build auf bootfähiges Ziel auflösen/prüfen.

**Umsetzung:** Der Runner akzeptiert nur `platform=iOS Simulator,id=<UUID>` als explizites Ziel.
Der Selector validiert genau einen verfügbaren iOS-Eintrag (auch iPad); unbekannte, ungültige,
falsche Plattform- und mehrdeutige IDs scheitern vor Paket-/Buildarbeit. Der Boot-Check ist
unabhängig vom Auswahlweg verpflichtend. Harness: drei automatische positive/fünf negative,
ein expliziter positiver/vier negative Selector-Fälle, 19 Runner-Ablehnungen und ein positiver
Boot-vor-Build-Fall bestanden. Konkrete Syntax im Integrations-Runbook dokumentiert.
Originalbefund vor Fix:

**Historischer Reviewstatus:** Mit synthetischen CLI-Stubs reproduziert; oben genannter Fix ist jetzt aktiv.
**Ort:** `Scripts/test-integration.sh`, etwa Zeilen 38–64;
Tests `Scripts/test-integration-preflight.sh`.
`TASK_SIMULATOR_ID` wird nur bei automatischer Auswahl gesetzt. Ein explizites
`platform=iOS Simulator,id=…` wird lediglich am Präfix geprüft; der spätere
`if [[ -n "${TASK_SIMULATOR_ID:-}" ]]` überspringt die Bootprüfung.

**Reproduktion:** Explizite synthetische UDID, `xcrun`-Stub mit Fehler und `swift`-Stub mit
Marker `BUILD_REACHED_BEFORE_BOOT_CHECK`/Exit 99. Der Produktionsrunner erreicht tatsächlich
`architecture rules` und Exit 99, statt Boot-Refusal/Exit 2. Kein Simulator wurde für diesen
Fall gestartet. Log `${TMPDIR:-/tmp}/vaultwarden-review-explicit-preflight.log`.
**Umsetzung:** Explizite ID/Name/OS-Destination validieren und eindeutig auf verfügbare UDID
auflösen oder nur klar dokumentierte ID-Syntax unterstützen. Bootfähigkeit unabhängig vom
Auswahlweg prüfen. Keine fremden Simulatoren löschen oder unaufgefordert Runtimes installieren.
**Abnahme:** Explizites Ziel bootbar/kaputt/fehlend/mehrdeutig, malformed und falsche Plattform
ablehnen, bevor Packages/Builds beginnen; automatische Auswahl weiter grün. Zuordnung F-15/T-1005.

## Scope und Abnahmematrix

Die folgende Produktmatrix beschreibt vorhandenen Scope, keinen vollständigen Geräteerfolg.
Konkrete Restarbeit steht ausschließlich bei den F-IDs; Testszenarien im AutoFill-/Integration-
Runbook sind Prüfrezepte und keine zweite abhakbare Liste.

| Vorhandener Scope | Noch benötigter Nachweis / Finding |
|---|---|
| HTTPS-Serversetup, Passwortlogin und TOTP-2FA | F-11, F-13; richtige KDF-/Fehler-/Challenge-Grenzen, kein Secret in UI-Fehlern |
| Refresh, Session Expiry, Lock/Logout | F-02, F-10, F-11; Neustart und App-/Extension-Prozesse |
| Master-Passwort-, PIN-, Biometrie-Unlock | F-10/11/14; persistente PIN-Versuche, Enrollment-Recovery, Widerruf während Prompt |
| Vault Sync, Suche, Filter, Lesen, Ordner-/Collection-Anzeige | F-01, F-13/14; partielle Fehler und unbekannte Typen sichtbar |
| Bereits vorhandene Login/Card/Identity/Note/SSH-Editoren | F-13; verlustfreie Metadaten, stale Drafts, Confirmed-Write-Recovery |
| Generator, Kopieren und TOTP-Anzeige | F-14; bestehende Generator-/Clipboard-Regressionen plus reale Laufzeit-/Lockgrenzen |
| Attachments | F-08, F-13/14; geschützte Preview, Originbindung, Cleanup und Disk-full |
| Text-/File-Sends | F-08, F-13/14; Daten-/Datumsgrenzen, unklare Writes, Uploadtickets |
| Geräte anzeigen/widerrufen | F-07, F-13 |
| Timeout | F-02 |
| Password-/TOTP-AutoFill, vorhandene Passkey-Flows | F-03/04/12; OS-End-to-End, Recovery und aktuelle Index-/Cache-Autorität |
| Menüleiste/Quick Access/Launch at Login | F-05/06/14 |
| Universal Layout, Multi-Scene, Accessibility, Privacy Shield | F-14 |

Ausgeschlossen bleiben zusätzliche 2FA-Verfahren, neue Cipher-Editoren, Multi-Account, Haupt-App-Offline-Vault, Background Sync, Extension-Unlock und neue Verwaltungsendpunkte. Auf Owner-Auftrag vom 2026-11-07 kommt natives Passwortspeichern auf iOS/iPadOS 26.2+ hinzu; auf macOS bleibt der App-Editor zuständig. Re-Prompt-Items bleiben ohne bewiesenen Master-Passwort-Grant gesperrt; Read-only ist eine vorhandene Sicherheitsentscheidung.


### Vollständiges Produktinventar aus FeatureStatus

| Function | Status | Platforms | Required release checks |
| --- | --- | --- | --- |
| Custom HTTPS Vaultwarden server, login, TOTP login | implemented | macOS, iOS, iPadOS | unit tests and manual smoke test |
| Session refresh, lock and logout | implemented; app runtime revocation and cleanup recovery | macOS, iOS, iPadOS | unit, lifecycle and cross-process token-rotation tests |
| Master-password, PIN and biometric unlock | implemented | macOS, iOS, iPadOS | unit tests and device smoke test |
| Items requiring master-password re-prompt | restricted: no secret access, mutations or AutoFill | macOS, iOS, iPadOS | access-policy, stale-cache and revocation fixtures; device smoke test |
| Vault sync, list, search, filters and details | implemented | macOS, iOS, iPadOS | unit and integration tests |
| Login, card, identity, secure-note and SSH-key editing | implemented; local stale-draft/permission guards | macOS, iOS, iPadOS | round-trip, save-recovery and permission fixtures; UI tests |
| Bank account, driver's license and passport | read-only metadata; no payload editor | macOS, iOS, iPadOS | capability-matrix tests |
| Unknown cipher types, blob-format or malformed cipher payloads | unavailable with partial-vault warning; not editable | macOS, iOS, iPadOS | mapping/error-recovery contract tests |
| Unknown fields on otherwise readable ciphers | known contents readable; editor, delete, attachment mutations and passkey registration read-only | macOS, iOS, iPadOS | nested-shape/cache/race fixtures; fresh sync for older caches; server/device checks |
| Password generator, secret copying and TOTP display | implemented | macOS, iOS, iPadOS | fallback minimum-count/error-recovery tests, clipboard tests and manual smoke test |
| Attachments | implemented; transfer/lifecycle polish pending | macOS, iOS, iPadOS | transfer tests and manual smoke test |
| Text and file Sends | implemented; protected file transport and typed cleanup, real lifecycle checks pending | macOS, iOS, iPadOS | unit tests and manual smoke test |
| Device list and device revocation | implemented | macOS, iOS, iPadOS | unit tests |
| Password, TOTP and passkey AutoFill | implemented; invocation revocation guarded, projection consistency pending | macOS, iOS, iPadOS | contract and device integration tests |
| Menu bar, quick access and launch at login | implemented | macOS | manual smoke test |
| Email, Duo, YubiKey or WebAuthn login 2FA | not supported | — | documented scope |
| Account registration/recovery and multi-account | not supported | — | documented scope |
| Custom fields, folders, collections, trash, restore and archive management | not supported | — | documented scope |
| Main-app offline vault, background sync and conflict resolution | not supported | — | documented scope |
| AutoFill password saving | iOS/iPadOS 26.2+: explicit create/update confirmation, encrypted server writes, durable uncertainty recovery | native and package tests; signed-device acceptance pending | macOS uses app editor; no native save-request API |
| Extension-side unlock | not supported | — | documented scope |
| Vaultwarden administration, reporting and enterprise UI | not supported | — | documented scope |

## Abgleich mit sämtlichen ursprünglichen Planaufgaben

Jede ursprüngliche Task-ID bleibt auffindbar. „Lokal vorhanden“ ist keine vollständige Phase-
oder Gerätefreigabe. Alte Tabellen im Plan sind datierte Historie. Insbesondere inzwischen
vorhandene Golden Files, Domain-Moves, Formatter-Pins, Errorbody-Verwerfen und Refresh-Intents
nicht wegen überholter Tabellen erneut implementieren. ADR 028 ersetzt bewusst den ursprünglichen
observation-only-Handoff; daraus keine neue Umbauaufgabe ableiten. Unbekannte Cipher-Payloads
bleiben read-only statt einen neuen beliebigen JSON-Roundtrip zu entwickeln (ADR 026).

| Ursprüngliche IDs | Geprüfter Stand / verbliebene Aufgabe in dieser Liste |
| --- | --- |
| R-000 | Recovery-Baseline `e465721` / Tag historisch vorhanden; keine neue Baseline nötig. F-21 für finalen Source-Commit. |
| R-001 | Package-/Buildrunner vorhanden und jetzt ausgeführt; F-19, F-25 für Reproduzierbarkeit/Preflight. |
| R-002 | Scope/Disclaimer vorhanden; laufende Pflege hier und F-20. |
| R-003 | Charakterisierungs-/Race-Suites existieren; vollständige Szenarioabdeckung nicht aus Testanzahl ableiten: F-08/F-10–F-14. |
| H-101 | Alter Store entfernt, Observation-State-Owner vorhanden; Publishing-/sichtbare UI-Smokes F-14. |
| H-102, H-103 | Lokale Payload-/Permission-/Draft-/Roundtrip-Fences vorhanden; Unknown-Payload bewusst read-only. Reale CRUD-Roundtrips F-13. |
| H-104 | Deleted-/Archived-Policy vorhanden; OS-/Projection-Lifecycle F-12/F-13. |
| H-105 | Same-origin/Redirect-/Dateinamen-Guards vorhanden; Ressourcen und Transferabbruch F-08/F-22. |
| A-201, A-202, A-203 | Zielgraph/Domain-Modelle und produktive Ports vorhanden; aktuelle Architekturprüfung grün. ADR-028-Abweichung anerkannt; F-11/F-14 für reale Flows. |
| A-204 | HTTP-Limits/Redirects/Body-Verwerfen vorhanden; Upload-Abbruch F-22, Download-/SDK-Limits F-08, ATS-Pfade F-19/F-21. |
| A-205 | Update-then-add/typed Keychain/PIN-/Cleanup-Guards vorhanden; Dual-Failure und echte Prozesse F-10/F-11/F-14. |
| A-206 | Adapter, KDF- und SDK-Feld-/Kardinalitäts-Guards vorhanden; vollständige FFI-/Silent-Degradation-/Servermatrix F-12/F-13/F-16. |
| A-207 | Versionierter Contract und alte/neue Cache-Goldens vorhanden; Boot-/Schema-/Process-Recovery F-02/F-12/F-23. |
| A-208 | Plattformports/injizierbare Clients vorhanden; OS-Fake-/Fehlerkombinationen und echte Systemmatrix F-05/F-06/F-12/F-14. |
| S-301 | Gemeinsame OAuth-/HTTP-/Retry-After-Semantik vorhanden; realer Serververtrag und Fehler-UI F-11/F-13/F-14. |
| S-302, S-303 | Lease/Intent/Commit/Scope-/Epoch-Fences vorhanden; keine neue Refresh-Architektur. Dual-Failure, echte Crash-/Upgrade-/Altclient-Races F-10/F-11; Timeout-Reboot F-23. |
| S-304 | Biometrie-Recovery lokal vorhanden; Cancel/Lockout/Enrollment-Änderung/fehlender Key/OS-Fehler/re-enroll am Gerät F-14/F-21. |
| S-305 | Persistente PIN-Budgets und Failure-Guards vorhanden; parallele PIN-Versuche und reale Keychain-Write-/Disable-Fehler F-10/F-14. |
| S-306 | AppModel/Runtime-Revocation/Recovery vorhanden; Multi-Scene, realer Cleanup-/Reboot-Fehler F-10/F-11/F-14/F-23, Transport-Cancel F-22. |
| V-401 | Repository/FIFO/Single-Flight/Confirmed-Write-Projektion vorhanden; unklare Writes, Serverkonflikte/Recovery und Multi-Scene F-11/F-13/F-14. |
| V-402 | Account-/Grant-/Revisions-Projektion und Initialisierungsfix F-01 lokal geprüft; echte Dateifehler-/Prozess-/Upgrade-Matrix F-10/F-12. |
| V-403 | Gemeinsame Identity-Mutationsordnung und Repair-Journal vorhanden; QuickType, später Daemon-Request, alte Binaries, Review-Freshness/Health-Gaps F-12. |
| V-404 | URI-Modes/PSL/kein identifizierter Vollvault-Fallback vorhanden; F-24 sowie OS-Nonmatch/manuelles Browsing F-12. |
| V-405 | Modellierte Sync-/Teil-Decryption-Fehler/Retry vorhanden; sichtbare Warnungen und realer Sync-Recovery F-13/F-14. |
| U-501 | Settings-Domain-/Observation-Migration vorhanden; Device-Race F-07 lokal korrigiert; echte Revocation/Timeout/PIN F-02/F-13/F-14/F-23. |
| U-502 | Send-Migration/FIFO/Confirmed-Write-Recovery vorhanden; Ressourcen/Cancel/Live-Send F-08/F-13/F-22. |
| U-503 | Vault-Presentation physisch migriert; stale Drafts/unklare Writes/Multi-Scene und sichtbare Recovery F-13/F-14. |
| U-504 | Domain-Auth-Commands/Capability-Handoff vorhanden, ADR-028-Planabweichung; echte Auth-/Recovery-/Multi-Window-Matrix F-11/F-14. |
| U-505 | Shared Universal-Navigation/Layout vorhanden; iPad/Fenstergrößen/Dynamic Type/Accessibility/Multi-Scene F-14. |
| U-506 | AppArchitecture/alte Store-/Processor-Basis entfernt; nicht neu migrieren. Architektur-Guard aktuell grün. |
| X-601 | AutoFillData/Contract/SDK-Callback-Grenze vorhanden; Legacy-Collection-Policy und Silent-SDK-Degradation bewusst prüfen, F-12/F-13. |
| X-602, X-603 | Password/TOTP/Assertion-Orchestrierung/Expiry/Completion-Fences vorhanden; UserVerification/UserHandle/FFI/echter OS-Context F-12. |
| X-604 | Journal/Incremental-Identity/Review-Abandonment vorhanden; Unknown-Schema/Legacy-Origin/Late-HTTP/Kill/Power-loss/Health-/Review-Freshness F-12/F-13. |
| X-605 | Runbook/Fixtures vorhanden, kein kompletter signierter Prozess-/Upgrade-Abschluss; F-02/F-10–F-12/F-23. |
| F-701, F-702, F-703 | Geschützte File-Ports/Multipart/Preview/Send vorhanden; SDK-Whole-file-Heap, Disk-full/Crashreste und Cancel F-08/F-22. |
| P-801 | xcconfig/Runtime-Konfigurationsguard lokal vorhanden; signiertes App-Group/Keychain/Provisioning F-21. |
| P-802 | HTTPS/Debug-Loopback/Redirect-Policy vorhanden; Release-ATS und sämtliche SDK-HTTP-Pfade F-19/F-21; F-08/F-09/F-22. |
| P-803 | Native Menüleiste/Hotkey/Launch-at-Login vorhanden; TCC-/Systemfreigaben F-05/F-06, Sandbox-/Distribution F-21. |
| P-804 | Typisierte Fehler-/Recovery-Zustände vorhanden; sichtbare UI-/Retry-Vermeidung bei bestätigten Writes F-13/F-14. |
| P-805 | Plattformgrößen-/Layout-Komponenten vorhanden; tatsächliche Universal-/Accessibility-Matrix F-14. |
| P-806 | HTTP-Errorbody verworfen, Redaction vorhanden; kompletter Git-/Asset-/Log-/Release-Text-Check F-18. |
| C-901, C-902, C-903 | Zwei lokale Packages, Presentation/Composition-Moves und alte Basisklassenbereinigung vorhanden; Shell-/OS-Adapter gehören bewusst zu Executables. Keine pauschalen Modulmoves; verbleibende Grenzen F-11/F-12/F-14, Artefakte F-18/F-21. |
| C-904 | Aktuelle positive/negative Import-/Konfigurationsguards vorhanden; F-19 für Remote-Nachweis. |
| C-905 | SwiftFormat 0.63.0 mit Hash, Strict Concurrency/Warnings-as-Errors für eigene Targets vorhanden; überholte „noch pinnen“-Forderung nicht wiederholen. Remote-Toolchain F-19. |
| T-1001 | Umfangreiche lokale Unit-/Contract-Suites grün; neue Regressionen F-22–F-25, konkrete Gap-Matrizen F-08/F-10–F-14. Testanzahl ist keine Vollständigkeitsgarantie. |
| T-1002 | Hostlose Composition/Hosting/Controller-Bundles vorhanden; echter sichtbarer Text/XCUITest/ExtensionContext F-12/F-14. |
| T-1003 | Opt-in Live-Test bestand lokal gegen Vaultwarden 1.37.5; Login-TOTP nicht ausgeübt, restliche F-13-Matrix und Produktions-Smoke offen. |
| T-1004 | Signierte Real-Device-Matrix offen; F-02/F-05/F-06/F-10–F-14/F-21/F-23. |
| T-1005 | CI vorhanden, kein nachgewiesener Remote-Erfolg; F-19, Preflight-Fix F-25. |
| L-1101 | GPL-3.0-only für eigene Dateien und die upstream dual lizenzierten SDK-Bestandteile gewählt; Source-only-F-17 erledigt, binäre Artefaktprüfung separat. |
| L-1102 | Isolierter SDK-Neubau historisch dokumentiert; Fresh Clone/Toolchain/Upstream-Fix F-16/F-19. |
| L-1103 | Security/ThreatModel/Architecture vorhanden; Kontaktzustellung/aktuelle Einschränkungen F-21; keine Audit-Freigabe. |
| L-1104 | Lernstatus/Scope/Nichtziele vorhanden; zentraler Status jetzt F-20, vor Source-Release erneut F-18/F-21. |
| L-1105 | Keine Release-Publikation beauftragt; Source-Commit/Tag/Release-Text und spätere Artefaktprovenienz F-18/F-19/F-21. |

### Defektregister D-001–D-027 und Owner-Entscheidungen

| IDs | Abgleich / heutige Zuordnung |
| --- | --- |
| D-001 | Alter State-Fehler durch Architekturwechsel erledigt; H-101/U-506, F-14 für UI-Abnahme. |
| D-002/D-003 | Lokale Edit-/Metadaten-/Unknown-Payload-Fences vorhanden; F-13 für echten Server-Roundtrip. |
| D-004/D-005/D-006 | Zentrale OAuth-/Token-/Retry-Policy vorhanden; reale Rotation/Recovery F-11/F-13. |
| D-007/D-008/D-009 | Match-Modi/kein Vollvault-Fallback/offline MPL-PSL vorhanden; F-24/F-12. |
| D-010/D-011/D-012 | Projektion/Policy/Identity-Repair lokal vorhanden; F-01 abgeschlossen, reale Konsistenz F-12/F-13. |
| D-013/D-014 | Origin-/Dateinamenfences vorhanden; F-09 lokal geprüft, F-08/F-13 für Transferabnahme. |
| D-015/D-016 | Geschützte Dateien/Cleanup vorhanden, Gesamt-Heap/Crash/Disk-full/Cancellation offen; F-08/F-22. |
| D-017 | Release-HTTPS und Debug-Loopback-Policy vorhanden; tatsächliche ATS-/SDK-/Release-Konfiguration F-19/F-21. |
| D-018/D-019/D-020 | Update-then-add/klassifizierte Persistenz/Biometrie-Recovery vorhanden; F-10/F-11/F-14. |
| D-021 | macOS-Sandbox/Distribution bewusst weiterhin Owner-Gate F-21/O-03. |
| D-022/D-023/D-024/D-025/D-026 | Composition/Domain/Observation-Migration lokal vorhanden, Architekturguards grün; keine alten Module wieder einführen. F-14 für reale UI-Flows. |
| D-027 | Typisierte Degradation/Redaction vorhanden, reale Sichtbarkeit/Recovery F-13/F-14; Publikationsscan F-18. |
| O-01/O-02 | Initialer Commit/Recovery und GPL-3.0-only-Ownerwahl erledigt; keine offene Grundsatz-Lizenzwahl für eigenen Code. |
| O-03/O-04 | Sandbox/Distributionsweg/Signing-/IDs-/Team-/App-Group-Ownerentscheidungen bleiben F-21. |
| O-05 | Lokale synthetische Testinstanz mit exakter Vaultwarden-Version und expliziter Testfreigabe für den Vertragstest eingerichtet; Produktionsversion/Owner-Smoke separat offen. |

### Übergeordnete Phasen und Quality Gates

Keine pauschale Komplettfreigabe aus historischen leeren Phase-Checkboxen ableiten. Die folgende
Zuordnung ersetzt die zwölf konkurrierenden Phase-Checkboxen des Plans; tatsächliche Arbeit wird
nur oben bei F-IDs abgehakt.

| Phase / Gate | Abschluss noch abhängig von |
| --- | --- |
| 0 Baseline | Aktuelle lokale Matrix/F-19; alter Wortlaut „vier D-001-Tests rot“ ist historische Baseline, keine heute gewünschte Failure. |
| 1 unmittelbare Defekte | Lokale Fixtures vorhanden; aktueller Build/realer Daten-Roundtrip F-13/F-19. |
| 2 Modulgrenzen | Lokale Imports/Packagegraph grün; vollständige App-Integration F-19. |
| 3 Auth/Session | F-02/F-10/F-11/F-14/F-23. |
| 4 Vault/Sync | F-12/F-13/F-24; keine atomare Server/Cache/OS-Transaktion behaupten. |
| 5 Feature-Presentation | F-14/F-19 und dokumentierte ADR-028-Abweichung. |
| 6 AutoFill/Passkeys | F-02/F-10–F-13/F-21/F-23/F-24. |
| 7 Dateien | F-08/F-22 und signierte Cleanup-/Gerätebudgets. |
| 8 Plattform/UI | F-05/F-06/F-14/F-19/F-21. |
| 9 Cleanup | Guards lokal grün; aktuelle Builds/Remote-CI F-19, keine unbegründeten Adapter-Moves. |
| 10 Tests/CI | F-10–F-14/F-19/F-21/F-25. |
| 11 Release Candidate | Vorige App-Gates, SDK-/Lizenz-/Publication F-16–F-19/F-21. Source-only-Ownerfreigabe bleibt separat und ist keine App-Produktionsfreigabe. |

## Lokale Abschlusskommandos und externe Grenzen

```sh
bash Scripts/swiftformat.sh --lint
swift Scripts/check-architecture.swift
bash Scripts/test-architecture-rules.sh
swift Scripts/check-source-secrets.swift
bash Scripts/test-source-secrets.sh
swift Scripts/check-source-materials.swift
bash Scripts/test-integration-preflight.sh
bash Scripts/test-packages.sh
bash Scripts/test-integration.sh
bash Scripts/build-unsigned.sh Debug
bash Scripts/build-unsigned.sh Release
bash Scripts/test-configuration.sh
bash Scripts/build-sdk.sh --check
```

`--check` inventarisiert vorhandene SDK-Bytes read-only. Historischer Vergleich:
`swift Scripts/sdk-artifact-inventory.swift Packages/VaultwardenSDK/Frameworks/BitwardenFFI.xcframework --verify Docs/SDKLocalArtifactInventory.json`.
Hashabweichungen untersuchen statt das Manifest blind zu ersetzen. Fresh Clone benötigt
`bash Scripts/build-sdk.sh --install`; getrennte Neubauverifikation/FFI-Smoke siehe
`SDKRebuildVerification.md`. Tooldownloads benötigen Internet. Ein Pakettest gegen lokal vorhandene
FFI-Bytes beweist keinen neu gebauten SDK- oder anderen-Rechner-Erfolg.

Keine Live-Konfiguration/Produktionscredentials aus lokalen Dateien übernehmen. `--with-server`
benötigt isolierte Instanz, exakte Version, synthetischen Account/Passkey-Cipher und ausdrückliche
Schreibfreigabe. Postfach-Zustellung nicht eigenmächtig per Mail testen. Keine Zertifikate/IDs/
Distributionsstrategie auswählen, kein Runtime-Download und keine globalen Caches löschen.

### Konsolidierung und erhaltene Nachweise

Entfernt nach Übernahme: separate `Docs/ReleaseChecklist.md`, überholtes
`Docs/Planning/PROJECT_AUDIT.md` sowie die zwei alten Home-Reviews
`vaultwarden-review-handoff.md` / `vaultwarden-findings-gpt6-luna.md`.
Die alte Audit-Empfehlung, vorhandene Funktionen pauschal zu deaktivieren, war bereits durch
den verbindlichen Scope überholt und wird nicht erneut als Aufgabe eingeführt. Alle D-001–D-027,
ursprünglichen Tasks, zwölf Gates und F-01–F-21 sind oben zugeordnet. Architekturdetails und
historische Umsetzungsevidenz bleiben im ursprünglichen Plan und den ADRs erhalten.

`FeatureStatus.md` beschreibt nur Produktumfang. `Verification.md`/`SDKRebuildVerification.md`
sind datierte Nachweislogs, `AutoFillLifecycleChecks.md`/`IntegratedAcceptance.md` detaillierte
Abnahmeanleitungen. Sie führen keine eigene aktuelle Checkliste. Die vorgefundene private
`CLAUDE_HANDOFF.md` wurde auf doppelte Restaufgaben geprüft, aber weder verändert noch entfernt
oder zur Veröffentlichung freigegeben. Sie wird inzwischen ausdrücklich ignoriert und ist kein aktueller Arbeitsauftrag an GPT-6-Luna.
