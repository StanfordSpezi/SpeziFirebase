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

enum ReauthenticationOperationResult {
    case cancelled
    case success
}


protocol FirebaseAccountService: AnyActor, AccountService {
    static var logger: Logger { get }
    
    var account: Account { get async }
    var context: FirebaseContext { get async }

    /// This method is called upon startup to configure the Firebase-based AccountService.
    ///
    /// - Important: You must call `FirebaseContext/share(account:)` with your `@AccountReference`-acquired
    ///     `Account` object within this method call.
    /// - Parameter context: The global firebase context
    func configure(with context: FirebaseContext) async

    /// This method is called to re-authenticate the current user credentials.
    ///
    /// - Parameter user: The user instance to reauthenticate.
    /// - Returns: `true` if authentication was successful, `false` if authentication was cancelled by the user.
    /// - Throws: If authentication failed.
    func reauthenticateUser(user: User) async throws -> ReauthenticationOperationResult
}


extension FirebaseAccountService {
    func inject(authorizationController: AuthorizationController) async {}
}


// MARK: - Default Account Service Implementations
extension FirebaseAccountService {
    func logout() async throws {
        guard Auth.auth().currentUser != nil else {
            if await account.signedIn {
                try await context.notifyUserRemoval(for: self)
                return
            } else {
                throw FirebaseAccountError.notSignedIn
            }
        }

        try await context.dispatchFirebaseAuthAction(on: self) {
            try Auth.auth().signOut()
            try await Task.sleep(for: .milliseconds(10))
            Self.logger.debug("signOut() for user.")
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
            let result = try await reauthenticateUser(user: currentUser) // delete requires a recent sign in
            guard case .success = result else {
                Self.logger.debug("Re-authentication was cancelled. Not deleting the account.")
                return // cancelled
            }

            try await currentUser.delete()
            Self.logger.debug("delete() for user.")
        }
    }

    func updateAccountDetails(_ modifications: AccountModifications) async throws {
        guard let currentUser = Auth.auth().currentUser else {
            if await account.signedIn {
                try await context.notifyUserRemoval(for: self)
            }
            throw FirebaseAccountError.notSignedIn
        }

        var changes = false

        do {
            // if we modify sensitive credentials and require a recent login
            if modifications.modifiedDetails.storage[UserIdKey.self] != nil || modifications.modifiedDetails.password != nil {
                let result = try await reauthenticateUser(user: currentUser)
                guard case .success = result else {
                    Self.logger.debug("Re-authentication was cancelled. Not deleting the account.")
                    return // got cancelled!
                }
            }

            if let userId = modifications.modifiedDetails.storage[UserIdKey.self] {
                Self.logger.debug("updateEmail(to:) for user.")
                try await currentUser.updateEmail(to: userId)
                changes = true
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

                changes = true
            }

            if changes {
                // non of the above request will trigger our state change listener, therefore just call it manually.
                try await context.notifyUserSignIn(user: currentUser, for: self)
            }
        } catch let error as NSError {
            Self.logger.error("Received NSError on firebase dispatch: \(error)")
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            Self.logger.error("Received error on firebase dispatch: \(error)")
            throw FirebaseAccountError.unknown(.internalError)
        }
    }
}
