//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseCore
import Spezi

// TODO: find and replace all "components"


/// Module to configure the Firebase set of dependencies.
///
/// The ``configure()`` method calls `FirebaseApp.configure()`.
/// Use the `@Dependency` property wrapper to define a dependency on this component and ensure that `FirebaseApp.configure()` is called before any
/// other Firebase-related components:
/// ```swift
/// public final class YourFirebaseModule: Module {
///     @Dependency private var configureFirebaseApp: ConfigureFirebaseApp
///
///     // ...
/// }
/// ```
public final class ConfigureFirebaseApp: Module, DefaultInitializable {
    public init() {}
    
    
    public func configure() {
        FirebaseApp.configure()
    }
}
