//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziAccount
@_exported import class FirebaseAuth.User
import class FirebaseAuth.Auth
import protocol FirebaseAuth.AuthStateDidChangeListenerHandle
import FirebaseCore
import Foundation
import SpeziFirebaseConfiguration


/// Configures Firebase Auth `AccountService`s that can be used in any views of the `Account` module.
///
/// The ``FirebaseAccountConfiguration`` offers a ``user`` property to access the current Firebase Auth user from, e.g., a SwiftUI view's environment:
/// ```
/// @EnvironmentObject var firebaseAccountConfiguration: FirebaseAccountConfiguration</* ... */>
/// ```
///
/// The ``FirebaseAccountConfiguration`` can, e.g., be used to to connect to the Firebase Auth emulator:
/// ```
/// class ExampleAppDelegate: SpeziAppDelegate {
///     override var configuration: Configuration {
///         Configuration(standard: /* ... */) {
///             FirebaseAccountConfiguration(emulatorSettings: (host: "localhost", port: 9099))
///             // ...
///         }
///     }
/// }
/// ```
public final class FirebaseAccountConfiguration: Component {
    @Dependency private var configureFirebaseApp: ConfigureFirebaseApp

    private let emulatorSettings: (host: String, port: Int)?
    private let authenticationMethods: FirebaseAuthAuthenticationMethods

    public let accountService: FirebaseEmailPasswordAccountService // TODO this protocol requirement requires us to make the service public!
    
    /// - Parameters:
    ///   - emulatorSettings: The emulator settings. The default value is `nil`, connecting the FirebaseAccount module to the Firebase Auth cloud instance.
    ///   - authenticationMethods: The authentication methods that should be supported.
    public init(
        emulatorSettings: (host: String, port: Int)? = nil,
        authenticationMethods: FirebaseAuthAuthenticationMethods = .all
    ) {
        self.emulatorSettings = emulatorSettings
        self.authenticationMethods = authenticationMethods

        // TODO at least one authenticationMethod!
        //  if authenticationMethods.contains(.emailAndPassword)
        self.accountService = FirebaseEmailPasswordAccountService()
    }
    
    public func configure() {
        if let emulatorSettings {
            Auth.auth().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }

        Task {
            await accountService.configure()
        }
    }
}
