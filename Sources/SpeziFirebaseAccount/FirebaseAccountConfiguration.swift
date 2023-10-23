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
import SpeziLocalStorage
import SpeziSecureStorage


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
    @Dependency private var secureStorage: SecureStorage
    @Dependency private var localStorage: LocalStorage

    private let emulatorSettings: (host: String, port: Int)?
    private let authenticationMethods: FirebaseAuthAuthenticationMethods

    @Provide var accountServices: [any AccountService]

    /// Central context management for all account service implementations.
    private var context: FirebaseContext?
    
    /// - Parameters:
    ///   - authenticationMethods: The authentication methods that should be supported.
    ///   - emulatorSettings: The emulator settings. The default value is `nil`, connecting the FirebaseAccount module to the Firebase Auth cloud instance.
    public init(
        authenticationMethods: FirebaseAuthAuthenticationMethods,
        emulatorSettings: (host: String, port: Int)? = nil
    ) {
        self.emulatorSettings = emulatorSettings
        self.authenticationMethods = authenticationMethods
        self.accountServices = []

        if authenticationMethods.contains(.emailAndPassword) {
            self.accountServices.append(FirebaseEmailPasswordAccountService())
        }
        if authenticationMethods.contains(.signInWithApple) {
            self.accountServices.append(FirebaseIdentityProviderAccountService())
        }
    }
    
    public func configure() {
        if let emulatorSettings {
            Auth.auth().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }

        Task {
            // We might be configured above the AccountConfiguration and therefore the `Account` object
            // might not be injected yet.
            try? await Task.sleep(for: .milliseconds(10))

            let context = FirebaseContext(local: localStorage, secure: secureStorage)
            let firebaseServices = accountServices.compactMap { service in
                service as? any FirebaseAccountService
            }

            for service in firebaseServices {
                await service.configure(with: context)
            }

            await context.setup(firebaseServices)
            self.context = context
        }
    }
}
