# Changelog

## Noch nicht veröffentlicht – Review-Folgearbeit 2026-11-02/03/07

- Lizenz für projekt-eigenen Code, Dokumentation und Assets von MIT auf GPL-3.0-only geändert.
  Fremdmaterialien wurden nicht umlizenziert und behalten ihre Upstream-Lizenzbedingungen;
  für die dual lizenzierten Bitwarden-SDK-Quellen wurde die upstream angebotene GPLv3-Option
  für den Source-only-Umfang gewählt (F-17). Binärdistributionen benötigen eine eigene Prüfung.
- AutoFill-Grants an den Systemstart gebunden; Upload-Abbruch an den echten Netzwerk-Task
  weitergereicht; Einzelregex- und Abfragebudget kombiniert; explizite Simulatorziele vor Builds geprüft.
- Datei-Downloads während der Übertragung begrenzt und geschützt veröffentlicht. Byte-Limits
  sind kein Gesamt-Heap-Limit des SDK; bestätigte/unklare Serverwrites bleiben ohne Rollback-Zusage.
- Source-/Dependency-/Advisory-Inventare und Material-/Secret-Guards ergänzt; XcodeGen mit
  Version und Archivhash gepinnt. Eine zentrale Arbeitscheckliste ersetzt überholte Listen.
  Lokale Tests/Builds sowie offene SDK-Sicherheits-, CI-, Geräte- und Servergrenzen stehen in
  [RemainingReleaseWork](Docs/RemainingReleaseWork.md). Keine Veröffentlichungs- oder App-Freigabe.

## 0.1.0-prealpha – Quellcode-Lernprojekt (noch nicht veröffentlicht)

Eigener Code, Dokumentation und Assets: GPL-3.0-only. SDK-Quellen, Datensätze und Abhängigkeiten
behalten ihre jeweiligen Fremdlizenzen. Keine installierbaren
signierten Apps, keine Sicherheitsprüfung und keine allgemeine Bitwarden-/Vaultwarden-
Kompatibilitätsgarantie.
App-Metadaten verwenden `0.1.0` / Build `1`; `prealpha` bezeichnet den Source-Status.

### Umbau und behobene Defekte

- Zwei lokale Packages; Domain, Data, Storage, Networking, SDK-/Plattformadapter und vier
  Observation-Presentation-Targets. Keine rohe SDK-/Token-Abhängigkeit der Feature-UI.
- Verlustärmeres Bearbeiten vorhandener Cipher-Typen, read-only/fail-closed bei unvollständigen
  Editoren, Permissions/Re-Prompt und stale Drafts; vorhandene Metadaten bleiben erhalten.
- Unbekannte Cipher-Felder sperren verlustbehaftete Editor-/Attachment-/Passkey-Schreibzugriffe;
  bekannte Inhalte bleiben lesbar und die Schreibsperre übersteht verschlüsselte Cache-Projektion.
  Keine neue Interpretation oder Roundtrip-Unterstützung beliebiger Zukunftsfelder.
- Account-/Server-/Lineage-/Generation-gebundene Token-/Unlock-Persistenz; temporäre
  Netzwerkfehler sind nicht pauschal Logout. Durable Lock-/Logout-Cleanup vor Restore.
- Separate App-/Extension-Refresh-Anfrage-Lease und durabler Unsicherheitsmarker vor HTTP;
  keine blinde Wiederholung nach verlorener Rotation. Scope-/Epoch-Rechecks und typisierte
  erneute-Anmeldung-Hinweise bis eigener UI/Passkey-Transport, kein automatischer Logout bei 5xx.
- Bestätigter atomarer Fresh-Login-Write ohne postcommit Cancellation-/Epoch-Read-Fehlklassifikation;
  unabhängige Enrollment-Cleanup-Versuche und korrigierte No-Grant-/Private-Write-Recovery.
- SDK-Präsenz-/Kardinalitätsprüfungen verhindern blanke verlustbehaftete Writes/AutoFill nach
  stillen Feldfehlern. Lokale KDF-Kostengrenzen verweigern extreme Werte ohne Clamping.
- Feste synthetische historische/current Cache-Goldens und UI-Recovery-Regressionen.
- Repository-eigene FIFO-Mutationen/Projektion; bestätigte Writes und Cleanup-/Refreshfehler
  bleiben unterscheidbar, kein blinder Create-Retry nach UI-Cancellation.
- URI-Match-Modi/PSL und konkrete Credential-IDs fail-closed; AutoFill-Picker ohne Seeds/Secrets,
  frische Secret-Auflösung und terminaler TOTP-Periodencheck.
- Passkey-Write-Journal, explizite Unsicherheits-/Repair-Zustände, exakte Callback-Auswahl,
  inkrementelle Identitäten und gemeinsame App-/Extension-OS-Mutationsordnung.
- Geschützte Temp-Dateien, same-origin Attachments, gehärtete Namen/Redirects, explizites Cleanup.
- Attachment-/File-Send-Dateitransport und gemeinsame geschützte 64-KiB-Multipart-Assembly statt
  zusätzlicher Voll-RAM-Transport-Bodies; SDK-interne Whole-file-Allokation bleibt eine Grenze.
- Send-FIFO, Scoped-Access nur während SDK-Dateiverschlüsselung und getrennte Cleanup-/Upload-
  Fehler; bestätigte Drafts schließen auch bei UI-Cancellation. Ungültige Zugriffslimits/Datums-
  Werte werden ohne Konvertierungs-Trap oder stilles Clamping verweigert.
- Send-Draft-Request-IDs verhindern späte Picker-/Edit-Ergebnisse nach Save/Dismiss/neuer Intention;
  vorhandene Sync-Consumer-Tests warten auf echten Join statt unzuverlässigem Task-Start/Yield.
- Strict Concurrency/Warnungen als Fehler für eigenen Code, gepinnter Formatter, Source-Checks,
  CI-Vorbereitung und isoliertes SDK-Buildscript ohne Upstream-Checkout-Änderungen.
- Gemeinsamer Integrationsablauf: hostlose macOS-/iOS-Simulator-Bundles führen echte App-/
  Extension-Composition, Handoff-/Lock-/Cleanup-Lifecycle, Hosting und den Apple-Credential-
  Provider-Controller mit isolierter Infrastruktur aus; CI ruft ihn nach dem SDK-Build auf.
- Credential Provider: vollständiges UIKit-Containment (`willMove`/`didMove`) beim Ersetzen.
- Guard-Skripte benötigen kein `rg` mehr; ohne es wäre der Secret-Leak-Negativcheck still
  wirkungslos gewesen. Testbundle-IDs folgen der Contributor-Konfiguration.
- Repository-Struktur: Audit und Umsetzungsplan liegen unter `Docs/Planning/`, Lizenztexte unter
  `Docs/ThirdParty/`, das Verifikationsprotokoll heißt `Docs/Verification.md`; die von macOS und
  iOS gemeinsam genutzten App-Ressourcen liegen unter `App/Resources`, Extension-Plists folgen dem
  Namensschema der App. Das generierte Xcode-Projekt heißt plattformneutral `Vaultwarden.xcodeproj`
  (Target- und Schemenamen unverändert).
- Opt-in Live-Vertragstest für bestehende Serverflows mit Einzelfeld-Konfigurationsverweigerung,
  RFC-6238-Referenz und Cleanup nur eigener IDs – bisher **nicht** gegen einen Server ausgeführt.

### Bewusst nicht neu implementiert / bekannte Grenzen

Keine zusätzlichen Server-Kompatibilitätsfeatures, Multi-Account, Haupt-App-Offline-Vault,
Background Sync, zusätzliche Login-2FA oder neuen unvollständigen Cipher-Editoren.
Bestehende Re-Prompt-Items bleiben ohne Master-Passwort-Nachweis für Secret-Aktionen gesperrt.

Der Auth-Handoff bleibt eine einmalige widerrufbare Capability-Übergabe statt reiner Beobachtung
([ADR 028](Docs/ADR/028-session-handoff-and-integrated-acceptance.md)). Echte End-to-End-Auth-/
Refresh-Abnahme mit Prozessen/Servern, signierte UI-/Extension-Context-Abnahme,
dateigrößenunabhängiger Gesamt-Heap, ein ausgeführter Server-Contract, echte Geräte-/Crash-
Matrix und anderer Fresh-Clone-Rechner/Remote-CI-Nachweis sind offen. Die Source-only-Lizenzwahl
wurde inzwischen unter F-17 geklärt; konkrete Binärdistributionen benötigen eine separate Prüfung.
Isolierter lokaler SDK-Neubau und echter FFI-Smoke bestanden. Details:
[FeatureStatus](Docs/FeatureStatus.md), [Arbeitscheckliste](Docs/RemainingReleaseWork.md),
[ausgeführte Verifikation](Docs/Verification.md),
[verbindlicher Plan](Docs/Planning/RESTRUCTURE_IMPLEMENTATION_PLAN.md).
Der aktuelle kompakte [Reststand](Docs/RemainingReleaseWork.md) trennt implementierten Code
von noch nicht ausgeführten Abnahmen; keine pauschale Freigabe aller Hardening-Phasen.
