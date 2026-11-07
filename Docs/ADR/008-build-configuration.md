# Gemeinsame Build-Konfiguration und fail-closed Bootstrap

Status: P-801 lokal implementiert und geprüft, 2026-09-27. Quality Gate 5 und signierte
Container-/Keychain-Prüfungen bleiben offen. Kein Release- oder Security-Audit-Nachweis.

## Entscheidung

`Configuration/Base.xcconfig` definiert die bisherigen öffentlichen Identifier und Versionen.
Debug/Release inkludieren Base; Base inkludiert optional eine ignorierte Local.xcconfig.
Persönliche Team-IDs und der SharedAppGroup-Team-Fallback sind entfernt. Alle vier Targets
expandieren dieselben Buildsettings in Info.plist und Entitlements. Ein expliziter App-ID-Prefix
unterstützt Profile mit abweichendem Prefix, ohne Runtime/Entitlement-Zuordnung zu verändern.

`SecurityStorage.AppStorageConfiguration` validiert ausschließlich injizierte, öffentliche Werte:
Bundle-Familie, App Group, getrennte private/shared Services, Prefix-Format und Container-URL.
Bundle-Lookup und Live-FileManager bleiben in `Composition/SharedAppGroup.swift`; Data bekommt
weiter konkrete Keychain-/Container-Ports. Es gibt keinen Team-/Group-Fallback und keine neue
Speicher-/Server-Kompatibilitätsfunktion.

`AppComposition` ist eine einmal erzeugte Instanz, keine Sammlung statischer live Dependencies.
AppStartup trägt entweder diese Instanz und das gemeinsame AppModel oder einen typisierten
Konfigurationsfehler. Die Konfiguration wird geprüft, bevor Credential-Stores/Repository/Model
angelegt werden. Der Fehlerzustand startet weder Login/Restore noch Cleanup und öffnet keine
authentifizierten Scenes. Debug nennt nur den Schlüssel, nicht dessen Wert; Release zeigt eine
stabile Reparaturanweisung. Mac-Menü und Settings verwenden denselben Startup-Zustand.

Extension-Shared-Store-Factories werfen bei ungültigen Werten oder fehlendem Container vor
Keychain-Zugriff. Cache-Reader und Autorisierungsstore erhalten dieselbe einmal aufgelöste
Container-URL. Bestehende Invocation-/Scope-/Revocation-Guards bleiben erhalten.

## Verifikation und Grenzen

Zehn neue Unit-Testmethoden mit parametrisierten Fällen prüfen alle vier Default-Bundle-IDs,
abweichende Contributor-Identifier, Prefix/Entitlement-Separator, fehlende/unexpandierte Werte,
fremde Bundles, getrennte Services, Container-Denial und wertfreie Diagnosen. Das Prüfscript liest
Debug-/Release-Buildsettings aller vier Targets und deren Runtime-/Entitlement-Templates.
Positive Contributor-/Prefix-Overrides und negative fehlende/falsch formatierte Prefix-Werte
wurden tatsächlich ausgeführt. Betroffene Pakettests und beide unsigned Builds bestehen; siehe
[Prüfprotokoll](../Verification.md).

Werteformat und Container-Auflösung beweisen keine signierte Keychain-Berechtigung, Apple-
Registrierung oder ein passendes Provisioning-Profil. Es wurde kein UI-Launch/Device-Smoke und
kein signierter Prozess geprüft. Mac-Sandbox-/Distribution-Entscheidung bleibt P-803, keine
neue Sandbox- oder Hotkey-Policy in diesem Block. App-/Server-/Cross-process-Gates bleiben offen.
Identifieränderungen wählen anderen lokalen Speicher; es gibt keine implizite Credential-Migration.

Contributor-Schritte stehen in [ContributorConfiguration.md](../ContributorConfiguration.md).
