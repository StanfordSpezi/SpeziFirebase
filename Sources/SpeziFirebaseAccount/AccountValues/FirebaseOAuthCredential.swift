//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseAuth
import SpeziAccount
import SwiftUI

struct OAuthCredentialWrapper: Equatable {
    let credential: OAuthCredential
}


// TODO show signIn Provider in the Overview!
struct FirebaseOAuthCredentialKey: AccountKey {
    typealias Value = OAuthCredentialWrapper

    static let name: LocalizedStringResource = "OAuth Credential" // not translated as never shown
    static let category: AccountKeyCategory = .credentials
    static var initialValue: InitialValue<Value> {
        preconditionFailure("Cannot enter a new oauth credential manually")
    }
}

// Codable is required by SpeziAccount such that external Storage Providers can easily store keys.
// As this is an signup-only value, we make sure this isn't ever encoded.
extension OAuthCredentialWrapper: Codable {
    init(from decoder: Decoder) throws { // swiftlint:disable:this unavailable_function
        preconditionFailure("OAuthCredential must not be decoded!")
    }

    func encode(to encoder: Encoder) throws { // swiftlint:disable:this unavailable_function
        preconditionFailure("OAuthCredential must not be encoded!")
    }
}


extension AccountKeys {
    /// The OAuth Credential `AccountKey` metatype.
    var oauthCredential: FirebaseOAuthCredentialKey.Type {
        FirebaseOAuthCredentialKey.self
    }
}


extension SignupDetails {
    /// Access the OAuth Credential of a firebase user.
    var oauthCredential: OAuthCredential? {
        storage[FirebaseOAuthCredentialKey.self]?.credential
    }
}


extension FirebaseOAuthCredentialKey {
    public struct DataEntry: DataEntryView {
        public typealias Key = FirebaseOAuthCredentialKey

        public var body: some View {
            Text("The FirebaseOAuthCredentialKey cannot be set!")
        }

        public init(_ value: Binding<Value>) {}
    }

    public struct DataDisplay: DataDisplayView {
        public typealias Key = FirebaseOAuthCredentialKey

        public var body: some View {
            Text("The FirebaseOAuthCredentialKey cannot be displayed!")
        }

        public init(_ value: Value) {}
    }
}
