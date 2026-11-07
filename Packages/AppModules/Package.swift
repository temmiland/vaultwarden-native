// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AppModules",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "SecurityStorage", targets: ["SecurityStorage"]),
        .library(name: "AutoFillContract", targets: ["AutoFillContract"]),
        .library(name: "BitwardenSDKAdapter", targets: ["BitwardenSDKAdapter"]),
        .library(name: "Data", targets: ["Data"]),
        .library(name: "PlatformServices", targets: ["PlatformServices"]),
        .library(name: "SharedUI", targets: ["SharedUI"]),
        .library(name: "AuthPresentation", targets: ["AuthPresentation"]),
        .library(name: "VaultPresentation", targets: ["VaultPresentation"]),
        .library(name: "SendPresentation", targets: ["SendPresentation"]),
        .library(name: "SettingsPresentation", targets: ["SettingsPresentation"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
        .library(name: "AutoFillData", targets: ["AutoFillData"]),
        .library(name: "AutoFillFeature", targets: ["AutoFillFeature"]),
    ],
    dependencies: [
        .package(path: "../VaultwardenSDK"),
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Networking"),
        .target(name: "SecurityStorage"),
        .target(name: "AutoFillContract"),
        .target(
            name: "BitwardenSDKAdapter",
            dependencies: [
                "Domain",
                "Networking",
                "AutoFillContract",
                .product(name: "BitwardenSdk", package: "VaultwardenSDK"),
            ]
        ),
        .target(
            name: "Data",
            dependencies: [
                "Domain",
                "Networking",
                "SecurityStorage",
                "AutoFillContract",
                "BitwardenSDKAdapter",
                "AutoFillData",
            ]
        ),
        .target(name: "PlatformServices", dependencies: ["Domain"]),
        .target(name: "SharedUI", dependencies: ["Domain"]),
        .target(name: "AuthPresentation", dependencies: ["Domain", "SharedUI"]),
        .target(name: "VaultPresentation", dependencies: ["Domain", "SharedUI"]),
        .target(name: "SendPresentation", dependencies: ["Domain", "SharedUI"]),
        .target(name: "SettingsPresentation", dependencies: ["Domain", "SharedUI"]),
        .target(
            name: "AppFeature",
            dependencies: ["Domain", "AuthPresentation", "VaultPresentation", "SendPresentation", "SettingsPresentation"]
        ),
        .target(
            name: "AutoFillData",
            dependencies: ["Domain", "AutoFillContract", "Networking", "SecurityStorage", "BitwardenSDKAdapter"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "AutoFillFeature",
            dependencies: ["Domain", "AutoFillContract", "SharedUI"]
        ),
        .testTarget(
            name: "AuthPresentationTests",
            dependencies: ["AuthPresentation", "Domain", "Data", "AutoFillContract", "BitwardenSDKAdapter",
                           "Networking", "SecurityStorage", .product(name: "BitwardenSdk", package: "VaultwardenSDK")]
        ),
        .testTarget(
            name: "AppModulesArchitectureTests",
            dependencies: [
                .product(name: "BitwardenSdk", package: "VaultwardenSDK"),
                "Domain", "Networking", "SecurityStorage", "AutoFillContract", "BitwardenSDKAdapter",
                "Data", "PlatformServices", "SharedUI", "AuthPresentation", "VaultPresentation", "SendPresentation",
                "SettingsPresentation", "AppFeature", "AutoFillData", "AutoFillFeature",
            ],
            resources: [.process("Fixtures")]
        ),
    ]
)

// Project-owned targets only: upstream generated SDK targets retain their own warning policy.
// Passing global -warnings-as-errors conflicts with that SDK's -suppress-warnings setting.
for target in package.targets {
    target.swiftSettings = (target.swiftSettings ?? []) + [
        .unsafeFlags(["-strict-concurrency=complete", "-warnings-as-errors"]),
    ]
}
