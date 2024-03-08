//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseAuth
import OSLog
import SpeziAccount
import SpeziLocalStorage
import SpeziSecureStorage


private enum UserChange {
    case user(_ user: User)
    case removed
}

private struct UserUpdate {
    let service: (any FirebaseAccountService)?
    let change: UserChange
    var authResult: AuthDataResult?
}


actor FirebaseContext {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "InternalStorage")

    private let localStorage: LocalStorage
    private let secureStorage: SecureStorage
    @_WeakInjectable<Account> private var account: Account

    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?

    private var lastActiveAccountServiceId: String?
    private var lastActiveAccountService: (any FirebaseAccountService)?

    // dispatch of user updates
    private var shouldQueue = false
    private var queuedUpdate: UserUpdate?


    init(local localStorage: LocalStorage, secure secureStorage: SecureStorage) {
        self.localStorage = localStorage
        self.secureStorage = secureStorage
    }


    func share(account: Account) {
        self._account.inject(account)
    }

    func setup(_ registeredServices: [any FirebaseAccountService]) {
        self.loadLastActiveAccountService()

        if let lastActiveAccountServiceId,
           let service = registeredServices.first(where: { $0.id == lastActiveAccountServiceId }) {
            self.lastActiveAccountService = service
        }

        // get notified about changes of the User reference
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener(stateDidChangeListener)

        // if there is a cached user, we refresh the authentication token
        Auth.auth().currentUser?.getIDTokenForcingRefresh(true) { _, error in
            if let error {
                let code = AuthErrorCode(_nsError: error as NSError)

                guard code.code != .networkError else {
                    return // we make sure that we don't remove the account when we don't have network (e.g., flight mode)
                }

                Task {
                    try await self.notifyUserRemoval(for: self.lastActiveAccountService)
                }
            }
        }
    }

    // a overload that just returns void
    func dispatchFirebaseAuthAction<Service: FirebaseAccountService>(
        on service: Service,
        action: () async throws -> Void
    ) async throws {
        try await self.dispatchFirebaseAuthAction(on: service) {
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
    func dispatchFirebaseAuthAction<Service: FirebaseAccountService>(
        on service: Service,
        action: () async throws -> AuthDataResult?
    ) async throws {
        defer {
            cleanupQueuedChanges()
        }

        shouldQueue = true
        setActiveAccountService(to: service)

        do {
            let result = try await action()

            try await dispatchQueuedChanges(result: result)
        } catch let error as NSError {
            Self.logger.error("Received NSError on firebase dispatch: \(error)")
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            Self.logger.error("Received error on firebase dispatch: \(error)")
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private nonisolated func removeCredentials(userId: String, server: String) {
        do {
            try secureStorage.deleteCredentials(userId, server: server)
        } catch {
            if let cocoaError = error as? CocoaError,
               cocoaError.isFileError {
                return // silence any file errors (e.g. file doesn't exist)
            }
            Self.logger.error("Failed to remove credentials: \(error)")
        }
    }

    private func setActiveAccountService(to service: any FirebaseAccountService) {
        self.lastActiveAccountServiceId = service.id
        self.lastActiveAccountService = service


        do {
            try secureStorage.store(
                credentials: Credentials(username: "_", password: service.id),
                server: StorageKeys.activeAccountService,
                removeDuplicate: true
            )
        } catch {
            Self.logger.error("Failed to store active account service: \(error)")
        }
    }

    private func loadLastActiveAccountService() {
        let id: String
        do {
            let credential = try secureStorage.retrieveCredentials("_", server: StorageKeys.activeAccountService)
            if let credential {
                id = credential.password
            } else {
                // In previous versions we used the plain local storage for the active key.
                do {
                    id = try localStorage.read(storageKey: StorageKeys.activeAccountService)
                } catch {
                    if let cocoaError = error as? CocoaError,
                       cocoaError.isFileError {
                        return // silence any file errors (e.g. file doesn't exist)
                    }
                    Self.logger.error("Failed to read last active account service from local storage: \(error)")
                    return
                }
            }
        } catch {
            Self.logger.error("Failed to retrieve last active account service from secure storage: \(error)")
            return
        }

        self.lastActiveAccountServiceId = id
    }

    private func resetActiveAccountService() {
        self.lastActiveAccountService = nil
        self.lastActiveAccountServiceId = nil

        do {
            try secureStorage.deleteCredentials("_", server: StorageKeys.activeAccountService)
        } catch {
            Self.logger.error("Failed to remove active account service: \(error)")
        }

        // we don't care if removal of the legacy item fails
        try? localStorage.delete(storageKey: StorageKeys.activeAccountService)
    }


    private func stateDidChangeListener(auth: Auth, user: User?) {
        // this is called by the FIRAuth framework.

        let change: UserChange
        if let user {
            change = .user(user)
        } else {
            change = .removed
        }

        let update = UserUpdate(service: lastActiveAccountService, change: change)

        if shouldQueue {
            Self.logger.debug("Received stateDidChange that is queued to be dispatched in active call.")
            self.queuedUpdate = update
        } else {
            Self.logger.debug("Received stateDidChange that that was triggered due to other reasons. Dispatching anonymously...")
            anonymouslyDispatch(update: update)
        }
    }

    private func cleanupQueuedChanges() {
        shouldQueue = false

        guard let queuedUpdate = self.queuedUpdate else {
            return
        }


        self.queuedUpdate = nil
        anonymouslyDispatch(update: queuedUpdate)
    }

    private func dispatchQueuedChanges(result: AuthDataResult? = nil) async throws {
        shouldQueue = false

        guard var queuedUpdate else {
            Self.logger.debug("Didn't find anything to dispatch in the queue!")
            return
        }

        self.queuedUpdate = nil

        if let result { // patch the update before we apply it
            queuedUpdate.authResult = result
        }

        try await apply(update: queuedUpdate)
    }

    private func anonymouslyDispatch(update: UserUpdate) {
        // anonymous dispatch doesn't forward the error!
        Task {
            do {
                try await apply(update: update)
            } catch {
                Self.logger.error("Failed to anonymously dispatch user change due to \(error)")
            }
        }
    }

    private func apply(update: UserUpdate) async throws {
        switch update.change {
        case let .user(user):
            let isNewUser = update.authResult?.additionalUserInfo?.isNewUser ?? false
            guard let service = update.service else {
                Self.logger.error("Failed to dispatch user update due to missing account service identifier on disk!")
                do {
                    // This typically happens if there still is a Account associated in the Keychain but the App was recently deleted.
                    // Therefore, we reset the user account to allow for easily re-authenticating with firebase.
                    try Auth.auth().signOut()
                } catch {
                    Self.logger.warning("Tried to remove local user. But Firebase signOut failed with \(error)")
                }
                throw FirebaseAccountError.setupError
            }

            try await notifyUserSignIn(user: user, for: service, isNewUser: isNewUser)
        case .removed:
            try await notifyUserRemoval(for: update.service)
        }
    }

    func notifyUserSignIn(user: User, for service: any FirebaseAccountService, isNewUser: Bool = false) async throws {
        guard let email = user.email else {
            Self.logger.error("Failed to associate firebase account due to missing email address.")
            throw FirebaseAccountError.invalidEmail
        }

        Self.logger.debug("Notifying SpeziAccount with updated user details.")

        let builder = AccountDetails.Builder()
            .set(\.accountId, value: user.uid)
            .set(\.userId, value: email)
            .set(\.isEmailVerified, value: user.isEmailVerified)

        if let displayName = user.displayName,
           let nameComponents = try? PersonNameComponents(displayName, strategy: .name) {
            // we wouldn't be here if we couldn't create the person name components from the given string
            builder.set(\.name, value: nameComponents)
        }

        let details = builder.build(owner: service)

        // Previous SpeziFirebase releases used to store the password within the keychain.
        // We keep this for now, to clear the keychain of all users.
        removeCredentials(userId: details.userId, server: StorageKeys.emailPasswordCredentials)

        try await account.supplyUserDetails(details, isNewUser: isNewUser)
    }

    func notifyUserRemoval(for service: (any FirebaseAccountService)?) async throws {
        Self.logger.debug("Notifying SpeziAccount of removed user details.")

        await account.removeUserDetails()

        resetActiveAccountService()
    }
}
