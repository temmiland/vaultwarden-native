# Auth-Transporte und gemeinsame KDF-Grenze

Status: Teilmigration A-202/A-203/A-206/S-303/U-504, 2026-09-27. Betroffene Tests und unsigned
App-/Extension-Builds bestehen. Credential-Orchestrierung und reale Release-Gates bleiben offen.

## Entscheidung

Prelogin sowie Passwort-/TOTP-HTTP inklusive OAuth-Form-Builder, Wire-DTOs und Device-Metadaten
liegen jetzt in Data, nicht im AuthFeature-Presentation-Paket. HTTP bleibt injiziert; Endpoints,
Wire-Namen, `connector`, Refresh-Delegation und bestehende 2FA-Provider-Decodierung bleiben gleich.
Unsichere Credential-Server werden direkt am Transport vor HTTP abgewiesen. Cancellation nach
einem nicht kooperativen Response liefert kein spätes Ergebnis. Data-Token-/Code-/Device-
Beschreibungen sind redigiert; rohe Serverdiagnosen werden weiterhin nicht als UI-Fehler verwendet.

Domain definiert `PreloginService`, SDK-freie `KeyDerivationParameters` und stabile `AuthFlowError`.
`SDKKeyDerivationMapper` besitzt die gemeinsame Konvertierung für App- und Extension-Pfade.
Nur fehlende Werte verwenden vorhandene defaults: PBKDF2 600.000 Iterationen; Argon2 3 Iterationen,
64 Speicher-Einheiten und Parallelität 4. Negative, nullgroße, UInt32-overflow und unbekannte
Algorithmuswerte scheitern mit einem Fehler, nicht mit Trap oder PBKDF2-Fallback. Auch direkt
konstruierte Domain-Werte werden vor SDK-Aufruf geprüft.

Data mappt StoredAuthAccount auf diese Parameter. Unlock validiert sie vor Repository-Transition,
Client-/Crypto-Erstellung und Biometrie-Evaluation. Ungültige Accountdaten leeren die Eingaben,
verbrauchen keinen PIN-Versuch und löschen weder PIN- noch Biometrie-Enrollment. Die bisherige
falsche Behandlung eines Crypto-Metadatenfehlers als falsches Passwort/PIN wird vermieden.

Token-Metadaten müssen mit dem Prelogin-KDF übereinstimmen, bevor Crypto/Persistenz beginnt.
Fehlende Felder übernehmen genau die tatsächlich verwendeten Parameter, nicht neue Algorithmus-
Defaults. Persistierte Wire-Feldnamen/Schema bleiben gleich; neue erfolgreiche Logins speichern
explizite KDF-Werte. Legacy-Records werden beim Lesen nicht umgeschrieben. AutoFill-Freigabe
verwendet dieselbe geprüfte Abbildung; Argon2 mit fehlenden Iterationen bekommt nicht mehr
versehentlich den PBKDF2-Iterationsdefault.

## Verifikation und Grenzen

15 vorhandene Transport-Testmethoden sind in AppModules portiert, nicht als neue Tests gezählt.
20 neue Methoden prüfen Defaults/Grenzwerte, unbekannte KDFs, explizit ungültige Domain-Werte,
Token-/Stored-/Shared-Mapping, redigierte Beschreibungen und Transport-Denial/Cancellation.
Ungültiges Prelogin verhindert Token-Requests; ungültige Token-Metadaten verhindern Crypto/Commit.
Returning Unlock erhält bei KDF-Fehlern PIN-Budget/Enrollment.

Ein bestehender Cache-Test verglich nach JSON-Decoding/Re-Encoding zufällige Byte-Reihenfolge.
Er vergleicht nun das vollständige JSON-Objekt inklusive aller verschlüsselten Werte, unabhängig
von Key-Order; ein zusätzlicher Reihenfolge-Fall sichert dies ab. Produktiver Cache-Code ist unverändert.
Siehe [ausgeführte Prüfungen](../Verification.md).

Stand bei Einführung dieser Entscheidung: AuthFeature besaß weiter Keychain-Komposition, den
SDK-Token-Provider, Client-Erstellung, Credential-Sequencing, Commit und pending SDK-Contexts.
IdentityTokenService liefert Data-Wirewerte an diesen Übergangsflow; sie sind keine Domain-only
Presentation-/Repository-Ergebnisse. AuthPresentation bleibt Domain/SharedUI-only und übernimmt
keine Data-/SDK-Imports. Die drei Pakete bleiben bestehen, bis die übrigen Consumer migriert sind.

Nachtrag 2026-09-28: Credential-Speicher und Token-Autorität sind nach Data migriert;
siehe [Folgeentscheidung](010-auth-credential-authority.md). Der Nachreview fand außerdem eine
Lücke im echten Shared-Write: Sein Metadatenvergleich benutzte noch rohe PBKDF2-/Nil-Defaults
und konnte die oben korrekt normalisierten Legacy-Argon2-Werte ablehnen. Auch diese Grenze
vergleicht nun die kanonische Abbildung. Neue produktive Speicherpfad-Tests belegen Grant-/Token-
Publikation ohne Private-Record-Rewrite sowie weiterhin Denial bei fremden/geänderten Werten.
Die vorherigen Mapper-Tests allein waren noch kein Nachweis des erfolgreichen Writes.

Weiterer Nachtrag: [Login-/TOTP-Command-Capabilities](011-auth-command-capabilities.md) besitzen
jetzt auch frisches Credential-Sequencing und private Retry-/Pending-Ressourcen in Data.
Drei Auth-Models nutzen nur Domain-Ports; Returning-Unlock und der Root-Handoff bleiben transitional.

UInt32-Konversion prüft Zahlenrepräsentation/positive Werte, nicht vollständige SDK-Kostenlimits
oder den Erfolg realer Hash-/Unlock-Operationen. Keine neuen KDF-/2FA-/Vaultwarden-Funktionen,
keine Zeroization-/Rollback-Zusage, kein SDK-FFI-/Server-/Device-Smoke in diesem Block. Vollständige
Command-/Runtime-/Commit-Ownership, durables Recovery und die signierte Prozessmatrix bleiben offen.
