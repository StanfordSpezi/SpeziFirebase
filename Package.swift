// swift-tools-version:5.9

//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import PackageDescription


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
        .package(url: "https://github.com/StanfordSpezi/Spezi", .upToNextMinor(from: "0.8.0")),
        .package(url: "https://github.com/StanfordSpezi/SpeziViews.git", .upToNextMinor(from: "0.6.1")),
        .package(url: "https://github.com/StanfordSpezi/SpeziAccount", branch: "fix/storage-standard"),
        .package(url: "https://github.com/StanfordSpezi/SpeziStorage", .upToNextMinor(from: "0.5.0")),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.13.0")
    ],
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
            ]
        ),
        .target(
            name: "SpeziFirebaseConfiguration",
            dependencies: [
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ]
        ),
        .target(
            name: "SpeziFirestore",
            dependencies: [
                .target(name: "SpeziFirebaseConfiguration"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestoreSwift", package: "firebase-ios-sdk")
            ]
        ),
        .target(
            name: "SpeziFirebaseStorage",
            dependencies: [
                .target(name: "SpeziFirebaseConfiguration"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk")
            ]
        ),
        .target(
            name: "SpeziFirebaseAccountStorage",
            dependencies: [
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziAccount", package: "SpeziAccount"),
                .target(name: "SpeziFirestore")
            ]
        ),
        .testTarget(
            name: "SpeziFirebaseTests",
            dependencies: [
                .target(name: "SpeziFirebaseAccount"),
                .target(name: "SpeziFirebaseConfiguration"),
                .target(name: "SpeziFirestore")
            ]
        )
    ]
)
