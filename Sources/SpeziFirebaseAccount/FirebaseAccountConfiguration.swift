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
public final class FirebaseAccountConfiguration: Module {
    @Dependency private var configureFirebaseApp: ConfigureFirebaseApp
    @Dependency private var secureStorage: SecureStorage
    @Dependency private var localStorage: LocalStorage
    @Dependency private var speziAccount: AccountConfiguration?

    @Provide private var accountServices: [any AccountService]

    @Model private var accountModel = FirebaseAccountModel()
    @Modifier private var firebaseModifier = FirebaseAccountModifier()

    private let emulatorSettings: (host: String, port: Int)?
    private let authenticationMethods: FirebaseAuthAuthenticationMethods


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
            self.accountServices.append(FirebaseIdentityProviderAccountService(accountModel))
        }
    }
    
    public func configure() {
        if let emulatorSettings {
            Auth.auth().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }


        guard speziAccount != nil else {
            preconditionFailure("""
                                Missing Account Configuration!
                                FirebaseAccount was configured but no \(AccountConfiguration.self) was provided. Please \
                                refer to the initial setup instructions of SpeziAccount: https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/initial-setup
                                """)
        }

        Task {
            let context = FirebaseContext(local: localStorage, secure: secureStorage)
            let firebaseServices = accountServices.compactMap { service in
                service as? any FirebaseAccountService
            }

            for service in firebaseServices {
                await service.configure(with: context)
            }

            await context.setup(firebaseServices)
            self.context = context // we inject as weak, so ensure to keep the reference here!
        }
    }
}
