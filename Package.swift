// swift-tools-version:5.7

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
        .iOS(.v16)
    ],
    products: [
        .library(name: "SpeziFirebaseAccount", targets: ["SpeziFirebaseAccount"]),
        .library(name: "SpeziFirebaseConfiguration", targets: ["SpeziFirebaseConfiguration"]),
        .library(name: "SpeziFirestore", targets: ["SpeziFirestore"]),
        .library(name: "SpeziFirestorePrefixUserIdAdapter", targets: ["SpeziFirestorePrefixUserIdAdapter"])
    ],
    dependencies: [
        .package(url: "https://github.com/StanfordBDHG/Spezi", .upToNextMinor(from: "0.4.1")),
        .package(url: "https://github.com/StanfordBDHG/SpeziAccount", .upToNextMinor(from: "0.2.0")),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.7.0")
    ],
    targets: [
        .target(
            name: "SpeziFirebaseAccount",
            dependencies: [
                .target(name: "SpeziFirebaseConfiguration"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "SpeziAccount", package: "SpeziAccount"),
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
            name: "SpeziFirestorePrefixUserIdAdapter",
            dependencies: [
                .target(name: "SpeziFirestore"),
                .product(name: "Spezi", package: "Spezi"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
            ]
        ),
        .testTarget(
            name: "SpeziFirebaseTests",
            dependencies: [
                .target(name: "SpeziFirebaseAccount"),
                .target(name: "SpeziFirebaseConfiguration"),
                .target(name: "SpeziFirestore"),
                .target(name: "SpeziFirestorePrefixUserIdAdapter")
            ]
        )
    ]
)
