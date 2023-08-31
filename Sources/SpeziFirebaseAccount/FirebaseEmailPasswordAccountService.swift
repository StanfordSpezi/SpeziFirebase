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
import SwiftUI


private enum UserChange {
    case user(_ user: User)
    case removed
}

private struct QueueUpdate {
    let change: UserChange
}


actor FirebaseEmailPasswordAccountService: UserIdPasswordAccountService {
    private static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "AccountService")

    private static let supportedKeys = AccountKeyCollection {
        \.userId
        \.password
        \.name
    }

    static var defaultPasswordValidationRule: ValidationRule {
        guard let regex = try? Regex(#"[^\s]{8,}"#) else {
            fatalError("Invalid Password Regex in the FirebaseEmailPasswordAccountService")
        }
        
        return ValidationRule(
            regex: regex,
            message: "FIREBASE_ACCOUNT_DEFAULT_PASSWORD_RULE_ERROR",
            bundle: .module
        )
    }

    @AccountReference private var account: Account

    let configuration: AccountServiceConfiguration
    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?

    private var shouldQueue = false
    private var queuedUpdate: QueueUpdate?

    init(passwordValidationRules: [ValidationRule] = [FirebaseEmailPasswordAccountService.defaultPasswordValidationRule]) {
        self.configuration = AccountServiceConfiguration(
            name: LocalizedStringResource("FIREBASE_EMAIL_AND_PASSWORD", bundle: .atURL(from: .module)),
            supportedKeys: .exactly(Self.supportedKeys)
        ) {
            AccountServiceImage(Image(systemName: "envelope.fill"))
            RequiredAccountKeys {
                \.userId
                \.password
            }
            UserIdConfiguration(type: .emailAddress, keyboardType: .emailAddress)

            FieldValidationRules(for: \.userId, rules: .minimalEmail)
            FieldValidationRules(for: \.password, rules: passwordValidationRules)
        }
    }


    func configure() {
        authStateDidChangeListenerHandle = Auth.auth().addStateDidChangeListener(stateDidChangeListener)

        // if there is a cached user, we refresh the authentication token
        Auth.auth().currentUser?.getIDTokenForcingRefresh(true) { _, error in
            if error != nil {
                Task {
                    await self.notifyUserRemoval()
                }
            }
        }
    }

    func login(userId: String, password: String) async throws {
        Self.logger.debug("Received new login request...")

        defer {
            cleanupQueuedChanges()
        }

        shouldQueue = true

        do {
            try await Auth.auth().signIn(withEmail: userId, password: password)
            Self.logger.debug("signIn(withEmail:password:)")

            try await dispatchQueuedChanges()
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    func signUp(signupDetails: SignupDetails) async throws {
        Self.logger.debug("Received new signup request...")

        defer {
            cleanupQueuedChanges()
        }

        shouldQueue = true

        do {
            let authResult = try await Auth.auth().createUser(withEmail: signupDetails.userId, password: signupDetails.password)
            Self.logger.debug("createUser(withEmail:password:) for user.")

            Self.logger.debug("Sending email verification link now...")
            try await authResult.user.sendEmailVerification()

            if let displayName = signupDetails.name {
                Self.logger.debug("Creating change request for display name.")
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = displayName.formatted(.name(style: .medium))
                try await changeRequest.commitChanges()
            }

            try await dispatchQueuedChanges()
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    func resetPassword(userId: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: userId)
            Self.logger.debug("sendPasswordReset(withEmail:) for user.")
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    func logout() async throws {
        guard Auth.auth().currentUser != nil else {
            throw FirebaseAccountError.notSignedIn
        }

        defer {
            cleanupQueuedChanges()
        }

        shouldQueue = true

        do {
            try Auth.auth().signOut()
            Self.logger.debug("signOut() for user.")

            try await dispatchQueuedChanges()
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    func delete() async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw FirebaseAccountError.notSignedIn
        }

        defer {
            cleanupQueuedChanges()
        }

        shouldQueue = true

        do {
            try await currentUser.delete()
            Self.logger.debug("delete() for user.")

            try await dispatchQueuedChanges()
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    func updateAccountDetails(_ modifications: AccountModifications) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            throw FirebaseAccountError.notSignedIn
        }

        defer {
            cleanupQueuedChanges()
        }

        do {
            if let userId = modifications.modifiedDetails.storage[UserIdKey.self] {
                Self.logger.debug("updateEmail(to:) for user.")
                try await currentUser.updateEmail(to: userId)
            }

            if let password = modifications.modifiedDetails.password {
                Self.logger.debug("updatePassword(to:) for user.")
                try await currentUser.updatePassword(to: password)
            }

            if let name = modifications.modifiedDetails.name {
                Self.logger.debug("Creating change request for updated display name.")
                let changeRequest = currentUser.createProfileChangeRequest()
                changeRequest.displayName = name.formatted(.name(style: .long))
                try await changeRequest.commitChanges()
            }

            try await dispatchQueuedChanges()
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private func stateDidChangeListener(auth: Auth, user: User?) {
        // this is called by the FIRAuth framework.

        let change: UserChange
        if let user {
            change = .user(user)
        } else {
            change = .removed
        }


        if shouldQueue {
            Self.logger.debug("Received stateDidChange that is queued to be dispatched in active call.")
            self.queuedUpdate = QueueUpdate(change: change)
        } else {
            Self.logger.debug("Received stateDidChange that that was triggered due to other reasons. Dispatching anonymously...")
            anonymouslyDispatchChange(change)
        }
    }

    private func cleanupQueuedChanges() {
        shouldQueue = false

        guard let queuedUpdate = self.queuedUpdate else {
            return
        }


        self.queuedUpdate = nil
        anonymouslyDispatchChange(queuedUpdate.change)
    }

    private func dispatchQueuedChanges() async throws {
        shouldQueue = false

        guard let queuedUpdate else {
            return
        }

        try await apply(change: queuedUpdate.change)
        self.queuedUpdate = nil
    }

    private func anonymouslyDispatchChange(_ change: UserChange) {
        Task {
            do {
                try await apply(change: change)
            } catch {
                Self.logger.error("Failed to anonymously dispatch user change due to \(error)")
            }
        }
    }

    private func apply(change: UserChange) async throws {
        switch change {
        case let .user(user):
            try await notifyUserSignIn(user: user)
        case .removed:
            await notifyUserRemoval()
        }
    }

    func notifyUserSignIn(user: User) async throws {
        guard let email = user.email else {
            throw FirebaseAccountError.invalidEmail
        }

        let builder = AccountDetails.Builder()
            .set(\.userId, value: email)
            .set(\.isEmailVerified, value: user.isEmailVerified)

        if let displayName = user.displayName,
            let nameComponents = try? PersonNameComponents(displayName) {
            // we wouldn't be here if we couldn't create the person name components from the given string
            builder.set(\.name, value: nameComponents)
        }

        Self.logger.debug("Notifying SpeziAccount with updated user details.")

        let details = builder.build(owner: self)
        try await account.supplyUserDetails(details)
    }

    func notifyUserRemoval() async {
        Self.logger.debug("Notifying SpeziAccount of removed user details.")
        await account.removeUserDetails()
    }
}
