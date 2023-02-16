// swift-tools-version:5.7

//
// This source file is part of the CardinalKit open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import PackageDescription


let package = Package(
    name: "CardinalKitFirebase",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "CardinalKitFirebaseAccount", targets: ["CardinalKitFirebaseAccount"]),
        .library(name: "CardinalKitFirebaseConfiguration", targets: ["CardinalKitFirebaseConfiguration"]),
        .library(name: "CardinalKitFirestore", targets: ["CardinalKitFirestore"]),
        .library(name: "CardinalKitFirestorePrefixUserIdAdapter", targets: ["CardinalKitFirestorePrefixUserIdAdapter"])
    ],
    dependencies: [
        .package(url: "https://github.com/StanfordBDHG/CardinalKit", .upToNextMinor(from: "0.3.0")),
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.3.0")
    ],
    targets: [
        .target(
            name: "CardinalKitFirebaseAccount",
            dependencies: [
                .target(name: "CardinalKitFirebaseConfiguration"),
                .product(name: "Account", package: "CardinalKit"),
                .product(name: "CardinalKit", package: "CardinalKit"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
            ]
        ),
        .target(
            name: "CardinalKitFirebaseConfiguration",
            dependencies: [
                .product(name: "CardinalKit", package: "CardinalKit"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ]
        ),
        .target(
            name: "CardinalKitFirestore",
            dependencies: [
                .target(name: "CardinalKitFirebaseConfiguration"),
                .product(name: "CardinalKit", package: "CardinalKit"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestoreSwift", package: "firebase-ios-sdk")
            ]
        ),
        .target(
            name: "CardinalKitFirestorePrefixUserIdAdapter",
            dependencies: [
                .target(name: "CardinalKitFirestore"),
                .product(name: "CardinalKit", package: "CardinalKit"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
            ]
        ),
        .testTarget(
            name: "CardinalKitFirebaseTests",
            dependencies: [
                .target(name: "CardinalKitFirebaseAccount"),
                .target(name: "CardinalKitFirebaseConfiguration"),
                .target(name: "CardinalKitFirestore"),
                .target(name: "CardinalKitFirestorePrefixUserIdAdapter")
            ]
        )
    ]
)
