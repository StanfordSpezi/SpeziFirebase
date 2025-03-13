//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseCore
import FirebaseCoreExtension
import Spezi


/// Configure the Firebase application.
///
/// The `FirebaseApp.configure()` method will be called upon configuration of the `Module`.
///
/// If your app uses the standard `GoogleService-Info.plist` approach to configure Firebase, you don't need to explicitly enable this module.
/// However, if you want to use a custom, non-plist-based Firebase configuration, you should place t
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
    private enum Input {
        case useDefault
        case custom(name: String, options: FirebaseOptions)
    }
    
    /// Whether any instance of this module was already configured.
    /// We use this property to keep track of this, since Firebase doesn't allow repeated configuration.
    @MainActor private static var didConfigure = false
    
    @MainActor private static var usedConfigInput: Input?
    
    // TODO: document!
    @MainActor private static var isDefaultConfigurationAllowed = true
    
    @MainActor public static func disallowDefaultConfiguration() {
        isDefaultConfigurationAllowed = false
    }
    
    @Application(\.logger)
    private var logger
    
    private let input: Input
    
    /// Creates a ``ConfigureFirebaseApp`` instance, which will configure firebase based on the contents of the `GoogleService-Info.plist` file.
    public init() {
        input = .useDefault
    }
    
    /// Creates a ``ConfigureFirebaseApp`` instance, which will configure firebase using custom configuration options.
    /// - parameter name: The name of the app. Defaults to `__FIRAPP_DEFAULT`.
    /// - parameter options: The options which should be used to configure firebase.
    public init(name: String = kFIRDefaultAppName, options: FirebaseOptions) {
        input = .custom(name: name, options: options)
    }
    
    @_documentation(visibility: internal)
    public func configure() {
        if let lastInput = Self.usedConfigInput {
            preconditionFailure("Firebase was already configured, using \(lastInput)")
        }
        guard !Self.didConfigure else {
            preconditionFailure("\(Self.self) module was included multiple times in Spezi Configuration")
        }
        switch input {
        case .useDefault:
            guard Self.isDefaultConfigurationAllowed else {
                preconditionFailure("Attempted to configure default config, which is disallowed.")
            }
            logger.notice("Configuring Firebase using default config")
            Self.usedConfigInput = input
            FirebaseApp.configure()
        case let .custom(name, options):
            logger.notice("Configuring Firebase using custom config; name=\(name); options=\(options)")
            Self.usedConfigInput = input
            FirebaseApp.configure(name: name, options: options)
        }
    }
}
