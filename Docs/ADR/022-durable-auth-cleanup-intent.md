# ADR 022: Persistentes Auth-Cleanup vor Restore

Datum: 2026-09-28. Status: implementiert, lokale Fixture-Verifikation; kein Crash-/Gerätenachweis.

## Problem

Lock/Logout betreffen mehrere Keychain-Einträge. Eine fehlgeschlagene Entfernung darf beim
nächsten Start nicht als weiterhin nutzbare Session oder AutoFill-Freigabe wieder erscheinen.
Ein In-Memory-Recovery-State genügt über Store-/Repository-Neuerzeugung hinweg nicht.

## Entscheidung

Data speichert im gemeinsamen Keychain einen `auth.cleanup.v1`-Marker: Schema 1, Kind `lock`
oder `logout`, keine Credentials. Lesen, Schreiben, Widerruf und Replay verwenden dieselbe
bisherige synchrone Shared-Token-Transaktion. Logout kann nicht durch Lock herabgestuft werden.

- Lock übernimmt zunächst eine bereits bestätigte neuere Extension-Tokenrotation in die private
  Session. Erst danach wird der Marker geschrieben und die gemeinsame Capability widerrufen.
- Logout markiert zuerst, versucht Widerruf und jede private/shared Entfernung unabhängig und
  bewahrt den ersten Fehler. Der Geräte-Identifier bleibt bestehen.
- Nur vollständig erfolgreiches Cleanup entfernt den Marker. Ein Fehler beim Entfernen selbst
  bleibt sichtbar und lässt die Sperre bestehen.
- App-Restore, Refresh-Commit und neue Login-/Unlock-Publication verlangen keinen offenen Marker.
  AutoFill kann mit Marker keine alte Freigabe laden. Unlesbare/kaputte/zukünftige Marker werden
  nicht als Abwesenheit behandelt oder automatisch gelöscht.
- Flow-Restore wiederholt Cleanup vor Capture des Publication-Epoch; Repository-Restore prüft
  ebenfalls. Lesen und Replay liegen in EINER Transaktion: eine alte Logout-Beobachtung darf
  keine inzwischen veröffentlichte Nachfolgesession löschen.

Die No-op-Defaults der Lifecycle-/Transaction-Ports dienen alten Testfixtures. Produktive Stores
implementieren die Checks; sie sind kein zulässiger Livefallback.

## Verifikation und Grenzen

11 neue Testmethoden prüfen Fehler beim Lesen/Schreiben/Entfernen, Store-/Repository-Recreation,
Checkpoint-Replay, Idempotenz, Nachfolgesession, Lock-vor-Reconcile-Reihenfolge und fail-closed
App-/Extension-Zugriff. Die Keychains sind synthetische `.processOnly`-Fixtures; kein echter
Prozessabbruch, Security-Daemon-Ausfall, Power Loss oder signierter Parallelprozess wurde getestet.

Ein nicht schreibbarer Keychain kann keinen dauerhaften Marker garantieren. Cleanup wird dennoch
unabhängig versucht und der Fehler gemeldet. Alte Binaries verstehen den Marker nicht. Bereits
vor fehlgeschlagenem Lock-Reconcile verlorene rotierte Tokens werden nicht rekonstruiert. Dies
ist weder ein Refresh-Journal noch eine atomare Keychain/HTTP/Cache/OS/Temp-Transaktion. Die
vollständige operation-eigene Auth-Commit-/Cancellation-Semantik bleibt separat offen.
