//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import FirebaseAuth
import OSLog
import Spezi
import SpeziAccount
import SpeziLocalStorage
import SpeziSecureStorage


private enum UserChange {
    case user(_ user: User)
    case removed
}

private struct UserUpdate {
    let change: UserChange
    var authResult: AuthDataResult?
}


actor FirebaseContext: Module, DefaultInitializable { // TODO: better name? no actor!
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "InternalStorage")

    @Dependency private var localStorage: LocalStorage
    @Dependency private var secureStorage: SecureStorage
    @Dependency private var account: Account

    @MainActor private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?

    // dispatch of user updates
    private var shouldQueue = false
    private var queuedUpdate: UserUpdate?


    init() {}

    @MainActor
    func configure() {
        // get notified about changes of the User reference
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] auth, user in
            guard let self else {
                return
            }
            Task {
                await self.stateDidChangeListener(auth: auth, user: user)
            }
        }

        // if there is a cached user, we refresh the authentication token
        Auth.auth().currentUser?.getIDTokenForcingRefresh(true) { _, error in
            if let error {
                let code = AuthErrorCode(_nsError: error as NSError)

                guard code.code != .networkError else {
                    return // we make sure that we don't remove the account when we don't have network (e.g., flight mode)
                }

                Task {
                    try await self.notifyUserRemoval()
                }
            }
        }

        Task {
            // Previous SpeziFirebase releases used to store an identifier for the active account service on disk.
            // We keep this for now, to clear the keychain of all users.
            await resetActiveAccountService()
        }
    }

    // a overload that just returns void
    func dispatchFirebaseAuthAction(
        action: @Sendable () async throws -> Void
    ) async throws {
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
            Self.logger.error("Received NSError on firebase dispatch: \(error)")
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            Self.logger.error("Received error on firebase dispatch: \(error)")
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private func resetActiveAccountService() {
        do {
            try secureStorage.deleteCredentials("_", server: StorageKeys.activeAccountService)
        } catch SecureStorageError.notFound {
            // we don't care if we want to delete something that doesn't exist
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

        let update = UserUpdate(change: change)

        // TODO: update some of the log messages to be less confusing!
        if shouldQueue {
            Self.logger.debug("Received stateDidChange that is queued to be dispatched in active call.")
            self.queuedUpdate = update
        } else {
            Self.logger.debug("Received stateDidChange that that was triggered due to other reasons. Dispatching anonymously...")

            // just apply update out of band, errors are just logged as we can't throw them somewhere where UI pops up // TODO: (should we try?)
            Task {
                do {
                    try await apply(update: update)
                } catch {
                    Self.logger.error("Failed to anonymously dispatch user change due to \(error)")
                }
            }
        }
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

    private func apply(update: UserUpdate) async throws {
        switch update.change {
        case let .user(user):
            let isNewUser = update.authResult?.additionalUserInfo?.isNewUser ?? false
            if user.isAnonymous {
                // We explicitly handle anonymous users on every signup and call our state change handler ourselves.
                // But generally, we don't care about anonymous users.

                // TODO: we do now! restructure this! => rename account service methods to indicate a signup or link!
                return
            }

            try await notifyUserSignIn(user: user, isNewUser: isNewUser)
        case .removed:
            try await notifyUserRemoval()
        }
    }

    func notifyUserSignIn(user: User, isNewUser: Bool = false, mergeWith additionalDetails: AccountDetails? = nil) async throws {
        guard let email = user.email else {
            Self.logger.error("Failed to associate firebase account due to missing email address.")
            throw FirebaseAccountError.invalidEmail
        }

        Self.logger.debug("Notifying SpeziAccount with updated user details.")


        var details = AccountDetails()
        details.accountId = user.uid
        details.userId = email
        details.isEmailVerified = user.isEmailVerified

        if let displayName = user.displayName,
           let nameComponents = try? PersonNameComponents(displayName, strategy: .name) {
            // we wouldn't be here if we couldn't create the person name components from the given string
            details.name = nameComponents
        }

        if let additionalDetails {
            details.add(contentsOf: additionalDetails)
        }

        let account = account
        await account.supplyUserDetails(details, isNewUser: isNewUser)
    }

    func notifyUserRemoval() async throws {
        Self.logger.debug("Notifying SpeziAccount of removed user details.")

        let account = account
        await account.removeUserDetails()
    }
}
