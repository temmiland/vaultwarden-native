# ADR 024 – Physische Presentation-Grenzen und explizite Composition

Datum: 2026-09-28. Status: umgesetzt; lokale Tests/Builds separat protokolliert.

## Ausgangslage

Die vier UI-Targets waren bereits Domain-only, lagen aber noch unter alten `*Feature`-Pfaden.
AutoFillFeature war weitgehend eine leere Grenze; Picker/Registration-Views lagen im Apple-
Controller-Target und bezogen ihr Metadatenmodell aus AutoFillData. Send/Settings konnten ohne
explizite Composition einen produktiven HTTP-Client erzeugen. Namen in der App-Shell beschrieben
abgeschlossene Migrationen weiterhin als Legacy.

## Entscheidung

- Auth/Vault/Send/Settings liegen physisch unter `Sources/*Presentation`. Target-Namen, Verhalten,
  Tests und historische Keychain-Service-Namen bleiben unverändert; kein Storage-Schemawechsel.
- AutoFillFeature enthält die gemeinsamen SwiftUI-Views mit öffentlichen Initializern. Es hängt
  nur von Domain, SharedUI und AutoFillContract ab, nicht von AutoFillData/SDK/Storage/HTTP.
- AutoFillLoginSummary liegt als transienter Metadata-only Wert im Contract. Vorhandene
  redigierte Beschreibung und Werte bleiben gleich; kein neuer Codec, keine Migration.
- Beide Apple-Extension-Targets importieren AutoFillFeature. Controller/Request-Übersetzung und
  Apple-Context bleiben in der Extension, Query/Write/Recovery-Policy in AutoFillData.
- AppComposition besitzt einen HTTPClient und injiziert ihn in Auth/Vault/Send/Settings.
  DefaultSendRepository/DefaultSettingsRepository verlangen diesen Port im Initializer.
  AppSessionAdapter und PersistentTimeoutDriver benennen ihre aktuelle Composition-Aufgabe.
- Source-/Manifest-Guards verweigern UI-Datenimporte und konkrete Live-HTTP-Factories außerhalb
  Networking/Composition. Sechs negative Wegwerf-Fixtures überprüfen die Guard-Wirkung.

## Verifikation und Grenzen

Vollständiger AppModules-Lauf nach den endgültigen Moves: 782 Swift-Testing-Methoden/102 Suites
und zwei XCTest-Tests, alle bestanden. Keine Assertions entfernt, keine neue Funktion. Unsigned
Debug-/Release-App-/Extension-Builds beider Plattformen bestanden nach den endgültigen Moves;
Befehle und Konfiguration sind in der Verifikation erfasst.

Ein Source-Regex ersetzt keinen AST-/Architektur-/Security-Audit. Compiles ersetzen keine echte
Apple-Controller-/UI-/Geräteprüfung. Der konkrete Data-Assembly-Zugriff liegt absichtlich im
Composition Root, nicht in Features. Vollständige Auth-Commit-/Recovery-Grenzen und reale
Prozess-/Server-/OS-Matrix bleiben offen. SDK und offizielle Checkouts wurden nicht geändert.
