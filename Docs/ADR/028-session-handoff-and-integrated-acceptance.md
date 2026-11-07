# 028 – Session-Übergabe und zusammenhängende Integrationsabnahme

Stand: 2026-09-29. **Status: technische Planabweichung, im Code umgesetzt und lokal geprüft.**
Keine Owner-, externe oder Security-Freigabe; die Owner-Gates O-01 bis O-05 sind nicht berührt.
Betrifft A-203/U-504/T-1002/T-1003/C-904. Keine neuen Serverfunktionen oder Upstream-Änderungen.

## Ursprüngliche Anforderung bleibt unverändert

U-504 verlangt wörtlich: „onAuthenticated Client/Token Callback durch AppModel-Sessionbeobachtung
ersetzen“. Diese Abnahme ist **nicht** erfüllt und wird hier nicht umgedeutet. Der Plantext
bleibt; diese ADR dokumentiert die bewusst gewählte Abweichung und die ersetzende Prüfung.

## Entscheidung

Die Forderung nach einem **vollständig observation-only Auth-Handoff** wird durch eine
einmalige Command-Übergabe einer widerrufbaren Domain-Capability ersetzt. Der Repository-Stream
bleibt die einzige Quelle für Account-/Session-Zustandsänderungen. Er transportiert keine
Tokens, User-Keys, SDK-Clients oder verwendbaren Runtime-Ressourcen.

Ein erfolgreicher Credential-Command erzeugt eine Session-Ressource. Diese benötigt einen
expliziten Lifetime-Owner: `PendingAuthSession.prepareHandoff` ist single-use, der Auth-Coordinator
übergibt die opaque `AuthenticatedSessionCapability` an die App-Composition; nur
`AppComposition.accept` übersetzt die konkrete `AuthenticatedSession` in sessiongebundene
Repositories. Presentation bleibt Domain-only. `AppModel.didAuthenticate` prüft Handoff-Epoch,
Zugriff und Autorisierung, lässt das Repository dieselbe Session-ID bestätigen und veröffentlicht
erst dann die entsperrte App. Lock/Logout/Expiry widerrufen die Runtime und schließen die
Repositories; ein verspäteter, doppelter oder konkurrierender Handoff öffnet die App nicht.

Ein Broadcast derselben Runtime über den Account-State-Stream könnte mehrere UI-Consumer zu
Lifetime-Ownern machen. Ein separater beobachteter Resource-Registry-Port würde eine zweite
konsumierbare Authority, zusätzliche Besitzregeln und neue Race-Flächen einführen. Für den
eingefrorenen Single-Account-Umfang bietet das keinen belegten Vorteil.

## Ersetzende Prüfung

Die hostlosen macOS-/iOS-Bundles führen die echte App-Composition mit isolierter Infrastruktur
aus (Fallliste: [Runbook](../IntegratedAcceptance.md#was-die-nativen-bundles-abdecken)):

- Repository bestätigt dieselbe Session-ID; Lock/Logout widerruft Runtime und Repositories.
- Doppelte Übergabe ist idempotent, eine konkurrierende zweite Runtime wird widerrufen, ohne
  Repository-Snapshot oder Besitz zu ändern.
- Widerrufene Capability, Lock/Logout während blockierter Session-Vorbereitung und
  Cleanup-Recovery öffnen keine Runtime; Cleanup wartet auf laufende Vorbereitung.
- Returning Restore zeigt den gespeicherten Account gesperrt, ohne Unlock-Beginn oder Request.

Minimale Injection-Seams: ein zweiter `AppComposition`-Initializer (Credential-Store, HTTP,
Biometrie, Gerätename, Timeout-Settings, Datei-Lifecycle) und ein `sessionLoader` am
Credential-Provider-Controller. Der Live-Initializer validiert weiterhin zuerst die Storage-
Konfiguration; die Produktion verwendet unverändert den validierten Shared Store. Kein
testabhängiger Fallback in `SharedAppGroup`.

## Ein Arbeits- und Prüfprozess statt dreier unabhängiger Restlisten

`bash Scripts/test-integration.sh` führt nach einem Preflight nacheinander aus:

1. Architekturregeln und beide vollständigen Package-Testtargets.
2. macOS-Xcode-Testbundle mit den echten gemeinsamen App-/Extension-Quellen.
3. Dasselbe Bundle auf einem verfügbaren iPhone-Simulator.
4. Nur mit `--with-server`: den ausdrücklich freigegebenen Live-Server-Vertragstest.

Die Controller-Smokes laden `ASCredentialProviderViewController`, installieren echte native
SwiftUI-Hosting-Controller und ersetzen Invocation-Inhalte. Der UIKit-Containment-Lifecycle wird
mit `willMove(toParent:)`/`didMove(toParent:)` ausgeführt. OS-Completion, PluginKit-Aktivierung,
QuickType, Biometrie und signierte App-Group-Zugriffe werden dadurch **nicht** simuliert bestanden.

## Live-Server-Sicherheitsgrenze

Der Live-Test benötigt konkrete Owner-Version/URL, einen synthetischen Account, einen im
offiziellen Client vorbereiteten Passkey und ausdrücklich erlaubte Mutationen. Credentials
gelangen nur als lokale Prozessumgebung zum finalen Package-Test, nicht in Xcode-Manifeste oder
Git. Der Test verwendet echtes SDK und HTTP, aber eigene Credential-Stores sowie eigene Temp-Pfade.
Der Refresh verwendet die echte Anfrage-Lease und den Intent/Commit-Pfad; nur die testlokale
Token-Expiry wird vor dem Request künstlich abgelaufen gesetzt.

Cleanup löscht ausschließlich bestätigte, von diesem Lauf erzeugte IDs. Bei unbekanntem Write-
Ausgang wird weder Create wiederholt noch anhand eines Namens der Account durchsucht/gelöscht.
Die isolierte Instanz muss dann manuell kontrolliert oder verworfen werden. Rohe Fehler und
Credential-Werte werden nicht ausgegeben. Der Test lief bisher **nie** gegen einen echten Server.

## Nicht durch diese Entscheidung geschlossen

Der Prozess ist keine echte unabhängige App-/Extension-Prozess-, Crash-/Upgrade-, Signierungs-
oder Geräteabnahme und kein XCUITest. Passkey-Registrierung/Assertion benötigt weiterhin echte
OS-Anfragen und User Verification; Server-TOTP-Challenge wird nur bei einem entsprechend
eingerichteten Account ausgeübt. Eine angegebene Server-Version ist Deployment-Metadatum, kein
automatisch attestierter Image-Digest. SDK-Gesamt-Heap, Remote-CI/Fresh-Machine und Owner-
Veröffentlichungsgates bleiben.
