//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Authentication Providers supported by the `FirebaseAccountService`.
public struct FirebaseAuthProviders: OptionSet, Codable, Sendable {
    /// E-Mail and Password-based authentication.
    ///
    /// Please follow the necessary setup steps at [Password Authentication](https://firebase.google.com/docs/auth/ios/password-auth).
    public static let emailAndPassword = FirebaseAuthProviders(rawValue: 1 << 0)
    /// Sign In With Apple.
    ///
    /// Please follow the necessary setup steps at [Sign in with Apple](https://firebase.google.com/docs/auth/ios/apple).
    public static let signInWithApple = FirebaseAuthProviders(rawValue: 1 << 1)

    /// Sign in anonymously using a button press.
    @_spi(Internal)
    public static let anonymousButton = FirebaseAuthProviders(rawValue: 1 << 2)


    @_documentation(visibility: internal)
    public let rawValue: Int
    

    @_documentation(visibility: internal)
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
