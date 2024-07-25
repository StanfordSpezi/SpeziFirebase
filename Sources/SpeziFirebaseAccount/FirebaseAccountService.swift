//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
@preconcurrency import FirebaseAuth
import OSLog
import Spezi
import SpeziAccount
import SpeziFirebaseConfiguration
import SwiftUI


/// Configures an `AccountService` to interact with Firebase Auth.
///
/// The `FirebaseAccountConfiguration` can, e.g., be used to to connect to the Firebase Auth emulator:
/// ```
/// class ExampleAppDelegate: SpeziAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             FirebaseAccountConfiguration(emulatorSettings: (host: "localhost", port: 9099))
///             // ...
///         }
///     }
/// }
/// ```
public final class FirebaseAccountService: AccountService {
    // TODO: update all docs!
    @Application(\.logger)
    private var logger

    @Dependency private var configureFirebaseApp: ConfigureFirebaseApp
    @Dependency private var context: FirebaseContext

    @Dependency private var account: Account
    @Dependency private var notifications: AccountNotifications
    @Dependency private var externalStorage: ExternalAccountStorage

    @Model private var firebaseModel = FirebaseAccountModel()
    @Modifier private var firebaseModifier = FirebaseAccountModifier()

    private let emulatorSettings: (host: String, port: Int)?
    private let authenticationMethods: FirebaseAuthAuthenticationMethods
    public let configuration: AccountServiceConfiguration

    @IdentityProvider(placement: .embedded)
    private var loginWithPassword = FirebaseLoginView()
    @IdentityProvider(placement: .external)
    private var signInWithApple = FirebaseSignInWithAppleButton()

    @SecurityRelatedModifier private var emailPasswordReauth = ReauthenticationAlertModifier()


    // TODO: manage state order stuff!
    @MainActor private var lastNonce: String?

    /// - Parameters:
    ///   - authenticationMethods: The authentication methods that should be supported.
    ///   - emulatorSettings: The emulator settings. The default value is `nil`, connecting the FirebaseAccount module to the Firebase Auth cloud instance.
    public init(
        authenticationMethods: FirebaseAuthAuthenticationMethods,
        emulatorSettings: (host: String, port: Int)? = nil
    ) {
        // TODO: how do we support anonymous login and e.g. a invitation code setup with FirebaseAccountService? => anonymous account and signup only (however login page at when already used).
        self.emulatorSettings = emulatorSettings
        self.authenticationMethods = authenticationMethods

        let supportedKeys = AccountKeyCollection {
            // TODO: try to remove the supportedKeys, account service makes sure keys are there anyways?
            \.accountId
            \.userId

            // TODO: how does that translate to the new model of singleton Account Services?
            if authenticationMethods.contains(.emailAndPassword) {
                \.password
            }
            \.name
        }

        self.configuration = AccountServiceConfiguration(supportedKeys: .exactly(supportedKeys)) {
            RequiredAccountKeys {
                \.userId
                if authenticationMethods.contains(.emailAndPassword) {
                    \.password // TODO: how does that translate to the new model?
                }
            }

            UserIdConfiguration.emailAddress
            FieldValidationRules(for: \.userId, rules: .minimalEmail)
            FieldValidationRules(for: \.password, rules: .minimumFirebasePassword) // TODO: still support overriding this?
        }

        if !authenticationMethods.contains(.emailAndPassword) {
            $loginWithPassword.isEnabled = false
        }
        if !authenticationMethods.contains(.signInWithApple) {
            $signInWithApple.isEnabled = false
        }
    }
    
    public func configure() {
        if let emulatorSettings {
            Auth.auth().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }

        let subscription = externalStorage.detailUpdates
        Task { [weak self] in
            for await updatedDetails in subscription {
                guard let self else {
                    return
                }

                handleUpdatedDetailsFromExternalStorage(for: updatedDetails.accountId, details: updatedDetails.details)
            }
        }
    }

    private func handleUpdatedDetailsFromExternalStorage(for accountId: String, details: AccountDetails) {
        // TODO: merge with local representation and notify account of the new details?
    }

    func login(userId: String, password: String) async throws {
        logger.debug("Received new login request...")

        try await context.dispatchFirebaseAuthAction { @MainActor in
            try await Auth.auth().signIn(withEmail: userId, password: password)
            logger.debug("signIn(withEmail:password:)")
        }
    }

    func signUp(signupDetails: AccountDetails) async throws {
        logger.debug("Received new signup request...")

        guard let password = signupDetails.password else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await context.dispatchFirebaseAuthAction { @MainActor in
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: signupDetails.userId, password: password)
                logger.debug("Linking email-password credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                if let displayName = signupDetails.name { // TODO: we are not doing that thing with Apple?
                    try await updateDisplayName(of: result.user, displayName)
                }

                try await context.notifyUserSignIn(user: result.user)

                return
            }

            let authResult = try await Auth.auth().createUser(withEmail: signupDetails.userId, password: password)
            logger.debug("createUser(withEmail:password:) for user.")

            logger.debug("Sending email verification link now...")
            try await authResult.user.sendEmailVerification()

            if let displayName = signupDetails.name {
                try await updateDisplayName(of: authResult.user, displayName)
            }
        }
    }

    func signupWithCredential(_ credential: OAuthCredential) async throws {
        // TODO: the whole firebase auth action complexity is not necessary anymore is it? (We are a single account service now!)
        try await context.dispatchFirebaseAuthAction { @MainActor in
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                logger.debug("Linking oauth credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                try await context.notifyUserSignIn(user: currentUser, isNewUser: true)

                return result
            }

            let authResult = try await Auth.auth().signIn(with: credential)
            logger.debug("signIn(with:) credential for user.")

            return authResult // TODO: resolve the slight "isNewUser" difference! just make the "ask for potential differences" explicit!
        }
    }

    func resetPassword(userId: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: userId)
            logger.debug("sendPasswordReset(withEmail:) for user.")
        } catch let error as NSError {
            let firebaseError = FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
            if case .invalidCredentials = firebaseError {
                return // make sure we don't leak any information // TODO: we are not throwing?
            } else {
                throw firebaseError
            }
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    public func logout() async throws {
        guard Auth.auth().currentUser != nil else {
            if account.signedIn {
                try await context.notifyUserRemoval()
                return
            } else {
                throw FirebaseAccountError.notSignedIn
            }
        }

        try await context.dispatchFirebaseAuthAction { @MainActor in
            try Auth.auth().signOut()
            try await Task.sleep(for: .milliseconds(10))
            logger.debug("signOut() for user.")
        }
    }

    public func delete() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if account.signedIn {
                try await context.notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        try await notifications.reportEvent(.deletingAccount, for: currentUser.uid)

        try await context.dispatchFirebaseAuthAction { @MainActor in
            // TODO: always use Apple Id if we can, we need the token!
            let result = try await reauthenticateUser(user: currentUser) // delete requires a recent sign in
            guard case .success = result else {
                logger.debug("Re-authentication was cancelled by user. Not deleting the account.")
                return // cancelled
            }

            if let credential = result.credential {
                // re-authentication was made through sign in provider, delete SSO account as well
                guard let authorizationCode = credential.authorizationCode else {
                    logger.error("Unable to fetch authorizationCode from ASAuthorizationAppleIDCredential.")
                    throw FirebaseAccountError.setupError
                }

                guard let authorizationCodeString = String(data: authorizationCode, encoding: .utf8) else {
                    logger.error("Unable to serialize authorizationCode to utf8 string.")
                    throw FirebaseAccountError.setupError
                }

                do {
                    logger.debug("Revoking Apple Id Token ...")
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
            }

            try await currentUser.delete()
            logger.debug("delete() for user.")
        }
    }

    public func updateAccountDetails(_ modifications: AccountModifications) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if account.signedIn {
                try await context.notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        do {
            // if we modify sensitive credentials and require a recent login
            if modifications.modifiedDetails.storage[UserIdKey.self] != nil || modifications.modifiedDetails.password != nil {
                let result = try await reauthenticateUser(user: currentUser)
                guard case .success = result else {
                    logger.debug("Re-authentication was cancelled. Not updating sensitive user details.")
                    return // got cancelled!
                }
            }

            if let userId = modifications.modifiedDetails.storage[UserIdKey.self] {
                logger.debug("updateEmail(to:) for user.")
                // TODO: try await currentUser.sendEmailVerification(beforeUpdatingEmail: userId) (show in UI that they need to accept!)
                try await currentUser.updateEmail(to: userId)
            }

            if let password = modifications.modifiedDetails.password {
                logger.debug("updatePassword(to:) for user.")
                try await currentUser.updatePassword(to: password)
            }

            if let name = modifications.modifiedDetails.name {
                try await updateDisplayName(of: currentUser, name)
            }

            // None of the above requests will trigger our state change listener, therefore, we just call it manually.
            try await context.notifyUserSignIn(user: currentUser)
        } catch let error as NSError {
            logger.error("Received NSError on firebase dispatch: \(error)")
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            logger.error("Received error on firebase dispatch: \(error)")
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private func reauthenticateUser(user: User) async throws -> ReauthenticationOperation {
        // TODO: which reauthentication to call? (Just prefer Apple for simplicity?) => any way to build UI for a selection?

        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            try await reauthenticateUserApple(user: user)
        } else {
            try await reauthenticateUserPassword(user: user)
        }
    }

    private func reauthenticateUserPassword(user: User) async throws -> ReauthenticationOperation {
        guard let userId = user.email else {
            return .cancelled
        }

        logger.debug("Requesting credentials for re-authentication...")
        let passwordQuery = await firebaseModel.reauthenticateUser(userId: userId)
        guard case let .password(password) = passwordQuery else {
            return .cancelled
        }

        logger.debug("Re-authenticating password-based user now ...")
        try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: userId, password: password))
        return .success
    }

    private func reauthenticateUserApple(user: User) async throws -> ReauthenticationOperation {
        guard let appleIdCredential = try await requestAppleSignInCredential() else {
            return .cancelled
        }

        let credential = try oAuthCredential(from: appleIdCredential)
        logger.debug("Re-Authenticating Apple credential ...")
        try await user.reauthenticate(with: credential)

        return .success(with: appleIdCredential)
    }

    private func updateDisplayName(of user: User, _ name: PersonNameComponents) async throws {
        logger.debug("Creating change request for updated display name.")
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name.formatted(.name(style: .long))
        try await changeRequest.commitChanges()
    }
}


// MARK: - Sign In With Apple

extension FirebaseAccountService {
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
                logger.error("Unable to obtain credential as ASAuthorizationAppleIDCredential")
                throw FirebaseAccountError.setupError
            }

            let credential = try oAuthCredential(from: appleIdCredential)

            logger.info("onAppleSignInCompletion creating firebase apple credential from authorization credential")

            try await signupWithCredential(credential)
        case let .failure(error):
            guard let authorizationError = error as? ASAuthorizationError else {
                logger.error("onAppleSignInCompletion received unknown error: \(error)")
                throw error
            }

            logger.error("Received ASAuthorizationError error: \(authorizationError)")

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
        logger.debug("Requesting on the fly Sign in with Apple")
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()

        onAppleSignInRequest(request: request)

        guard let result = try await performRequest(request),
              case let .appleID(credential) = result else {
            return nil
        }

        guard lastNonce != nil else {
            logger.error("onAppleSignInCompletion was received though no login request was found.")
            throw FirebaseAccountError.setupError
        }

        return credential
    }

    private func performRequest(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationResult? {
        guard let authorizationController = firebaseModel.authorizationController else {
            logger.error("Failed to perform AppleID request. We are missing access to the AuthorizationController.")
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
            logger.error("AppleIdCredential was received though no login request was found.")
            throw FirebaseAccountError.setupError
        }

        guard let identityToken = credential.identityToken else {
            logger.error("Unable to fetch identityToken from ASAuthorizationAppleIDCredential.")
            throw FirebaseAccountError.setupError
        }

        guard let identityTokenString = String(data: identityToken, encoding: .utf8) else {
            logger.error("Unable to serialize identityToken to utf8 string.")
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
