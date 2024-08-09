//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseCore
import Spezi


/// Configure the Firebase application.
///
/// The `FirebaseApp.configure()` method will be called upon configuration of the `Module`.
///
/// Use the `@Dependency` property wrapper to define a dependency on this module and ensure that `FirebaseApp.configure()` is called before any
/// other Firebase-related modules and to ensure it is called exactly once.
///
/// ```swift
/// import Spezi
/// import SpeziFirebaseConfiguration
///
/// public final class MyFirebaseModule: Module {
///     @Dependency(ConfigureFirebaseApp.self)
///     private var configureFirebaseApp
/// }
/// ```
public final class ConfigureFirebaseApp: Module, DefaultInitializable {
    public init() {}
    
    
    public func configure() {
        FirebaseApp.configure()
    }
}
