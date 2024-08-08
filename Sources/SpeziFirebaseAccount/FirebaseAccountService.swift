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
import SpeziLocalStorage
import SpeziSecureStorage
import SpeziValidation
import SwiftUI


private enum UserChange {
    case user(_ user: User)
    case removed
}


private struct UserUpdate {
    let change: UserChange
    var authResult: AuthDataResult?
}


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
public final class FirebaseAccountService: AccountService { // swiftlint:disable:this type_body_length
    private static let supportedAccountKeys = AccountKeyCollection {
        \.accountId
        \.userId
        \.password
        \.name
    }

    // TODO: update all docs!
    @Application(\.logger)
    private var logger

    @Dependency private var configureFirebaseApp = ConfigureFirebaseApp()
    @Dependency private var localStorage = LocalStorage()
    @Dependency private var secureStorage = SecureStorage()

    @Dependency(Account.self)
    private var account
    @Dependency(AccountNotifications.self)
    private var notifications
    @Dependency(ExternalAccountStorage.self)
    private var externalStorage


    public let configuration: AccountServiceConfiguration
    private let emulatorSettings: (host: String, port: Int)?

    @IdentityProvider(section: .primary)
    private var loginWithPassword = FirebaseLoginView()
    @IdentityProvider(enabled: false)
    private var anonymousSignup = FirebaseAnonymousSignInButton()
    @IdentityProvider(section: .singleSignOn)
    private var signInWithApple = FirebaseSignInWithAppleButton()

    @SecurityRelatedModifier private var emailPasswordReauth = ReauthenticationAlertModifier()

    @Model private var firebaseModel = FirebaseAccountModel()
    @Modifier private var firebaseModifier = FirebaseAccountModifier()

    @MainActor private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    @MainActor private var lastNonce: String?

    // dispatch of user updates
    private var shouldQueue = false
    private var isConfiguring = false
    private var queuedUpdate: UserUpdate?


    private var unsupportedKeys: AccountKeyCollection {
        var unsupportedKeys = account.configuration.keys
        unsupportedKeys.removeAll(Self.supportedAccountKeys)
        return unsupportedKeys
    }

    /// - Parameters:
    ///   - providers: The authentication methods that should be supported.
    ///   - emulatorSettings: The emulator settings. The default value is `nil`, connecting the FirebaseAccount module to the Firebase Auth cloud instance.
    ///   - passwordValidation: Override the default password validation rule. By default firebase enforces a minimum length of 6 characters.
    public init(
        providers: FirebaseAuthProviders,
        emulatorSettings: (host: String, port: Int)? = nil,
        passwordValidation: [ValidationRule]? = nil // swiftlint:disable:this discouraged_optional_collection
    ) {
        self.emulatorSettings = emulatorSettings

        self.configuration = AccountServiceConfiguration(supportedKeys: .exactly(Self.supportedAccountKeys)) {
            RequiredAccountKeys {
                \.userId
                if providers.contains(.emailAndPassword) {
                    \.password
                }
            }

            UserIdConfiguration.emailAddress
            FieldValidationRules(for: \.userId, rules: .minimalEmail)
            FieldValidationRules(for: \.password, rules: passwordValidation ?? [.minimumFirebasePassword])
        }

        if !providers.contains(.emailAndPassword) {
            $loginWithPassword.isEnabled = false
        }
        if !providers.contains(.signInWithApple) {
            $signInWithApple.isEnabled = false
        }
        if providers.contains(.anonymousButton) {
            $anonymousSignup.isEnabled = true
        }
    }

    public func configure() {
        if let emulatorSettings {
            Auth.auth().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }

        isConfiguring = true
        defer {
            isConfiguring = false
        }

        // get notified about changes of the User reference
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            guard let self else {
                return
            }

            if isConfiguring {
                // We can safely assume main actor isolation, see
                // https://firebase.google.com/docs/reference/swift/firebaseauth/api/reference/Classes/Auth#/c:@M@FirebaseAuth@objc(cs)FIRAuth(im)addAuthStateDidChangeListener:
                let skip = MainActor.assumeIsolated {
                    // Ensure that there are details associated as soon as possible.
                    // Mark them as incomplete if we know there might be account details that are stored externally,
                    // we update the details later anyways, even if we might be wrong.
                    if let user {
                        var details = self.buildUser(user, isNewUser: false)
                        details.isIncomplete = !self.unsupportedKeys.isEmpty

                        self.logger.debug("Supply initial user details of associated Firebase account.")
                        self.account.supplyUserDetails(details)
                        return !details.isIncomplete
                    } else {
                        self.account.removeUserDetails()
                        return true
                    }
                }

                guard !skip else {
                    // don't spin of the task below if we know it wouldn't change anything.
                    return
                }
            }


            Task {
                do {
                    try await self.stateDidChangeListener(auth: auth, user: user)
                } catch {
                    self.logger.error("Failed to apply FirebaseAuth stateDidChangeListener: \(error)")
                }
            }
        }

        // if there is a cached user, we refresh the authentication token
        Auth.auth().currentUser?.getIDTokenForcingRefresh(true) { _, error in
            if let error {
                let code = AuthErrorCode(_nsError: error as NSError)

                guard code.code != .networkError else {
                    return // we make sure that we don't remove the account when we don't have network (e.g., flight mode)
                }

                // TODO: can we assume main actor?
                Task {
                    self.notifyUserRemoval()
                }
            }
        }

        Task.detached { [logger, secureStorage, localStorage] in
            // Previous SpeziFirebase releases used to store an identifier for the active account service on disk.
            // We keep this for now, to clear the keychain of all users.
            Self.resetLegacyStorage(secureStorage, localStorage, logger)
        }

        let subscription = externalStorage.updatedDetails
        Task { [weak self] in
            for await updatedDetails in subscription {
                guard let self else {
                    return
                }

                await handleUpdatedDetailsFromExternalStorage(for: updatedDetails.accountId, details: updatedDetails.details)
            }
        }
    }

    private func handleUpdatedDetailsFromExternalStorage(for accountId: String, details: AccountDetails) async {
        guard let user = Auth.auth().currentUser else {
            return
        }

        // TODO: make sure we do not interrupt! anything? (e.g. shouldQueue is true?)
        // TODO: semaphore on the withFirebaseAction?

        let details = buildUser(user, isNewUser: false, mergeWith: details)
        logger.debug("Update user details due to updates in the externally stored account details.")
        account.supplyUserDetails(details)
    }

    public func login(userId: String, password: String) async throws { // TODO: do all docs
        logger.debug("Received new login request...")

        try await dispatchFirebaseAuthAction { @MainActor in
            try await Auth.auth().signIn(withEmail: userId, password: password)
            logger.debug("signIn(withEmail:password:)")
        }
    }

    // TODO: expose methods for email verification?

    public func signUpAnonymously() async throws {
        try await dispatchFirebaseAuthAction {
            try await Auth.auth().signInAnonymously()
        }
    }

    public func signUp(with signupDetails: AccountDetails) async throws {
        logger.debug("Received new signup request...")

        guard let password = signupDetails.password else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await dispatchFirebaseAuthAction { @MainActor in
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: signupDetails.userId, password: password)
                logger.debug("Linking email-password credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                if let displayName = signupDetails.name {
                    try await updateDisplayName(of: result.user, displayName)
                }

                try await requestExternalStorage(for: result.user.uid, details: signupDetails)
                try await notifyUserSignIn(user: result.user)
                return result
            }

            let authResult = try await Auth.auth().createUser(withEmail: signupDetails.userId, password: password)
            logger.debug("createUser(withEmail:password:) for user.")

            logger.debug("Sending email verification link now...")
            try await authResult.user.sendEmailVerification()

            if let displayName = signupDetails.name {
                try await updateDisplayName(of: authResult.user, displayName)
            }

            try await requestExternalStorage(for: authResult.user.uid, details: signupDetails)

            return authResult
        }
    }

    public func signup(with credential: OAuthCredential) async throws {
        try await dispatchFirebaseAuthAction { @MainActor in
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                logger.debug("Linking oauth credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                try await notifyUserSignIn(user: currentUser, isNewUser: true)

                return result
            }

            let authResult = try await Auth.auth().signIn(with: credential)
            logger.debug("signIn(with:) credential for user.")

            // nothing to store externally

            return authResult
        }
    }

    public func resetPassword(userId: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: userId)
            logger.debug("sendPasswordReset(withEmail:) for user.")
        } catch let error as NSError {
            let firebaseError = FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
            if case .invalidCredentials = firebaseError {
                return // make sure we don't leak any information
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
                notifyUserRemoval()
                return
            } else {
                throw FirebaseAccountError.notSignedIn
            }
        }

        try await dispatchFirebaseAuthAction { @MainActor in
            try Auth.auth().signOut()
            try await Task.sleep(for: .milliseconds(10))
            logger.debug("signOut() for user.")
        }
    }

    public func delete() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if account.signedIn {
                notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        try await notifications.reportEvent(.deletingAccount(currentUser.uid))

        try await dispatchFirebaseAuthAction { @MainActor in
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
                notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        do {
            // if we modify sensitive credentials and require a recent login
            if modifications.modifiedDetails.contains(AccountKeys.userId) || modifications.modifiedDetails.password != nil {
                let result = try await reauthenticateUser(user: currentUser)
                guard case .success = result else {
                    logger.debug("Re-authentication was cancelled. Not updating sensitive user details.")
                    return // got cancelled!
                }
            }

            if modifications.modifiedDetails.contains(AccountKeys.userId) {
                logger.debug("updateEmail(to:) for user.")
                try await currentUser.updateEmail(to: modifications.modifiedDetails.userId)
            }

            if let password = modifications.modifiedDetails.password {
                logger.debug("updatePassword(to:) for user.")
                try await currentUser.updatePassword(to: password)
            }

            if let name = modifications.modifiedDetails.name {
                try await updateDisplayName(of: currentUser, name)
            }

            var externalModifications = modifications
            externalModifications.removeModifications(for: Self.supportedAccountKeys)
            if !externalModifications.isEmpty {
                let externalStorage = externalStorage
                try await externalStorage.updateExternalStorage(with: externalModifications, for: currentUser.uid)
            }

            // None of the above requests will trigger our state change listener, therefore, we just call it manually.
            try await notifyUserSignIn(user: currentUser)
        } catch let error as NSError {
            logger.error("Received NSError on firebase dispatch: \(error)")
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            logger.error("Received error on firebase dispatch: \(error)")
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private func reauthenticateUser(user: User) async throws -> ReauthenticationOperation {
        // we just prefer apple for simplicity, and because for the delete operation we need to token to revoke it
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

@MainActor
extension FirebaseAccountService {
    func onAppleSignInRequest(request: ASAuthorizationAppleIDRequest) {
        let nonce = CryptoUtils.randomNonceString(length: 32)
        // we configured userId as `required` in the account service
        var requestedScopes: [ASAuthorization.Scope] = [.email]

        let nameRequirement = account.configuration.name?.requirement
        if nameRequirement == .required { // .collected names will be collected later-on
            requestedScopes.append(.fullName)
        }

        request.nonce = CryptoUtils.sha256(nonce)
        request.requestedScopes = requestedScopes

        self.lastNonce = nonce // save the nonce for later use to be passed to FirebaseAuth
    }

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

            try await signup(with: credential)
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


@MainActor
extension FirebaseAccountService {
    private static nonisolated func resetLegacyStorage(_ secureStorage: SecureStorage, _ localStorage: LocalStorage, _ logger: Logger) {
        do {
            try secureStorage.deleteCredentials("_", server: StorageKeys.activeAccountService)
        } catch SecureStorageError.notFound {
            // we don't care if we want to delete something that doesn't exist
        } catch {
            logger.error("Failed to remove active account service: \(error)")
        }

        // we don't care if removal of the legacy item fails
        try? localStorage.delete(storageKey: StorageKeys.activeAccountService)
    }

    // a overload that just returns void
    func dispatchFirebaseAuthAction(
        action: @Sendable () async throws -> Void
    ) async throws {
        // TODO: use async semaphore here!
        try await self.dispatchFirebaseAuthAction {
            try await action()
            return nil
        }
    }

    /// Dispatch a firebase auth action.
    ///
    /// This method will make sure, that the result of a firebase auth command (e.g. resulting in a call of the state change
    /// delegate) will be waited for and executed on the same thread. Therefore, any errors thrown in the event handler
    /// can be forwarded back to the caller.
    /// - Parameters:
    ///   - service: The service that is calling this method.
    ///   - action: The action. If you doing an authentication action, return the auth data result. This way
    ///     we can forward additional information back to SpeziAccount.
    @_disfavoredOverload
    func dispatchFirebaseAuthAction(
        action: @Sendable () async throws -> AuthDataResult?
    ) async throws {
        defer {
            shouldQueue = false
        }

        shouldQueue = true

        do {
            let result = try await action()

            try await dispatchQueuedChanges(result: result)
        } catch let error as NSError {
            logger.error("Received NSError on firebase dispatch: \(error)")
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            logger.error("Received error on firebase dispatch: \(error)")
            throw FirebaseAccountError.unknown(.internalError)
        }
    }


    private func stateDidChangeListener(auth: Auth, user: User?) async throws {
        // this is called by the FIRAuth framework.

        let change: UserChange
        if let user {
            change = .user(user)
        } else {
            change = .removed
        }

        let update = UserUpdate(change: change)

        if shouldQueue {
            logger.debug("Received FirebaseAuth stateDidChange that is queued to be dispatched in active call.")
            self.queuedUpdate = update
        } else {
            logger.debug("Received FirebaseAuth stateDidChange that that was triggered due to other reasons. Dispatching anonymously...")

            // just apply update out of band, errors are just logged as we can't throw them somewhere where UI pops up
            try await apply(update: update)
        }
    }

    private func dispatchQueuedChanges(result: AuthDataResult? = nil) async throws {
        shouldQueue = false

        guard var queuedUpdate else {
            return
        }

        self.queuedUpdate = nil

        if let result { // patch the update before we apply it
            queuedUpdate.authResult = result
        }

        try await apply(update: queuedUpdate)
    }

    private func apply(update: UserUpdate) async throws {
        switch update.change {
        case let .user(user):
            let isNewUser = update.authResult?.additionalUserInfo?.isNewUser ?? false
            try await notifyUserSignIn(user: user, isNewUser: isNewUser)
        case .removed:
            notifyUserRemoval()
        }
    }

    private func buildUser(_ user: User, isNewUser: Bool, mergeWith additionalDetails: AccountDetails? = nil) -> AccountDetails {
        var details = AccountDetails()
        details.accountId = user.uid
        if let email = user.email {
            details.userId = email // userId will fallback to accountId if not present
        }

        // flags
        details.isNewUser = isNewUser
        details.isVerified = user.isEmailVerified
        details.isAnonymous = user.isAnonymous

        // metadata
        details.creationDate = user.metadata.creationDate
        details.lastSignInDate = user.metadata.lastSignInDate

        if let displayName = user.displayName,
           let nameComponents = try? PersonNameComponents(displayName, strategy: .name) {
            // we wouldn't be here if we couldn't create the person name components from the given string
            details.name = nameComponents
        }

        if let additionalDetails {
            details.add(contentsOf: additionalDetails)
        }

        return details
    }

    private func buildUserQueryingStorageProvider(user: User, isNewUser: Bool) async throws -> AccountDetails {
        var details = buildUser(user, isNewUser: isNewUser)

        let unsupportedKeys = unsupportedKeys
        if !unsupportedKeys.isEmpty {
            let externalStorage = externalStorage
            let externalDetails = try await externalStorage.retrieveExternalStorage(for: details.accountId, unsupportedKeys)
            details.add(contentsOf: externalDetails)
        }

        return details
    }

    func notifyUserSignIn(user: User, isNewUser: Bool = false) async throws {
        let details = try await buildUserQueryingStorageProvider(user: user, isNewUser: isNewUser)

        logger.debug("Notifying SpeziAccount with updated user details.")
        account.supplyUserDetails(details)
    }

    func notifyUserRemoval() {
        logger.debug("Notifying SpeziAccount of removed user details.")

        let account = account
        account.removeUserDetails()
    }

    private func requestExternalStorage(for accountId: String, details: AccountDetails) async throws {
        var externallyStoredDetails = details
        externallyStoredDetails.removeAll(Self.supportedAccountKeys)
        guard !externallyStoredDetails.isEmpty else {
            return
        }

        let externalStorage = externalStorage
        try await externalStorage.requestExternalStorage(of: externallyStoredDetails, for: accountId)
    }
}

// swiftlint:disable:this file_length
