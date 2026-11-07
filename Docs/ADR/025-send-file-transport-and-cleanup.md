# ADR 025 – File-Send-Transport, FIFO und bestätigtes Cleanup

Datum: 2026-09-28. Status: umgesetzt, lokale Pakettests bestanden; Plattform-Builds in Verifikation.

## Befund

DefaultSendRepository lud importierte Klartextdateien vollständig als Data, übergab sie über
Domain/FFI und baute für Direct-Uploads eine weitere Whole-file-Multipart-Data. Azure verwendete
ebenfalls einen RAM-Body. Der eigene Send-Pfad nutzte den bestehenden geschützten Temp-Owner
nicht. Actor-Reentrancy ließ Load/Create/Delete ungeordnet ineinanderlaufen. Ein nach bestätigtem
Create geworfener Fehler konnte bei UI-Cancellation die Draft-Bestätigung überspringen.

Zusätzlich konnte UInt32-Konvertierung eines manipulierten großen Draft-Zugriffslimits trapen;
nicht positive Werte wurden still auf eins geklemmt. Der Serverfehlertext zeigte `(action)`
wörtlich statt der tatsächlichen Aktion.

## Entscheidung und Ablauf

1. Der repository-eigene Mutation-Task erwirbt denselben FIFO-Slot wie Load/Delete. UI-Cancellation
   beendet ihn nicht; Runtime-Widerruf sperrt weitere Arbeit und späte Ergebnisse.
2. SensitiveFileWorking injiziert den gemeinsamen SensitiveTemporaryFileStore oder Fehlerfixtures.
   Der Actor reserviert 0700-Workdir/0600-Datei; iOS-Dateien bekommen Complete Protection vor
   Inhalt und erneut nach SDK-Writes. Composition nutzt denselben Owner wie Lock/Logout.
3. ImportedFile hält Scoped Access nur während der vorhandenen synchronen SDK-encryptFile-API.
   Domain transportiert Metadaten plus Datei-URL/UInt64-Länge statt File-Data. Original bleibt
   unverändert; offensichtliche Symlinks/Nicht-Dateien/gleiche Input-/Output-Pfade werden abgewiesen.
4. Der kleine `/sends/file/v2`-JSON-Request registriert wie bisher. Nach Bestätigung wird das
   Domain-Record projiziert; fehlgeschlagene Ticket-Decodierung ist ebenfalls postcommit.
5. Direct nutzt den gemeinsamen 64-KiB-MultipartFileBody und HTTPClient.upload(fromFile:),
   accountgebundenen Bearer, Reject-Redirect und UInt64-Content-Length. Azure nutzt dieselbe
   File-Upload-API mit Signed URL/Blob-Headern, ausdrücklich ohne Account-Bearer; unsicheres Schema,
   URL-Credentials/Fragment werden verweigert. Kein neuer Server-Endpunkt oder Upload-Modus.
6. Workdir-Cleanup wird nach Erfolg/Fehler versucht. Vor-Commit-Cleanupfehler, bestätigter Upload
   mit Cleanupfehler und fehlgeschlagener Upload plus Cleanupfehler bleiben verschiedene Fehler.
   UI schließt bestätigte Drafts vor Cancellation-Prüfung; Cleanup-Reparatur empfiehlt Lock,
   keine zweite Send-Erstellung. Kein automatischer HTTP-Retry oder Server-Rollback.

Ein abschließendes UI-Nachreview ergänzte Draft-Request-IDs: späte Picker-/Edit-Reads können
nach Save/Dismiss/neuer Intention keinen anderen Draft ersetzen oder einen bestätigten wieder
öffnen. Save invalidiert outstanding Reads vor Suspension; alle Rückläufer prüfen ID und Busy-State.

Zugriffslimits werden positiv/exakt UInt32-validiert; die obere UInt32-Grenze bleibt erhalten.
Deaktiviertes Limit ignoriert seinen alten Wert. Nicht endliche Datumswerte und Content-Typwechsel
bei vorhandenen Records werden vor SDK-Mutation/Serialisierung verweigert. UI validiert dieselben
numerischen/Datumsgrenzen; der Adapter bleibt unabhängig davon defensiv.

## Nachweis und Grenzen

27 neue Methoden: 13 Repository-/real-file-/FIFO-/Fehlerfixtures, sieben SDK-Adapter-Fixtures,
sieben Presentation-Methoden. Gesamter Paketlauf: **809 Swift-Testing/102 Suites + 2 XCTest = 811
bestanden**. Vorhandene Assertions bleiben erhalten, File-Port/body-nil/Content-Length/Cleanup-
Nachweise ergänzen sie. Erste Compile-Prüfung fand eine Fixture-Mutation eines immutable SDK-
Send-Werts; Fixture rekonstruiert jetzt den Wert, keine Upstream-Änderung.

Ein weiterer Gesamtlauf wurde in einem alten Sync-Consumer-Test unterbrochen: die Fixture hatte
keinen Nachweis, dass der zweite Consumer vor Abschluss am selben Job hängt. Die beiden
bestehenden Sync-Tests warten jetzt auf den tatsächlichen internen Consumer-Zähler statt bloßem
Task-Start/Yield. Unerwartete zusätzliche Fixture-Requests werden alle abgeschlossen, damit die
unveränderte Count==1-Assertion einen Fehler meldet statt zu hängen. Der finale volle Lauf bestand.
Frühere non-PTY-Beobachtungen werden damit nicht pauschal als abschließend diagnostiziert erklärt.

16-MiB-Sparsefile-Multipart läuft ohne Whole-body-Lesen durch die HTTP-Fixture; 6-GiB-Sparsefile
prüft UInt64-Metadaten ohne Whole-file-Data. Das sind keine tatsächlichen SDK-Heap-Messungen:
die Crypto-Fixtures schreiben synthetischen Ciphertext, kein Crypto-Roundtrip-Beweis. Der
unveränderte SDK-Dateipfad liest intern weiterhin ganze Dateien (`std::fs::read`). Er öffnet
Pfade selbst; eigener Typcheck ist kein atomarer FD-Handoff gegen beliebige Source-Ersetzungen.

Echter Server/SDK-Crypto-Vektor, Disk-full/Crash/Power-loss, signierte Scoped-Access-/Protection-
und Multi-Scene-/OS-Lifecycle-Matrix bleiben offen. F-701/Quality Gate 7 nicht allein aufgrund
file-basierter eigener Transporte schließen. Keine zusätzliche File-Send-Download-/Exportfunktion
eingeführt: im Scope bleibt das bisherige Erstellen/Upload/Bearbeiten/Share-Link-Verhalten.
