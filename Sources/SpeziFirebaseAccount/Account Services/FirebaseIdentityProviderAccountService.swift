//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
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


actor FirebaseIdentityProviderAccountService: IdentityProvider, FirebaseAccountService {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "IdentityProvider")

    private static let supportedKeys = AccountKeyCollection {
        \.accountId
        \.userId
        \.name
    }

    nonisolated var viewStyle: FirebaseIdentityProviderViewStyle {
        FirebaseIdentityProviderViewStyle(service: self)
    }

    let configuration: AccountServiceConfiguration

    private var authorizationController: AuthorizationController?

    @MainActor @AccountReference var account: Account // property wrappers cannot be non-isolated, so we isolate it to main actor
    @MainActor private var lastNonce: String?

    @_WeakInjectable var context: FirebaseContext

    init() { // TODO provider enum instantiation?
        self.configuration = AccountServiceConfiguration(
            name: "Identity Provider", // TODO source name from type
            supportedKeys: .exactly(Self.supportedKeys)
        ) {
            RequiredAccountKeys {
                \.userId
            }
            UserIdConfiguration(type: .emailAddress, keyboardType: .emailAddress)
        }
    }


    func configure(with context: FirebaseContext) async {
        self._context.inject(context)
        await context.share(account: account)
    }

    func inject(authorizationController: AuthorizationController) {
        self.authorizationController = authorizationController
    }

    func handleAccountRemoval(userId: String?) async {
        // nothing we are doing here
    }

    func reauthenticateUser(userId: String, user: User) async {
        // TODO how to check if token still valid?

        // TODO reauthenticate token https://firebase.google.com/docs/auth/ios/apple
    }

    func signUp(signupDetails: SignupDetails) async throws {
        guard let credential = signupDetails.oauthCredential else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await context.dispatchFirebaseAuthAction(on: self) {
            let authResult = try await Auth.auth().signIn(with: credential) // TODO review error!
            Self.logger.debug("signIn(with:) credential for user.")

            return authResult
        }
    }

    func delete() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if await account.signedIn {
                try await context.notifyUserRemoval(for: self)
            }
            throw FirebaseAccountError.notSignedIn
        }

        try await context.dispatchFirebaseAuthAction(on: self) {
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            await onAppleSignInRequest(request: request)

            // TODO verify that controller is non-nil

            guard let result = try await performRequest(request),
                  case let .appleID(credential) = result else {
                return // TODO handle?
            }

            guard let _ = await lastNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }

            guard let appleAuthCode = credential.authorizationCode else {
                print("Unable to fetch authorization code")
                return
            }

            guard let authCodeString = String(data: appleAuthCode, encoding: .utf8) else {
                print("Unable to serialize auth code string from data: \(appleAuthCode.debugDescription)")
                return
            }
            // TODO token revocation!!! https://firebase.google.com/docs/auth/ios/apple
            
            print("Revoking!")
            do {
                try await Auth.auth().revokeToken(withAuthorizationCode: authCodeString) // TODO review error!
            } catch {
                // TODO token revocation fails on simulator https://github.com/firebase/firebase-tools/pull/6050
                print(error)
                throw error
            }

            print("Deleting")
            try await currentUser.delete()
            Self.logger.debug("delete() for user.")
        }
    }

    private func performRequest(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationResult? {
        guard let authorizationController else {
            // TODO throw some error!
            return nil
        }

        do {
            return try await authorizationController.performRequest(request)
        } catch {
            try await onAppleSignInCompletion(result: .failure(error))
        }

        return nil
    }

    @MainActor
    func onAppleSignInRequest(request: ASAuthorizationAppleIDRequest) {
        let nonce = CryptoUtils.randomNonceString(length: 32)
        // we configured userId as `required` in the account service
        var requestedScopes: [ASAuthorization.Scope] = [.email]

        let nameRequirement = account.configuration[PersonNameKey.self]?.requirement
        if nameRequirement == .required { // .collected names will be collected later-on
            requestedScopes.append(.fullName)
        }

        request.nonce = CryptoUtils.sha256(nonce)
        request.requestedScopes = requestedScopes

        self.lastNonce = nonce // save the nonce for later use to be passed to FirebaseAuth
    }

    @MainActor
    func onAppleSignInCompletion(result: Result<ASAuthorization, Error>) async throws {
        defer { // cleanup tasks
            self.lastNonce = nil
        }

        switch result {
        case let .success(authorization):
            guard let appleIdCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                Self.logger.error("Unable to obtain credential as ASAuthorizationAppleIDCredential")
                throw FirebaseAccountError.setupError
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

            // the fullName is only provided on first contact. After that Apple won't supply that anymore!
            let credential: OAuthCredential = OAuthProvider.appleCredential(
                withIDToken: identityTokenString,
                rawNonce: lastNonce,
                fullName: appleIdCredential.fullName
            )

            let signupDetails = SignupDetails.Builder()
                .set(\.oauthCredential, value: .init(credential: credential))
                .build()


            // TODO we are currently bypassing all wrapped standards!
            try await signUp(signupDetails: signupDetails)
        case let .failure(error):
            guard let authorizationError = error as? ASAuthorizationError else {
                Self.logger.error("onAppleSignInCompletion received unknown error: \(error)")
                throw error
            }

            Self.logger.error("Received ASAuthorizationError error: \(authorizationError)")

            switch ASAuthorizationError.Code(rawValue: authorizationError.errorCode) {
            case .unknown, .canceled: // 1000, 1001
                // unknown is thrown if e.g. user is not logged in at all. Apple will show a pop up then!
                // cancelled is user interaction, no need to show anything
                break
            case .invalidResponse, .notHandled, .failed, .notInteractive: // 1002, 1003, 1004, 1005
                throw FirebaseAccountError.appleFailed
            default:
                throw FirebaseAccountError.setupError
            }
        }
    }
}
