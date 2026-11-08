# Isolierter SDK-Neubau – lokaler Nachweis

## SDK-Aktualisierung — 2026-11-08

Auf Owner-Auftrag wurde das SDK auf Upstream-Pin
`a13b4c4e1fa3685280241f417920fd19d7ef24a6` aktualisiert. Der isolierte Neubau mit Rust
1.99.0 und UniFFI 0.32.0 erzeugte alle fünf Apple-Release-Architekturen. Der zusätzliche
verbindliche Lockfile-Patch aktualisiert die mit diesem Upstream kompatiblen Dependencies;
`cargo build` und Bindgen verwenden `--locked`.

- Build-Patch SHA-256: `b824cd9c8fba29af01b0f1782f5314721cf10532d180a66303b9aa484a91c70c`
- Dependency-Patch SHA-256: `44e11046b48fb4b31ebb9a5ea01368fc1dee42a987162de08fda19e78f343aaa`
- Gepatchtes Cargo.lock SHA-256: `4d87866952641365ab38c937087c1b1e2f42d343a5c45b48353b10acc764ae38`
- Framework-Inhaltsinventar: [SDKLocalArtifactInventory.json](SDKLocalArtifactInventory.json)
- Source-/Dependency-/Auditnachweise: [ThirdParty](ThirdParty/)

Pin, Lockfile, alle generierten Swift-Bindings und Framework-Architekturen wurden geprüft.
Der echte SDK-Client-Smoke sowie 858 AppModules-Tests in 101 Suites bestehen. Der neue
SDK entschlüsselt Passkey-Private-Keys bereits im CipherView; der Adapter behält diese im
SDK-Typ, prüft vollständige Entschlüsselung und exportiert nur ausgewählte Metadaten.
Ein echter SDK-Verschlüsselungs-/Entschlüsselungsroundtrip prüft den Erhalt von Passkeys beim Editieren.
Die native Integration besteht mit 18 macOS- und 19 iOS-Simulatortests; Format-, Architektur-,
Secret-/Material-, Simulator-Preflight- und Konfigurationsprüfungen bestehen ebenfalls.
Die bisherigen Bindings und das Framework bleiben im ignorierten Upgrade-Buildroot als Rollback erhalten.

Das Audit meldet weiterhin RUSTSEC-2026-0387 (`crypto-bigint` 0.5.5) und RUSTSEC-2023-0071
(`rsa` 0.10.0-rc.19), dazu acht Unmaintained-Warnungen. Der Owner hat die Aktualisierung mit
verbleibenden Upstream-Befunden ausdrücklich beauftragt. Das ist keine Behauptung identischer
Ausnutzbarkeit in der offiziellen App, kein sauberes Audit und keine Signierungs-/Geräteabnahme.
Die folgenden Abschnitte dokumentieren historische Builds vor dieser Aktualisierung.

## Historischer frischer Source-only-Lauf — 2026-11-06

In einer neu erstellten Source-only-Kopie des aktuellen Arbeitsstands wurde
`bash Scripts/build-sdk.sh --install` vollständig ausgeführt. Die Kopie enthielt weder ein
vorhandenes SDK-Framework noch einen Upstream-Checkout oder lokale Buildprodukte; das Skript holte
den fest gepinnten Upstream neu und installierte das erzeugte Framework ausschließlich im ignorierten
Scratch-Verzeichnis dieser Kopie. Ergebnis: **alle fünf Release-Slices erfolgreich gebaut**.

- Upstream Source-Pin: `fbd21679c1c3690cba424ad3dbb0ba662eb9863e`
- Build-Patch SHA-256: `95f74e5f6d544be11f8b3542bbf90dd7ad4fc9ae00ad2ca5f3389041622748df`
- Cargo.lock SHA-256: `1a8918fba61d5823bb9be7a4b15c30d2184a70fcbb1d9dd3416eba945bb742fd`
- Toolchain: macOS arm64, Xcode 27.2 (27B52), Swift 6.4.2; SDK-Rust-Toolchain laut Pin 1.96.0
- isolierter Build-Root: lokales ignoriertes Scratch-Verzeichnis (nicht Teil des Source-Releases)

Der Build verifizierte den Quell-Pin, das unveränderte Lockfile, beide generierten Swift-Source-Bäume
und das Framework-Inventar. Nach Installation in der Kopie bestanden der SDK-Client-Smoke
(`clientInitializesAndRespondsOnMacOS()`), beide Pakettests und der vollständige native
macOS-/iOS-Simulator-Integrationsrunner. Zusätzlich bauten App und AutoFill-Extension auf beiden
Plattformen in Debug und Release unsigned. Source-/Architektur-/Material-Guards und ihre negativen
Fixtures bestanden. Der Live-Serververtrag war nicht aktiviert.

Das ist ein lokaler Neubau aus einem frischen Source-Overlay auf derselben Maschine. Es ist keine
byteidentische Reproduzierbarkeit, unabhängige Maschine, Remote-CI, Signierungs- oder
Provenance-Attestation und keine Lizenzfreigabe. Der vollständige Stand dieses Laufs ist in
`Docs/RemainingReleaseWork.md`, F-19, protokolliert.

## Älterer isolierter Nachweis — 2026-09-28

macOS arm64, Xcode 27, Rust 1.96.0. Kein installierter SDK überschrieben;
keine Änderungen an offiziellen Checkouts oder committed generierten Bindings.

## Tatsächlich ausgeführt

`bash Scripts/build-sdk.sh --build` erzeugte im eigenen ignorierten Scratch-Clone alle fünf
Release-Slices: aarch64-/x86_64-macOS, aarch64-iOS-Simulator und aarch64-/x86_64-iOS. Source-Pin:
`fbd21679c1c3690cba424ad3dbb0ba662eb9863e`; bestehender Build-Patch SHA-256:
`95f74e5f6d544be11f8b3542bbf90dd7ad4fc9ae00ad2ca5f3389041622748df`.

Der erste Build erzeugte erfolgreich Libraries/Bindings/XCFramework, scheiterte aber im eigenen
Vergleichsschritt: Upstreams `Sources/BitwardenSdk/.gitignore` fehlt im vendorten Source-Ordner.
Der Vergleich wurde auf generierten Inhalt begrenzt (`diff -qr -x .gitignore`); alle anderen
Dateien bleiben verglichen. Das ist kein unterdrückter Swift-/Rust-Buildfehler.

Danach tatsächlich ausgeführt, ohne erneutes Kompilieren der bereits gebauten Rust-Slices:

```sh
bash Scripts/build-sdk.sh --verify-build .build/sdk-isolated/build.7GBokw
bash Scripts/test-rebuilt-sdk.sh .build/sdk-isolated/build.7GBokw
```

Source-Pin, Cargo.lock gegen den Pin und beide generierten Source-Ordner: **bestanden**.
Der Smoke kopiert die vorhandenen Swift-Sources/Tests unverändert in ein eigenes Scratch-Paket
und linkt ausschließlich dessen FFI gegen den Neubau. **Ein echter Rust/Swift-FFI-Test bestanden**,
kein bloßer Import-/Build-Test. Kein echter Server oder Credential/Crypto-Vektornachweis.

## Inventare und Grenzen

Neubau: 76 reguläre Dateien; kanonischer Inhalts-SHA-256:
`f46cc94a59b945cd91e257f8b028cbce78b6142c690520e86e97795a64577157`.
Die vollständige JSON-Dateiliste und `cargo metadata --locked` liegen ignoriert im Build-Root.
Das separat eingecheckte [historische lokale Inventar](SDKLocalArtifactInventory.json) beschreibt
weiterhin die vorher installierten Bytes, nicht den Neubau. Unterschiedliche Hashes wurden nicht
als byteidentische Reproduktion oder Supply-Chain-Attestation umetikettiert.

Der Build nutzte vorhandene lokale Git-Objekte read-only und installierte Toolchains/Cargo-Caches.
Damit ist der isolierte Neubau bewiesen, nicht ein vollständig frischer Contributor-Rechner.
Remote-CI ist vorbereitet, nicht ausgeführt. Transitive Cargo-Metadaten sind keine abschließende
Lizenzprüfung. Keine Freigabe zum Verteilen eines kombinierten App-/SDK-Binaries.

Die Scratch-Namen sind Ergebnisprovenance dieses Laufs. Weitere Builds erzeugen eigene Namen;
`--verify-build`/`test-rebuilt-sdk.sh` erhalten explizit den jeweiligen neuen Build-Root.
