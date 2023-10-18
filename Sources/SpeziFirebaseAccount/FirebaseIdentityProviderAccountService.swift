//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import CryptoKit
import FirebaseAuth
import OSLog
import SpeziAccount
import SwiftUI


struct FirebaseIdentityProviderViewStyle: IdentityProviderViewStyle {
    let service: FirebaseIdentityProviderAccountService


    init(service: FirebaseIdentityProviderAccountService) {
        self.service = service
    }


    func makeSignInButton() -> some View {
        FirebaseSignInWithAppleButton(service: service)
    }
}


actor FirebaseIdentityProviderAccountService: IdentityProvider {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "IdentityProvider")

    private static let supportedKeys = AccountKeyCollection {
        \.userId
        \.password // TODO remove this once we figure out how to support Account Service directed requirement level!
        \.name
    }

    nonisolated var viewStyle: FirebaseIdentityProviderViewStyle {
        FirebaseIdentityProviderViewStyle(service: self)
    }

    let configuration: AccountServiceConfiguration

    @MainActor @AccountReference private var account: Account // property wrappers cannot be nonisolated, so we isolate it to main actor
    @MainActor private var lastNonce: String?


    init() { // TODO provider enum instantiation?
        self.configuration = AccountServiceConfiguration(
            name: "Identity Provider", // TODO source name from type
            supportedKeys: .exactly(Self.supportedKeys) // TODO SpeziAccount support to automatically collect more!
        ) {
            RequiredAccountKeys {
                \.userId // TODO not password right, anything else, does that make sense?
            }
            UserIdConfiguration(type: .emailAddress, keyboardType: .emailAddress)

            // TODO field validation rules doesn't make sense right?
        }
    }

    func signUp(signupDetails: SignupDetails) async throws {
        // TODO actually check what we plug in! is that used?
    }

    func updateAccountDetails(_ modifications: AccountModifications) async throws {
        // TODO reuse stuff?
    }

    func logout() async throws {
        // TODO reuse everything!
    }

    func delete() async throws {
        // TODO reuse everything?

        // TODO token revocation!!! https://firebase.google.com/docs/auth/ios/apple
    }

    @MainActor
    func onAppleSignInRequest(request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString(length: 32)
        // we configured userId as `required` in the account service
        var requestedScopes: [ASAuthorization.Scope] = [.email]

        let nameRequirement = account.configuration[PersonNameKey.self]?.requirement
        if nameRequirement == .required || nameRequirement == .collected {
            requestedScopes.append(.fullName)
        }

        request.nonce = Self.sha256(nonce)
        request.requestedScopes = requestedScopes

        self.lastNonce = nonce // save the nonce for later use to be passed to FirebaseAuth
    }

    @MainActor
    func onAppleSignInCompletion(result: Result<ASAuthorization, Error>) throws {
        switch result {
        case let .success(authorization):
            guard let appleIdCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                Self.logger.error("Unable to obtain credential as ASAuthorizationAppleIDCredential")
                throw FirebaseAccountError.setupError // TODO it's not just account creation!
            }

            guard let lastNonce else {
                Self.logger.error("onAppleSignInCompletion was received though no login request was found.")
                throw FirebaseAccountError.setupError
            }

            guard let identityToken = appleIdCredential.identityToken else {
                Self.logger.error("Unable to fetch identityToken from ASAuthorizationAppleIDCredential.")
                throw FirebaseAccountError.setupError
            }

            guard let identityTokenString = String(data: identityToken, encoding: .utf8) else {
                Self.logger.error("Unable to serialize identityToken to utf8 string.")
                throw FirebaseAccountError.setupError
            }


            Self.logger.info("onAppleSignInCompletion creating firebase apple credential from authorization credential")

            // the appleIdCredential.fullName is only provided on first contact. After that Apple won't supply that anymore!
            // TODO we are only getting the name on first call, see https://firebase.google.com/docs/auth/ios/apple
            let credential = OAuthProvider.appleCredential(
                withIDToken: identityTokenString,
                rawNonce: lastNonce,
                fullName: appleIdCredential.fullName
            )
            // TODO would be pass this now to our own signup method, or how does that ideally work?
            // TODO we also might need to source additional information!
            //  => API support to calculate diffing what is required still!

            print(identityTokenString) // TODO remove!!!
            print(credential)

            Task { // TODO create a task earlier to report error back as well!
                do {
                    try await Auth.auth().signIn(with: credential)

                    // TODO we are now signed in and need to query additional data!
                } catch {
                    print("ERROR: \(error)") // TODO forward at some point?
                }
            }
        case let .failure(error):
            guard let authorizationError = error as? ASAuthorizationError else {
                Self.logger.error("onAppleSignInCompletion received unknown error: \(error)")
                // TODO forward localized description
                break
            }

            Self.logger.error("Received ASAuthorizationError error: \(authorizationError)")

            switch ASAuthorizationError.Code(rawValue: authorizationError.errorCode) {
            case .unknown, .canceled:
                // unknown is thrown if e.g. user is not logged in at all. Apple will show a pop up then!
                // cancelled is user interaction, no need to show anything
                break
            case .invalidResponse:
                break // TODO The authorization request received an invalid response.
            case .notHandled:
                break // TODO The authorization request wasn’t handled.
            case .failed:
                break // TODO The authorization attempt failed.
            case .notInteractive:
                break // TODO The authorization request isn’t interactive.
            default:
                break
            }

            self.lastNonce = nil

            // TODO render some error back in the UI! (just throw?)
        }
    }


    // TODO move both somewhere else!
    private static func randomNonceString(length: Int) -> String {
        precondition(length > 0, "Nonce length must be non-zero")
        let nonceCharacters = (0 ..< length).map { _ in
            // ASCII alphabet goes from 32 (space) to 126 (~)
            let num = Int.random(in: 32...126)
            guard let scalar = UnicodeScalar(num) else {
                preconditionFailure("Failed to generate ASCII character for nonce!")
            }
            return Character(scalar)
        }

        return String(nonceCharacters)
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { byte in
                String(format: "%02x", byte)
            }
            .joined()
    }
}
