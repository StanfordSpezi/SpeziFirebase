//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import FirebaseAuth
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
public final class FirebaseAccountConfiguration: AccountService {
    // TODO: replace with Spezi logger!
    static nonisolated let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "AccountService")

    // TODO: remove this in favor for the account service?
    @Dependency private var configureFirebaseApp: ConfigureFirebaseApp
    @Dependency private var account: Account
    @Dependency private var context: FirebaseContext

    @Model private var firebaseModel = FirebaseAccountModel()
    @Modifier private var firebaseModifier = FirebaseAccountModifier()

    private let emulatorSettings: (host: String, port: Int)?
    private let authenticationMethods: FirebaseAuthAuthenticationMethods
    public let configuration: AccountServiceConfiguration

    @IdentityProvider(placement: .embedded) private var loginWithPassword = FirebaseLoginView()
    @IdentityProvider(placement: .external) private var signInWithApple = FirebaseSignInWithAppleButton()

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
        self.emulatorSettings = emulatorSettings
        self.authenticationMethods = authenticationMethods

        let supportedKeys = AccountKeyCollection {
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
    }

    func login(userId: String, password: String) async throws {
        Self.logger.debug("Received new login request...")

        try await context.dispatchFirebaseAuthAction {
            try await Auth.auth().signIn(withEmail: userId, password: password)
            Self.logger.debug("signIn(withEmail:password:)")
        }
    }

    func signUp(signupDetails: SignupDetails) async throws {
        Self.logger.debug("Received new signup request...")

        guard let password = signupDetails.password else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await context.dispatchFirebaseAuthAction {
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: signupDetails.userId, password: password)
                Self.logger.debug("Linking email-password credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                if let displayName = signupDetails.name { // TODO: we are not doing that thing with Apple?
                    try await updateDisplayName(of: result.user, displayName)
                }

                try await context.notifyUserSignIn(user: result.user)

                return
            }

            let authResult = try await Auth.auth().createUser(withEmail: signupDetails.userId, password: password)
            Self.logger.debug("createUser(withEmail:password:) for user.")

            Self.logger.debug("Sending email verification link now...")
            try await authResult.user.sendEmailVerification()

            if let displayName = signupDetails.name {
                try await updateDisplayName(of: authResult.user, displayName)
            }
        }
    }

    func signupWithCredential(_ credential: OAuthCredential) async throws {
        // TODO: the whole firebase auth action complexity is not necessary anymore is it? (We are a single account service now!)
        try await context.dispatchFirebaseAuthAction {
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                Self.logger.debug("Linking oauth credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                try await context.notifyUserSignIn(user: currentUser, isNewUser: true)

                return result
            }

            let authResult = try await Auth.auth().signIn(with: credential)
            Self.logger.debug("signIn(with:) credential for user.")

            return authResult // TODO: resolve the slight "isNewUser" difference! just make the "ask for potential differences" explicit!
        }
    }

    func resetPassword(userId: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: userId)
            Self.logger.debug("sendPasswordReset(withEmail:) for user.")
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

    func reauthenticateUserPassword(user: User) async throws -> ReauthenticationOperationResult {
        guard let userId = user.email else {
            return .cancelled
        }

        Self.logger.debug("Requesting credentials for re-authentication...")
        let passwordQuery = await firebaseModel.reauthenticateUser(userId: userId)
        guard case let .password(password) = passwordQuery else {
            return .cancelled
        }

        Self.logger.debug("Re-authenticating password-based user now ...")
        try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: userId, password: password))
        return .success
    }

    func reauthenticateUserApple(user: User) async throws -> ReauthenticationOperationResult {
        guard let appleIdCredential = try await requestAppleSignInCredential() else {
            return .cancelled
        }

        let credential = try oAuthCredential(from: appleIdCredential)

        try await user.reauthenticate(with: credential)
        return .success
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

        try await context.dispatchFirebaseAuthAction {
            try Auth.auth().signOut()
            try await Task.sleep(for: .milliseconds(10))
            Self.logger.debug("signOut() for user.")
        }
    }

    public func delete() async throws {
        // TODO: how to navigate?
    }

    public func deleteUserIDCredential() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if account.signedIn {
                try await context.notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        try await context.dispatchFirebaseAuthAction {
            let result = try await reauthenticateUserPassword(user: currentUser) // delete requires a recent sign in
            guard case .success = result else {
                Self.logger.debug("Re-authentication was cancelled. Not deleting the account.")
                return // cancelled
            }

            try await currentUser.delete()
            Self.logger.debug("delete() for user.")
        }
    }

    public func deleteApple() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if account.signedIn {
                try await context.notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        try await context.dispatchFirebaseAuthAction {
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

            Self.logger.debug("Re-Authenticating Apple Credential before deleting user account ...")
            let authCredential = try oAuthCredential(from: credential)
            try await currentUser.reauthenticate(with: authCredential)

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
                let result: ReauthenticationOperationResult

                // TODO: which reauthentication to call? (Just prefer Apple for simplicity?)
                if currentUser.providerData.contains(where: {$0.providerID == "apple.com" }) { // TODO: that's how we check?
                    result = try await reauthenticateUserApple(user: currentUser)
                } else {
                    result = try await reauthenticateUserPassword(user: currentUser)
                }
                guard case .success = result else {
                    Self.logger.debug("Re-authentication was cancelled. Not deleting the account.")
                    return // got cancelled!
                }
            }

            if let userId = modifications.modifiedDetails.storage[UserIdKey.self] {
                Self.logger.debug("updateEmail(to:) for user.")
                // TODO: try await currentUser.sendEmailVerification(beforeUpdatingEmail: userId) (show in UI that they need to accept!)
                try await currentUser.updateEmail(to: userId)
            }

            if let password = modifications.modifiedDetails.password {
                Self.logger.debug("updatePassword(to:) for user.")
                try await currentUser.updatePassword(to: password)
            }

            if let name = modifications.modifiedDetails.name {
                try await updateDisplayName(of: currentUser, name)
            }

            // None of the above requests will trigger our state change listener, therefore, we just call it manually.
            try await context.notifyUserSignIn(user: currentUser)
        } catch let error as NSError {
            Self.logger.error("Received NSError on firebase dispatch: \(error)")
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            Self.logger.error("Received error on firebase dispatch: \(error)")
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private func updateDisplayName(of user: User, _ name: PersonNameComponents) async throws {
        Self.logger.debug("Creating change request for updated display name.")
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name.formatted(.name(style: .long))
        try await changeRequest.commitChanges()
    }
}


// MARK: - Sign In With Apple

extension FirebaseAccountConfiguration {
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

            try await signupWithCredential(credential)
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

        onAppleSignInRequest(request: request)

        guard let result = try await performRequest(request),
              case let .appleID(credential) = result else {
            return nil
        }

        guard lastNonce != nil else {
            Self.logger.error("onAppleSignInCompletion was received though no login request was found.")
            throw FirebaseAccountError.setupError
        }

        return credential
    }

    private func performRequest(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationResult? {
        guard let authorizationController = firebaseModel.authorizationController else {
            Self.logger.error("Failed to perform AppleID request. We are missing access to the AuthorizationController.")
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
