//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseCore
import FirebaseFirestore
import FirebaseFirestoreSwift
import Spezi
import SpeziFirebaseConfiguration
import SwiftUI


/// The ``Firestore`` module allows for easy configuration of Firebase Firestore.
///
/// You can configure the ``Firestore`` module in the `SpeziAppDelegate`, e.g. the configure it using the Firebase emulator.
/// ```swift
/// class FirestoreExampleDelegate: SpeziAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             Firestore(settings: .emulator)
///             // ...
///         }
///     }
/// }
/// ```
///
/// - Note: We recommend using the [Firebase Firestore SDK as defined in the API documentation](https://firebase.google.com/docs/firestore/manage-data/add-data#swift)
///     throughout the application. We **highly recommend using the async/await variants of the APIs** instead of the closure-based APIs the SDK provides.
public class Firestore: Module, DefaultInitializable {
    @Dependency(ConfigureFirebaseApp.self)
    private var configureFirebaseApp

    private let settings: FirestoreSettings
    
    
    public required convenience init() {
        self.init(settings: FirestoreSettings())
    }
    
    /// - Parameters:
    ///   - settings: The firestore settings according to the [Firebase Firestore Swift Package](https://firebase.google.com/docs/reference/swift/firebasefirestore/api/reference/Classes/FirestoreSettings)
    public init(settings: FirestoreSettings) {
        self.settings = settings
    }
    
    
    public func configure() {
        FirebaseFirestore.Firestore.firestore().settings = self.settings
        
        _ = FirebaseFirestore.Firestore.firestore()
    }
}
