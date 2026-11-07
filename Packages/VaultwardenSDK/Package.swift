// swift-tools-version: 5.10
import PackageDescription

// Vendors a locally-built BitwardenFFI.xcframework (see Scripts/build-sdk.sh) that includes a macOS
// slice, unlike the upstream `bitwarden/sdk-swift` package which is iOS-only. Mirrors that package's
// structure so future upstream diffs are easy to compare against.
let package = Package(
    name: "VaultwardenSDK",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "BitwardenSdk", targets: ["BitwardenSdk"]),
    ],
    targets: [
        .target(
            name: "BitwardenSdk",
            dependencies: ["BitwardenFFI", "BitwardenSdkSupport"],
            swiftSettings: [.unsafeFlags(["-suppress-warnings"])]
        ),
        .target(name: "BitwardenSdkSupport"),
        .binaryTarget(
            name: "BitwardenFFI",
            path: "Frameworks/BitwardenFFI.xcframework"
        ),
        .testTarget(
            name: "BitwardenSdkTests",
            dependencies: ["BitwardenSdk"]
        ),
    ]
)
