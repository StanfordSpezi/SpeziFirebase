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

    init() {
        self.configuration = AccountServiceConfiguration(
            name: LocalizedStringResource("FIREBASE_IDENTITY_PROVIDER", bundle: .atURL(from: .module)),
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

    func reauthenticateUser(userId: String, user: User) async throws {
        guard let appleIdCredential = try await requestAppleSignInCredential() else {
            return // user canceled
        }
        
        let credential = try await oAuthCredential(from: appleIdCredential)

        try await user.reauthenticate(with: credential)
    }

    func signUp(signupDetails: SignupDetails) async throws {
        guard let credential = signupDetails.oauthCredential else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await context.dispatchFirebaseAuthAction(on: self) {
            let authResult = try await Auth.auth().signIn(with: credential)
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

        try await context.dispatchFirebaseAuthAction(on: self) { () -> Void in
            guard let credential = try await requestAppleSignInCredential() else {
                return // user canceled
            }

            guard let authorizationCode = credential.authorizationCode else {
                Self.logger.error("Unable to fetch authorizationCode from ASAuthorizationAppleIDCredential.")
                throw FirebaseAccountError.setupError
            }

            guard let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
                Self.logger.error("Unable to serialize authorizationCode to utf8 string.")
                throw FirebaseAccountError.setupError
            }

            do {
                Self.logger.debug("Revoking Apple Id Token ...")
                try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCodeString)
            } catch let error as NSError {
                #if targetEnvironment(simulator)
                // token revocation for Sign in with Apple is currently unsupported for Firebase
                // see https://github.com/firebase/firebase-tools/issues/6028
                // and https://github.com/firebase/firebase-tools/pull/6050
                if AuthErrorCode(_nsError: error).code != .invalidCredential {
                    throw error
                }
                #else
                throw error
                #endif
            } catch {
                throw error
            }

            try await currentUser.delete()
            Self.logger.debug("delete() for user.")
        }
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

            let credential = try oAuthCredential(from: appleIdCredential)

            Self.logger.info("onAppleSignInCompletion creating firebase apple credential from authorization credential")

            let signupDetails = SignupDetails.Builder()
                .set(\.oauthCredential, value: .init(credential: credential))
                .build()


            // We are currently calling the signup method directly. This, in theory, makes a difference.
            // In SpeziAccount, AccountServices might be wrapped by other (so called StandardBacked) account services
            // that add additional implementation. E.g., if a SignupDetails request contains data that is not storable
            // by this account service, this would get automatically handled by the wrapping account service.
            // As we know exactly, that this won't happen, we don't have to bother routing this request to
            // an potentially encapsulating account service. But this should be a heads up for future development.
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


    private func requestAppleSignInCredential() async throws -> ASAuthorizationAppleIDCredential? {
        Self.logger.debug("Requesting on the fly Sign in with Apple")
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()

        await onAppleSignInRequest(request: request)

        guard let result = try await performRequest(request),
              case let .appleID(credential) = result else {
            return nil
        }

        guard await lastNonce != nil else {
            Self.logger.error("onAppleSignInCompletion was received though no login request was found.")
            throw FirebaseAccountError.setupError
        }

        return credential
    }

    private func performRequest(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationResult? {
        guard let authorizationController else {
            Self.logger.error("Failed to perform AppleID request. We are missing access to the AuthorizationController. Did you set up the .firebaseAccount() modifier?")
            throw FirebaseAccountError.setupError
        }

        do {
            return try await authorizationController.performRequest(request)
        } catch {
            try await onAppleSignInCompletion(result: .failure(error))
        }

        return nil
    }

    @MainActor
    private func oAuthCredential(from credential: ASAuthorizationAppleIDCredential) throws -> OAuthCredential {
        guard let lastNonce else {
            Self.logger.error("AppleIdCredential was received though no login request was found.")
            throw FirebaseAccountError.setupError
        }

        guard let identityToken = credential.identityToken else {
            Self.logger.error("Unable to fetch identityToken from ASAuthorizationAppleIDCredential.")
            throw FirebaseAccountError.setupError
        }

        guard let identityTokenString = String(data: identityToken, encoding: .utf8) else {
            Self.logger.error("Unable to serialize identityToken to utf8 string.")
            throw FirebaseAccountError.setupError
        }

        // the fullName is only provided on first contact. After that Apple won't supply that anymore!
        return OAuthProvider.appleCredential(
            withIDToken: identityTokenString,
            rawNonce: lastNonce,
            fullName: credential.fullName
        )
    }
}
