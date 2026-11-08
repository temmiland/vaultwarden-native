# Third-party notices

The owner selected GPL-3.0-only for project-owned source, documentation and assets on 2026-11-07.
This project does not relicense third-party source, binary SDKs, datasets or dependencies. The root
LICENSE applies to project-owned files; third-party materials retain their applicable upstream terms.
This project is independent of Bitwarden/Vaultwarden and claims no rights to their trademarks.

## Bitwarden SDK / UniFFI

- Upstream: https://github.com/bitwarden/sdk-internal
- Pinned source revision: `a13b4c4e1fa3685280241f417920fd19d7ef24a6`.
- Generated Swift bindings/support: `Packages/VaultwardenSDK/Sources` (do not hand-edit).
- Locally built, gitignored binary: `Packages/VaultwardenSDK/Frameworks/BitwardenFFI.xcframework`.
- Local build patch: `Scripts/patches/0001-add-macos-target-to-xcframework-build.patch`, SHA-256
  `b824cd9c8fba29af01b0f1782f5314721cf10532d180a66303b9aa484a91c70c`.
- Applied dependency-lock update: `Scripts/patches/0003-update-sdk-dependencies.patch`, SHA-256
  `44e11046b48fb4b31ebb9a5ea01368fc1dee42a987162de08fda19e78f343aaa`.
  Resulting Cargo.lock SHA-256: `4d87866952641365ab38c937087c1b1e2f42d343a5c45b48353b10acc764ae38`.
  The earlier `0002-sdk-dependency-mitigation-experimental.patch` remains as historical evidence;
  it is not applied to the current SDK. The build retains upstream's non-commercial dependency guard.
- The pinned upstream license notice identifies GPL v3 OR Bitwarden SDK License v2 as the
  default, with exceptions for directories named `bitwarden_license` and per-file notices.
  The pinned UniFFI Cargo manifest declares `GPL-3.0-only OR LicenseRef-Bitwarden-SDK`.
- Preserved texts: [upstream notice](Docs/ThirdParty/Bitwarden-LICENSE.txt),
  [GPL v3](Docs/ThirdParty/Bitwarden-LICENSE_GPL.txt),
  [SDK License v2](Docs/ThirdParty/Bitwarden-LICENSE_SDK.txt).

For SDK source portions offered by the pinned upstream under its default dual-license router, this
project selects the upstream GPLv3 option for the source-only publication. This election uses a
license option granted by Bitwarden; it does not change Bitwarden's ownership or relicense its
software. The upstream notices and full license texts below remain included. Files with a specific
license header or an upstream exception are governed by that specific notice and are outside this
election. The source and dependency inventories record the material reviewed and upstream-declared
licenses; they do not make all third-party materials GPL. The bundled Public Suffix List remains
MPL-2.0. A later binary release still requires artifact-specific dependency, provenance and notice
review; this source-only election does not approve a combined binary release.

The pinned source root offers GPLv3 or the Bitwarden SDK License for source files without a more
specific notice; the UniFFI crate also declares `GPL-3.0-only OR LicenseRef-Bitwarden-SDK`, and its
Swift source subtree carries a GPL text. This project selects that upstream GPLv3 alternative for
the SDK source portions in the source-only publication. This is an election under the terms offered
by the upstream owner, not a project relicensing of Bitwarden code. See the completed source-only
review in `Docs/RemainingReleaseWork.md` (F-17). A binary distribution remains subject to a separate
artifact-specific review.

## Mozilla Public Suffix List

The bundled offline dataset is MPL 2.0; its original file header is retained. Source, revision,
SHA-256 and update instructions are in [the dataset notice](Docs/ThirdParty/PublicSuffixList.md).
The upstream MPL text is linked in that notice and the dataset header. Preserve both when
distributing the dataset; it retains MPL 2.0 and is not relicensed by the root GPL license.

## Apple SDKs and build tools

SwiftUI, Foundation, AuthenticationServices, Security, LocalAuthentication, AppKit/UIKit and
Quick Look are Apple platform dependencies, not bundled project-owned GPL implementations.
XcodeGen, SwiftFormat and Rust/Cargo are build tools, not automatically application dependencies.
Their pinned versions/notices belong in the release build inventory. The full transitive Rust
license inventory and final artifact-specific notices remain a release gate.

## Source publication inventory

The byte inventory of the actual upstream/support/dataset/license/SDK-patch files is
[SourceMaterialInventory.json](Docs/ThirdParty/SourceMaterialInventory.json). Validate it with
`swift Scripts/check-source-materials.swift`. This also refuses private signing settings,
the private handoff, SDK binaries, build directories and signing files in tracked source.
It does not grant a right to distribute or inspect arbitrary personal data in every file.

[SDKDependencyInventory.json](Docs/ThirdParty/SDKDependencyInventory.json) records the 738
packages from `cargo metadata --locked` for the pinned SDK, membership in the iOS/macOS normal/build
dependency trees, and their feature unions. It includes workspace packages not linked into the app; a graph entry is not
proof of runtime reachability. License strings and license-file names are upstream declarations,
not a license choice for this application. Five workspace packages declare a license file
instead of a license expression (`bitwarden-access-connector`, `bitwarden-commercial-vault`,
`bitwarden-pam`, `bitwarden-pam-sealed`, `bitwarden-sm`);
none appears in the inspected iOS normal/build tree. Directory/per-file exceptions still need
the owner's review, including the generated bindings/support and actual distribution scope.

[SDKAdvisoryInventory.json](Docs/ThirdParty/SDKAdvisoryInventory.json) records the pinned
lockfile's RustSec hits, patched version requirements and target-graph presence. The current
upstream comparison still has advisory hits, so a pin upgrade alone is not a security fix.
See F-16/F-17 in the [single work checklist](Docs/RemainingReleaseWork.md).

XcodeGen is now pinned to 2.46.0 with the official release archive SHA-256
`4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806` in `Scripts/xcodegen.sh`;
SwiftFormat remains pinned separately. These are build tools, not bundled application code.
