// swift-tools-version:5.9

//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import class Foundation.ProcessInfo
import PackageDescription


#if swift(<6)
let swiftConcurrency: SwiftSetting = .enableExperimentalFeature("StrictConcurrency")
#else
let swiftConcurrency: SwiftSetting = .enableUpcomingFeature("StrictConcurrency")
#endif


let package = Package(
    name: "SpeziFirebase",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "SpeziFirebaseAccount", targets: ["SpeziFirebaseAccount"]),
        .library(name: "SpeziFirebaseConfiguration", targets: ["SpeziFirebaseConfiguration"]),
        .library(name: "SpeziFirestore", targets: ["SpeziFirestore"]),
        .library(name: "SpeziFirebaseStorage", targets: ["SpeziFirebaseStorage"]),
        .library(name: "SpeziFirebaseAccountStorage", targets: ["SpeziFirebaseAccountStorage"])
    ],
    dependencies: [
        .package(url: "https://github.com/StanfordSpezi/Spezi", from: "1.0.0"),
        .package(url: "https://github.com/StanfordSpezi/SpeziViews.git", from: "1.0.0"),
        .package(url: "https://github.com/StanfordSpezi/SpeziStorage", branch: "feature/sendable-modules"),
        .package(url: "https://github.com/StanfordSpezi/SpeziAccount", branch: "feature/account-service-singleton"),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.13.0")
    ] + swiftLintPackage(),
    targets: [
        .target(
            name: "SpeziFirebaseAccount",
            dependencies: [
                .target(name: "SpeziFirebaseConfiguration"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziValidation", package: "SpeziViews"),
                .product(name: "SpeziAccount", package: "SpeziAccount"),
                .product(name: "SpeziLocalStorage", package: "SpeziStorage"),
                .product(name: "SpeziSecureStorage", package: "SpeziStorage"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
            ],
            swiftSettings: [
                swiftConcurrency
            ],
            plugins: [] + swiftLintPlugin()
        ),
        .target(
            name: "SpeziFirebaseConfiguration",
            dependencies: [
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ],
            swiftSettings: [
                swiftConcurrency
            ],
            plugins: [] + swiftLintPlugin()
        ),
        .target(
            name: "SpeziFirestore",
            dependencies: [
                .target(name: "SpeziFirebaseConfiguration"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestoreSwift", package: "firebase-ios-sdk")
            ],
            swiftSettings: [
                swiftConcurrency
            ],
            plugins: [] + swiftLintPlugin()
        ),
        .target(
            name: "SpeziFirebaseStorage",
            dependencies: [
                .target(name: "SpeziFirebaseConfiguration"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk")
            ],
            swiftSettings: [
                swiftConcurrency
            ],
            plugins: [] + swiftLintPlugin()
        ),
        .target(
            name: "SpeziFirebaseAccountStorage",
            dependencies: [
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziAccount", package: "SpeziAccount"),
                .target(name: "SpeziFirestore")
            ],
            swiftSettings: [
                swiftConcurrency
            ],
            plugins: [] + swiftLintPlugin()
        ),
        .testTarget(
            name: "SpeziFirebaseTests",
            dependencies: [
                .target(name: "SpeziFirebaseAccount"),
                .target(name: "SpeziFirebaseConfiguration"),
                .target(name: "SpeziFirestore")
            ],
            swiftSettings: [
                swiftConcurrency
            ],
            plugins: [] + swiftLintPlugin()
        )
    ]
)


func swiftLintPlugin() -> [Target.PluginUsage] {
    // Fully quit Xcode and open again with `open --env SPEZI_DEVELOPMENT_SWIFTLINT /Applications/Xcode.app`
    if ProcessInfo.processInfo.environment["SPEZI_DEVELOPMENT_SWIFTLINT"] != nil {
        [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")]
    } else {
        []
    }
}

func swiftLintPackage() -> [PackageDescription.Package.Dependency] {
    if ProcessInfo.processInfo.environment["SPEZI_DEVELOPMENT_SWIFTLINT"] != nil {
        [.package(url: "https://github.com/realm/SwiftLint.git", .upToNextMinor(from: "0.55.1"))]
    } else {
        []
    }
}
