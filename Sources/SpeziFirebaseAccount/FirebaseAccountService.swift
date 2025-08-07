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
import SpeziFoundation
import SpeziKeychainStorage
import SpeziLocalStorage
import SpeziValidation
import SwiftUI


private enum InitialUserState {
    case unknown
    case notPresent
    case present(incomplete: Bool)

    /// Check if the state of the authStateDidChange handler is the same as we observed initially.
    func canSkipStateChange(for user: User?) -> Bool {
        switch self {
        case .unknown:
            false
        case .notPresent:
            user == nil
        case .present(let incomplete):
            !incomplete && user != nil
        }
    }
}


private enum UserChange {
    case user(_ user: User)
    case removed
}


private struct UserUpdate {
    static var removed: UserUpdate {
        UserUpdate(change: .removed)
    }

    let change: UserChange
    var authResult: AuthDataResult?


    init(change: UserChange, authResult: AuthDataResult? = nil) {
        self.change = change
        self.authResult = authResult
    }

    init(from authResult: AuthDataResult) {
        self.change = .user(authResult.user)
        self.authResult = authResult
    }

    func describesSameUpdate(as update: UserUpdate) -> Bool {
        switch (change, update.change) {
        case (.removed, .removed):
            true
        case let (.user(lhs), .user(rhs)):
            lhs.uid == rhs.uid
        default:
            false
        }
    }
}


/// Configures an `AccountService` that interacts with Firebase Auth.
///
/// 
/// Configure the account service using the
/// [`AccountConfiguration`](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountconfiguration).
///
/// ```swift
/// import SpeziAccount
/// import SpeziFirebaseAccount
///
/// class ExampleAppDelegate: SpeziAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             AccountConfiguration(
///                 service: FirebaseAccountService()
///                 configuration: [/* ... */]
///             )
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Configuration
///
/// - ``init(providers:emulatorSettings:passwordValidation:)``
///
/// ### Signup
/// - ``signUpAnonymously()``
/// - ``signUp(with:)-6qeht``
/// - ``signUp(with:)-1jtx6``
///
/// ### Login
/// - ``login(userId:password:)``
///
/// ### Modifications
/// - ``updateAccountDetails(_:)``
///
/// ### Password Reset
/// - ``resetPassword(userId:)``
///
/// ### Logout & Deletion
/// - ``logout()``
/// - ``delete()``
///
/// ### Presenting the security alert
/// - ``securityAlert``
/// - ``FirebaseSecurityAlert``
@MainActor
public final class FirebaseAccountService: AccountService { // swiftlint:disable:this type_body_length
    private static let supportedAccountKeys = AccountKeyCollection {
        \.accountId
        \.userId
        \.password
        \.name
    }

    @Application(\.logger)
    private var logger

    @Dependency(ConfigureFirebaseApp.self)
    private var configureFirebaseApp
    @Dependency(LocalStorage.self)
    private var localStorage
    @Dependency(KeychainStorage.self)
    private var keychainStorage

    @Dependency(Account.self)
    private var account
    @Dependency(AccountNotifications.self)
    private var notifications
    @Dependency(ExternalAccountStorage.self)
    private var externalStorage


    @_documentation(visibility: internal)
    public let configuration: AccountServiceConfiguration
    private let emulatorSettings: (host: String, port: Int)?

    @IdentityProvider(section: .primary)
    private var loginWithPassword = FirebaseLoginView()
    @IdentityProvider(enabled: false)
    private var anonymousSignup = FirebaseAnonymousSignInButton()
    @IdentityProvider(section: .singleSignOn)
    private var signInWithApple = FirebaseSignInWithAppleButton()

    /// Security alert to authorize security sensitive operations.
    ///
    /// This view modifier injects an alert into the view hierarchy that will present an alert, if the account service requests to re-authenticate the
    /// user for security-sensitive operations. This modifier is automatically injected in SpeziAccount-related views.
    @SecurityRelatedModifier public var securityAlert = FirebaseSecurityAlert()

    @Model private var firebaseModel = FirebaseAccountModel()
    @Modifier private var firebaseModifier = FirebaseAccountModifier()

    @MainActor private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?
    @MainActor private var lastNonce: String?

    private var shouldQueue = false
    private var queuedUpdates: [UserUpdate] = []
    private var actionSemaphore = AsyncSemaphore()
    private var initiallyObservedState: InitialUserState = .unknown


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

    @_documentation(visibility: internal)
    public func configure() {
        if let emulatorSettings {
            Auth.auth().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }

        // get notified about changes of the User reference
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            // We could safely assume main actor isolation here, see
            // https://firebase.google.com/docs/reference/swift/firebaseauth/api/reference/Classes/Auth#/c:@M@FirebaseAuth@objc(cs)FIRAuth(im)addAuthStateDidChangeListener:
            self?.handleStateDidChange(auth: auth, user: user)
        }

        // if there is a cached user, we refresh the authentication token
        Auth.auth().currentUser?.getIDTokenForcingRefresh(true) { _, error in
            if let error {
                guard (error as NSError).code != AuthErrorCode.networkError.rawValue else {
                    return // we make sure that we don't remove the account when we don't have network (e.g., flight mode)
                }

                // guaranteed to be invoked on the main thread, see
                // https://firebase.google.com/docs/reference/swift/firebaseauth/api/reference/Classes/User#getidtokenforcingrefresh_:completion:
                MainActor.assumeIsolated {
                    self.notifyUserRemoval()
                }
            }
        }

        // Firebase v11.6.0 restore the v10 behavior where the currentUser is available immediately after startup.
        // `currentUser` will sync to the Auth worker queue, see https://github.com/firebase/firebase-ios-sdk/pull/14141.
        // The Auth.init kicked off loading the current user already above, so we might not need to wait that long here.
        // But, if there is a user, it will definitely get loaded here.
        checkForInitialUserAccount()

        Task.detached { [logger, keychainStorage, localStorage] in
            // Previous SpeziFirebase releases used to store an identifier for the active account service on disk.
            // We keep this for now, to clear the keychain of all users.
            Self.resetLegacyStorage(keychainStorage, localStorage, logger)
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

    /// Login user with userId and password credentials.
    /// - Parameters:
    ///   - userId: The user id. Typically the email used with the firebase account.
    ///   - password: The user's password.
    /// - Throws: Throws an ``FirebaseAccountError`` if the operation fails.
    public func login(userId: String, password: String) async throws {
        logger.debug("Received new login request ...")
        try ensureSignedOutBeforeLogin()

        try await dispatchFirebaseAuthAction { @MainActor in
            let result = try await Auth.auth().signIn(withEmail: userId, password: password)
            logger.debug("Successfully returned from Auth/signIn(withEmail:password:)")
            return result
        }
    }

    /// Sign in with an anonymous user account.
    /// - Throws: Throws an ``FirebaseAccountError`` if the operation fails.
    public func signUpAnonymously() async throws {
        logger.debug("Signing up anonymously ...")
        try ensureSignedOutBeforeLogin()

        try await dispatchFirebaseAuthAction {
            let result = try await Auth.auth().signInAnonymously()
            logger.debug("Successfully signed up anonymously ...")
            return result
        }
    }

    /// Sign up with userId and password credentials and additional user details.
    ///
    /// - Parameter signupDetails: The `AccountDetails` that must contain a **userId** and a **password**.
    /// - Throws: Trows an ``FirebaseAccountError`` if the operation fails. A ``FirebaseAccountError/invalidCredentials`` is thrown if
    ///  the `userId` or `password` keys are not present.
    public func signUp(with signupDetails: AccountDetails) async throws {
        logger.debug("Received new signup request with details ...")
        try ensureSignedOutBeforeLogin()

        guard let password = signupDetails.password, signupDetails.contains(AccountKeys.userId) else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await dispatchFirebaseAuthAction { @MainActor in
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                // The link call below resets the display name to nil. Therefore, we need to preserve the existing name if possible.
                let previousDisplayName = currentUser.displayName

                let credential = EmailAuthProvider.credential(withEmail: signupDetails.userId, password: password)
                logger.debug("Linking email-password credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                if let displayName = signupDetails.name {
                    try await updateDisplayName(of: currentUser, displayName)
                } else if let previousDisplayName {
                    try await updateDisplayName(of: currentUser, previousDisplayName)
                }

                try await requestExternalStorage(for: currentUser.uid, details: signupDetails)

                return result
            }

            let authResult = try await Auth.auth().createUser(withEmail: signupDetails.userId, password: password)
            logger.debug("createUser(withEmail:password:) for user.")

            logger.debug("Sending email verification link now...")
            do {
                try await authResult.user.sendEmailVerification()
            } catch {
                // failing to send email should not fail signup. Signup UI should have a "resend E-Mail" button
                logger.error("Failed to send email verification: \(error)")
            }

            if let displayName = signupDetails.name {
                try await updateDisplayName(of: authResult.user, displayName)
            }

            try await requestExternalStorage(for: authResult.user.uid, details: signupDetails)

            return authResult
        }
    }

    /// Sign up with an O-Auth credential.
    ///
    /// Sign up with an O-Auth credential, like one received from Sign in with Apple.
    /// - Parameter credential: The o-auth credential.
    /// - Throws: Throws an ``FirebaseAccountError`` if the operation fails.
    public func signUp(with credential: OAuthCredential) async throws {
        logger.debug("Received new signup request with OAuth credential ...")
        try ensureSignedOutBeforeLogin()

        try await dispatchFirebaseAuthAction { @MainActor in
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                // The link call below resets the display name to nil (if non is part of the OAuth credential).
                // Therefore, we need to preserve the existing name if possible.
                let previousDisplayName = currentUser.displayName

                logger.debug("Linking O-Auth credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                if let previousDisplayName, result.user.displayName == nil {
                    try await updateDisplayName(of: currentUser, previousDisplayName)
                }

                return result
            }

            let authResult = try await Auth.auth().signIn(with: credential)
            logger.debug("Successfully returned from Auth/signIn(with:).")

            // nothing to store externally

            return authResult
        }
    }

    private func ensureSignedOutBeforeLogin() throws {
        // We don't bother to notify SpeziAccount. This method is called when we attempt to associate a new user.
        // We will update SpeziAccount with a new user anyways.
        if let user = Auth.auth().currentUser, !user.isAnonymous {
            logger.debug("Found existing user associated. Performing signOut() first ...")
            try mapFirebaseAccountError {
                try Auth.auth().signOut()
            }
        }
    }

    public func resetPassword(userId: String) async throws {
        do {
            try await mapFirebaseAccountError {
                try await Auth.auth().sendPasswordReset(withEmail: userId)
                logger.debug("sendPasswordReset(withEmail:) for user.")
            }
        } catch FirebaseAccountError.invalidCredentials {
            return // make sure we don't leak any information
        }
    }

    /// Logout the current user.
    /// - Throws: Throws an ``FirebaseAccountError`` if the operation fails. A ``FirebaseAccountError/notSignedIn`` is thrown if logout
    ///     is called when no user was logged in.
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
            logger.debug("Successful signOut() for user.")
            return .removed
        }
    }

    /// Delete the current user and all associated data.
    ///
    /// This will notify external storage provider to delete the account data associated with the current user account.
    /// - Important: A re-authentication is required, when requesting to delete the account. This is automatically done through the a Single-Sign-On provider if available.
    ///   Otherwise, an alert will be presented to enter the password credential. Make sure that the ``securityAlert`` modifier is injected from the point your are calling
    ///   this method. This is automatically done with native SpeziAccount views.
    ///
    /// - Throws: Throws an ``FirebaseAccountError`` if the operation fails. A ``FirebaseAccountError/notSignedIn`` is thrown if delete
    ///     is called when no user was logged in.
    public func delete() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if account.signedIn {
                notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        try await notifications.reportEvent(.deletingAccount(currentUser.uid))

        let result = try await reauthenticateUser(user: currentUser) // delete requires a recent sign in
        guard case .success = result else {
            logger.debug("Re-authentication was cancelled by user. Not deleting the account.")
            throw CancellationError()
        }

        try await dispatchFirebaseAuthAction { @MainActor in
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
                    if error.code != AuthErrorCode.invalidCredential.rawValue {
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

            return .removed
        }
    }

    /// Apply modifications to the current user account.
    ///
    /// This method applies modifications to the current user account details. Modifications will be automatically forwarded to the external storage provider for
    /// keys not supported by Firebase Auth.
    ///
    /// - Important: A re-authentication is required, when changing security-sensitive account details (like userId or password).
    ///   This is automatically done through the a Single-Sign-On provider if available.
    ///   Otherwise, an alert will be presented to enter the password credential. Make sure that the ``securityAlert`` modifier is injected from the point your are calling
    ///   this method. This is automatically done with native SpeziAccount views.
    ///
    /// - Throws: Throws an ``FirebaseAccountError`` if the operation fails. A ``FirebaseAccountError/notSignedIn`` is thrown if delete
    ///     is called when no user was logged in.
    public func updateAccountDetails(_ modifications: AccountModifications) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if account.signedIn {
                notifyUserRemoval()
            }
            throw FirebaseAccountError.notSignedIn
        }

        // if we modify sensitive credentials and require a recent login
        if modifications.modifiedDetails.contains(AccountKeys.userId) || modifications.modifiedDetails.password != nil {
            let result = try await reauthenticateUser(user: currentUser)
            guard case .success = result else {
                logger.debug("Re-authentication was cancelled. Not updating sensitive user details.")
                throw CancellationError()
            }
        }

        try await mapFirebaseAccountError {
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
        }

        var externalModifications = modifications
        externalModifications.removeModifications(for: Self.supportedAccountKeys)
        if !externalModifications.isEmpty {
            try await externalStorage.updateExternalStorage(with: externalModifications, for: currentUser.uid)
        }

        // None of the above requests will trigger our state change listener, therefore, we just call it manually.
        await notifyUserSignIn(user: currentUser)
    }

    private func reauthenticateUser(user: User) async throws -> ReauthenticationOperation {
        // we just prefer apple for simplicity, and because for the delete operation we need to token to revoke it
        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            try await reauthenticateUserApple(user: user)
        } else if user.providerData.contains(where: { $0.providerID == "password" }) {
            try await reauthenticateUserPassword(user: user)
        } else {
            logger.error("Tried to re-authenticate but couldn't find a supported provider, found: \(user.providerData)")
            throw FirebaseAccountError.unsupportedProvider
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
        _ = try await mapFirebaseAccountError {
            try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: userId, password: password))
        }
        return .success
    }

    private func reauthenticateUserApple(user: User) async throws -> ReauthenticationOperation {
        guard let appleIdCredential = try await requestAppleSignInCredential() else {
            return .cancelled
        }

        let credential = try oAuthCredential(from: appleIdCredential)
        logger.debug("Re-Authenticating Apple credential ...")
        _ = try await mapFirebaseAccountError {
            try await user.reauthenticate(with: credential)
        }

        return .success(with: appleIdCredential)
    }

    private func updateDisplayName(of user: User, _ name: PersonNameComponents) async throws {
        try await updateDisplayName(of: user, name.formatted(.name(style: .long)))
    }

    private func updateDisplayName(of user: User, _ name: String) async throws {
        logger.debug("Creating change request for updated display name.")
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
    }
}

// MARK: - Listener and Handler

extension FirebaseAccountService {
    @MainActor
    private func checkForInitialUserAccount() {
        guard let user = Auth.auth().currentUser else {
            initiallyObservedState = .notPresent
            logger.debug("There is no existing Firebase account.")
            return
        }

        // Ensure that there are details associated as soon as possible.
        // Mark them as incomplete if we know there might be account details that are stored externally,
        // we update the details later anyways, even if we might be wrong.

        var details = buildUser(user, isNewUser: false)
        details.isIncomplete = !self.unsupportedKeys.isEmpty

        logger.debug("Found existing Firebase account. Supplying initial user details of associated Firebase account.")
        account.supplyUserDetails(details)
        initiallyObservedState = .present(incomplete: details.isIncomplete)
    }

    @MainActor
    private func handleStateDidChange(auth: Auth, user: User?) {
        if initiallyObservedState.canSkipStateChange(for: user) {
            initiallyObservedState = .unknown
            logger.debug("Skipping the initial stateDidChange handler once. User is \(user == nil ? "not " : "")associated.")
            return
        }

        Task {
            await handleUpdatedUserState(user: user)
        }
    }

    private func handleUpdatedDetailsFromExternalStorage(for accountId: String, details: AccountDetails) async {
        guard let user = Auth.auth().currentUser else {
            return
        }

        do {
            try await actionSemaphore.waitCheckingCancellation()
        } catch {
            return
        }

        defer {
            actionSemaphore.signal()
        }

        // make sure to keep the `newUser` flag
        let consideredNewUser = account.details?.isNewUser ?? false

        let details = buildUser(user, isNewUser: consideredNewUser, mergeWith: details)
        logger.debug("Update user details due to updates in the externally stored account details.")
        account.supplyUserDetails(details)
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

    func onAppleSignInCompletion(result: Result<ASAuthorization, any Error>) async throws {
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

            try await signUp(with: credential)
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

// MARK: - Infrastructure

@MainActor
extension FirebaseAccountService {
    private static nonisolated func resetLegacyStorage(_ keychainStorage: KeychainStorage, _ localStorage: LocalStorage, _ logger: Logger) {
        do {
            try keychainStorage.deleteCredentials(
                withUsername: "_",
                for: .internetPassword(forServer: StorageKeys.activeAccountService)
            )
        } catch {
            logger.error("Failed to remove active account service: \(error)")
        }

        // we don't care if removal of the legacy item fails
        try? localStorage.delete(LocalStorageKey<Never>(StorageKeys.activeAccountService))
    }

    // a overload that just returns void
    private func dispatchFirebaseAuthAction(action: () async throws -> Void) async throws {
        try await self._dispatchFirebaseAuthAction {
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
    private func dispatchFirebaseAuthAction(action: () async throws -> AuthDataResult) async throws {
        try await _dispatchFirebaseAuthAction {
            try await UserUpdate(from: action())
        }
    }

    @_disfavoredOverload
    private func dispatchFirebaseAuthAction(action: () async throws -> UserUpdate) async throws {
        try await _dispatchFirebaseAuthAction(action: action)
    }

    private func _dispatchFirebaseAuthAction(
        action: () async throws -> UserUpdate?
    ) async throws {
        shouldQueue = true
        defer {
            shouldQueue = false
        }

        try await actionSemaphore.waitCheckingCancellation()
        defer {
            actionSemaphore.signal()
        }

        let update = try await mapFirebaseAccountError(action: action)
        await dispatchQueuedChanges(update: update)
    }

    private func mapFirebaseAccountError<T: Sendable>(action: () async throws -> T) async rethrows -> T {
        do {
            return try await action()
        } catch {
            try _firebaseAccountMapError(error)
        }
    }

    private func mapFirebaseAccountError<T>(action: () throws -> T) rethrows -> T {
        do {
            return try action()
        } catch {
            try _firebaseAccountMapError(error)
        }
    }

    private func _firebaseAccountMapError(_ error: any Error) throws -> Never {
        logger.error("Received error on firebase dispatch: \(error)")
        let nsError = error as NSError
        if nsError.domain == AuthErrors.domain,
           let code = AuthErrorCode(rawValue: nsError.code) {
            throw FirebaseAccountError(authErrorCode: code)
        }
        throw error
    }


    private func handleUpdatedUserState(user: User?) async {
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
            queuedUpdates.append(update)
        } else {
            logger.debug("Received FirebaseAuth stateDidChange that that was triggered due to other reasons. Dispatching anonymously...")

            // just apply update out of band, errors are just logged as we can't throw them somewhere where UI pops up
            await apply(update)
        }
    }

    private func dispatchQueuedChanges(update: UserUpdate? = nil) async {
        defer {
            shouldQueue = false
        }

        // apply all queued updates
        while let queuedUpdate = queuedUpdates.first {
            queuedUpdates.removeFirst()
            if let update, queuedUpdate.describesSameUpdate(as: update) {
                continue
            }

            await apply(queuedUpdate)
        }

        // we always apply the update we receive from the action
        if let update {
            await apply(update)
        }
    }

    private func apply(_ update: UserUpdate) async {
        switch update.change {
        case let .user(user):
            let wasAnonymous = account.details?.isAnonymous == true
            let isNewUser = wasAnonymous || update.authResult?.additionalUserInfo?.isNewUser ?? false

            await notifyUserSignIn(user: user, isNewUser: isNewUser)
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

    private func buildUserQueryingStorageProvider(user: User, isNewUser: Bool) async -> AccountDetails {
        var details = buildUser(user, isNewUser: isNewUser)

        let unsupportedKeys = unsupportedKeys
        if !unsupportedKeys.isEmpty {
            let externalDetails = await externalStorage.retrieveExternalStorage(for: details.accountId, unsupportedKeys)
            details.add(contentsOf: externalDetails)
        }

        return details
    }

    func notifyUserSignIn(user: User, isNewUser: Bool = false) async {
        let details = await buildUserQueryingStorageProvider(user: user, isNewUser: isNewUser)

        logger.debug("Notifying SpeziAccount with updated user details.")
        account.supplyUserDetails(details)
    }

    func notifyUserRemoval() {
        logger.debug("Notifying SpeziAccount of removed user details.")

        account.removeUserDetails()
    }

    private func requestExternalStorage(for accountId: String, details: AccountDetails) async throws {
        var externallyStoredDetails = details
        externallyStoredDetails.removeAll(Self.supportedAccountKeys)
        guard !externallyStoredDetails.isEmpty else {
            return
        }

        logger.debug("Delegating storage of additional \(externallyStoredDetails.count) account details to storage provider ...")
        try await externalStorage.requestExternalStorage(of: externallyStoredDetails, for: accountId)
    }
}

// swiftlint:disable:this file_length
