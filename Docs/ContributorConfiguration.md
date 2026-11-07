# Contributor-Konfiguration

Die vier App-/Extension-Targets verwenden gemeinsame `.xcconfig`-Werte. Es ist keine persönliche
Team-ID im Projekt oder Swift-Code hinterlegt. Ein Clone lässt sich unsigned bauen; ohne gültige
Storage-Konfiguration startet aber keine Anmeldung. Die App zeigt stattdessen einen stabilen
Konfigurationsfehler, in Debug mit dem betroffenen Schlüssel. Bestehende Credentials werden
dadurch weder gelöscht noch migriert.

## Eigener Build

1. `Configuration/Local.example.xcconfig` nach `Configuration/Local.xcconfig` kopieren.
2. `DEVELOPMENT_TEAM` durch die eigene zehnstellige Apple-Team-ID ersetzen.
3. Falls erforderlich die Bundle-ID-Familie, App Group und Keychain-Service-Namen an die eigenen
   registrierten Identifier und Provisioning-Profile anpassen. App und Extension müssen dieselben
   Shared-Werte verwenden. Änderungen wählen einen anderen lokalen Speicher, nicht eine Migration.
4. Projekt regenerieren und die Konfiguration prüfen:

```sh
bash Scripts/generate-xcodeproj.sh
swift Scripts/verify-configuration.swift
```

Danach in Xcode die App-Schemes `VaultwardenMac` bzw. `VaultwardenIOS` bauen. Für rein lokale
Compiler-Prüfungen bleibt `./Scripts/build-unsigned.sh` verfügbar. Es registriert keine Identifier
und prüft keine Provisioning-Profile. Ohne passende Signierung kann die Runtime auch mit formal
gültigen Werten den Shared-Container verweigern; dieser Fehler wird nicht durch einen Fallback
umgangen. Ein korrekt signierter macOS-/iPhone-/iPad-Smoke bleibt vor Veröffentlichung
installierbarer Apps erforderlich; die beschlossene Source-only-Veröffentlichung ersetzt diese
spätere Geräteabnahme nicht.

`Local.xcconfig` wird ignoriert. Die committed Beispiel-Datei enthält nur Platzhalter. Team-ID
oder andere lokale Overrides nicht in `project.yml`, Swift-Dateien oder die öffentlichen Defaults
eintragen. Keine Swift-/YAML-Änderung ist für Contributor-IDs nötig.

## Gemeinsame Werte

`Base.xcconfig` enthält die bisherigen öffentlichen Speicher-Defaults. Debug und Release inkludieren
Base; Base inkludiert optional Local. Command-line-Buildsettings haben weiter Vorrang.

| Buildsetting | Verwendung |
| --- | --- |
| `VW_BUNDLE_ID_PREFIX` | macOS-App; `.ios`, `.autofill` und `.ios.autofill` für die weiteren Targets |
| `VW_APP_GROUP_IDENTIFIER` | Container-Auflösung und App-Group-Entitlement aller vier Targets |
| `VW_SHARED_KEYCHAIN_SERVICE` | Shared-Keychain-Service und Suffix der gemeinsamen Access Group |
| `VW_PRIVATE_KEYCHAIN_SERVICE` | Privater Auth-Keychain-Service der App, getrennt vom Shared-Service |
| `VW_KEYCHAIN_PREFIX` | App-ID-Prefix inklusive abschließendem Punkt, identisch in Runtime und Entitlements |
| `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` | Info.plist-Version aller vier Targets |

`VW_KEYCHAIN_PREFIX` ist standardmäßig `$(DEVELOPMENT_TEAM).`. Falls das Provisioning-Profil einen
anderen App-ID-Prefix verwendet, diesen explizit mit abschließendem Punkt in Local setzen. Runtime
und Entitlements verwenden denselben Wert; ein fehlender Punkt wird abgewiesen, nicht heimlich
normalisiert. Der Prefix besteht aus zehn Großbuchstaben/Ziffern plus Punkt. Identifier verwenden
nichtleere ASCII-Labels aus Buchstaben/Ziffern/Bindestrichen, getrennt durch Punkte; die App Group
beginnt mit `group.`. Private und Shared-Keychain-Services dürfen nicht identisch sein.

Default-Bundle-/Storage-IDs, Keychain-Wire-Namen, JSON-Schema und Lock-Dateiname bleiben unverändert.
Ein neuer Team-/App-ID-Prefix oder neue Service-/App-Group-IDs können alte Credentials nicht
automatisch lesen. Der Build führt keine automatische Account-/Cache-Migration aus.

## Was die Prüfungen belegen

Das Prüfscript liest die expandierten Xcode-Buildsettings für Debug und Release, alle vier Bundle-
IDs, die gemeinsamen Storage-/Version-Werte, die Runtime-Info.plist- und Entitlement-Templates
sowie die passende `DEBUG`-Compilerbedingung. Fehlende Prefix-Werte und Template-Mismatch führen
zu einem Fehlercode. Es verändert weder Local.xcconfig noch Signing/Accounts/Credentials.

Die Unit-Tests prüfen synthetische Konfigurationen und verweigerten Containerzugriff. Die Runtime
prüft vor Auth-Komposition Bundle-Identität, Werteformat und Container-Auflösung. Diese Prüfungen
belegen nicht, dass Apple die Identifier registriert hat, ein Profil passt oder ein signierter
Prozess Shared-Keychain-Reads/-Writes tatsächlich ausführen darf. Das gehört weiterhin zu
[AutoFill-Lifecycle-Checks](AutoFillLifecycleChecks.md) und den offenen Release-Gates.
