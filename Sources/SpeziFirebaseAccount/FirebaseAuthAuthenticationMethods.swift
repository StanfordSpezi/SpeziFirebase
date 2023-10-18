//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Definition of the authentication methods supported by the FirebaseAccount module.
public struct FirebaseAuthAuthenticationMethods: OptionSet {
    // TODO document necessary steps:
    //  email and password: enable in firebase
    //  apple: Xcode project setup (add capabilities) => signing capabilities (account and stuff!)
    //    - setup firebase (add sign in with apple)

    /// E-Mail and password-based authentication.
    public static let emailAndPassword = FirebaseAuthAuthenticationMethods(rawValue: 1 << 0)
    /// Sign In With Apple Identity Provider.
    public static let signInWithApple = FirebaseAuthAuthenticationMethods(rawValue: 1 << 1)


    /// All authentication methods.
    public static let all: FirebaseAuthAuthenticationMethods = [.emailAndPassword, .signInWithApple]
    // TODO all doesn't make sense + we need a way to inejct from the outside (e.g. GoogleSignIn!)
    
    
    public let rawValue: Int
    
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}
