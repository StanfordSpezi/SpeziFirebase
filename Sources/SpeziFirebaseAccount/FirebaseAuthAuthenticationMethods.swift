//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Definition of the authentication methods supported by the FirebaseAccount module.
public struct FirebaseAuthAuthenticationMethods: OptionSet, Codable {
    /// E-Mail and password-based authentication.
    /// 
    /// Please follow the necessary setup steps at [Password Authentication](https://firebase.google.com/docs/auth/ios/password-auth).
    public static let emailAndPassword = FirebaseAuthAuthenticationMethods(rawValue: 1 << 0)
    /// Sign In With Apple Identity Provider.
    ///
    /// Please follow the necessary setup steps at [Sign in with Apple](https://firebase.google.com/docs/auth/ios/apple).
    public static let signInWithApple = FirebaseAuthAuthenticationMethods(rawValue: 1 << 1)
    
    
    public let rawValue: Int
    
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
