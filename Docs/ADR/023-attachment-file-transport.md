# ADR 023: Dateibasierter Attachment-Transport, keine Streaming-Crypto-Zusage

Datum: 2026-09-28. Status: eigener Transport implementiert; F-701/F-703 bleiben teilweise.

## Entscheidung und Verhalten

SDKVaultSessionSource verwendet nach der bestehenden SDK-Dateiverschlüsselung nicht mehr
`Data(contentsOf:)` für den Multipart-Body. Networking.MultipartFileBody kopiert in 64-KiB-
Chunks in eine zusätzliche 0600-Datei im bereits registrierten Work-Verzeichnis. iOS setzt
Complete File Protection vor dem Schreiben. Nur reguläre Quellen, keine Symlinks/FIFOs; ein
exklusiv erzeugtes Ziel überschreibt keine vorhandene Datei. Boundary und Filename sind gehärtet,
Größen/Content-Length explizit UInt64. Jede Chunk-Grenze prüft Cancellation/Runtime; geänderte
Quelllänge verwirft die Ausgabe. Ein fehlgeschlagenes Entfernen der partiellen Body-Datei hat
einen typisierten Cleanupfehler, keinen verschluckten Best-Effort-Pfad.

Der Blob-Upload nutzt HTTPClient.upload(fromFile:), der Blob-Download HTTPClient.download(to:).
Metadata-/Refresh-Requests bleiben kleine JSON-Requests. Vor Credentials/Assembly wird die
bestehende same-origin Attachment-Policy geprüft; Redirects bleiben verboten. Token-Await und
Download dürfen keine veralteten Cipher-/Secret-Berechtigungen in Crypto weiterreichen.

Die URLSession-Download-Publikation kopiert in eine geschützte sibling-stage, prüft Cancellation
vor Austausch und verwendet beim Replace die Metadaten der neuen Datei (0600). Auf iOS gilt
Complete File Protection. Symlink-/Directory-Ziele werden abgewiesen; I/O-Fehler sind nicht
Abwesenheit. Fehlgeschlagenes Stage-Cleanup bleibt sichtbar. Die vorherige Zieldatei wird bei
vorzeitiger Cancellation nicht ersetzt. Caller/Repository bleiben für die registrierte Work-
Directory-Bereinigung auf Erfolg, Fehler, Lock und Preview-Ende verantwortlich.

## Ausgeführte Regressionen

14 neue Methoden: acht Multipart-, vier Filesystem-Installer- und zwei Source-Tests. Exact
Framing/Name/0600, 16-MiB-Sparsefile ohne Whole-file-Testread, Empty/Boundary/Symlink/FIFO,
Exklusivität, Truncation, Cancellation/Revocation, alte Destination/Stage-Cleanup, Blob-HTTP-Fehler
und Entzug der Secret-Policy nach Download. Bestehende Source-Tests behalten Body-/Token-/Origin-
Assertions und belegen zusätzlich den tatsächlich benutzten Upload-/Download-Port sowie leeren
HTTPRequest.body beim produktiven Upload. Der kleine HTTP-Testadapter liest Bytes zur Inspektion;
der Large-File-Test tut das ausdrücklich nicht.

Kompletter AppModules-Lauf: **782 Swift-Testing/102 Suites + 2 XCTest = 784 bestanden**;
macOS-/iOS-App und Extensions unsigned Debug UND Release tatsächlich bestanden. Keine echten
Servertransfers, OS-Lifecycle-/Disk-full-/Cleanup-failure-
Injektion am realen Volume oder Heap-Messung des Gesamtprozesses behaupten.

## Konkrete verbleibende SDK-Grenze

Der gepinnte SDK-Stand `fbd21679c1c3690cba424ad3dbb0ba662eb9863e` nutzt selbst in
`crates/bitwarden-vault/src/cipher/attachment_client/mod.rs:115,132` und
`crates/bitwarden-send/src/send_client.rs:86,123` `std::fs::read` für die ganze Datei.
Das eigene File-Send-Crypto-Port nimmt weiterhin Data/encryptBuffer; dessen Transport und
Crypto-Pfad sind noch umzubauen. Offizielle SDK-/Subrepos bleiben unverändert. Ein neuer
Crypto-Kern oder SDK-Fork wird nicht still eingeführt.

Damit ist der zusätzliche Voll-RAM-Multipart-/Download-Pfad bei Attachments entfernt, aber
**Peak Memory des Gesamtflows ist nicht dateigrößenunabhängig**. F-701-Done/Quality Gate 7 und
D-016 werden nicht abgeschlossen. Kein Größenlimit erfinden, kein Feature entfernen und keine
neue Server-Quota/Kompatibilitätsfunktion zur Umgehung hinzufügen. Für den verbleibenden Crypto-
Umbau ist eine separate Architektur-/Authority-Entscheidung erforderlich.
