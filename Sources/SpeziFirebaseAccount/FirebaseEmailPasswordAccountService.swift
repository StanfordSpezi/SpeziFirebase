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


enum StateChangeResult {
    case user(_ user: User)
    case removed
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

    private var currentContinuation: CheckedContinuation<StateChangeResult, Never>?

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
        do {
            try await Auth.auth().signIn(withEmail: userId, password: password)

            try await continueWithStateChange()
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    func signUp(signupDetails: SignupDetails) async throws {
        do {
            let authResult = try await Auth.auth().createUser(withEmail: signupDetails.userId, password: signupDetails.password)

            if let displayName = signupDetails.name?.formatted(.name(style: .long)) {
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try await changeRequest.commitChanges()
            }

            try await authResult.user.sendEmailVerification()

            try await continueWithStateChange()
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    func resetPassword(userId: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: userId)
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

        do {
            try Auth.auth().signOut()

            try await continueWithStateChange()
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

        do {
            try await currentUser.delete()

            try await continueWithStateChange()
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

        var changes = false

        do {
            if let userId = modifications.modifiedDetails.storage[UserIdKey.self] {
                try await currentUser.updateEmail(to: userId)
                changes = true
            }

            if let password = modifications.modifiedDetails.password {
                try await currentUser.updatePassword(to: password)
                changes = true
            }

            if let name = modifications.modifiedDetails.name {
                let changeRequest = currentUser.createProfileChangeRequest()
                changeRequest.displayName = name.formatted(.name(style: .long))
                try await changeRequest.commitChanges()

                changes = true
            }

            if changes {
                try await continueWithStateChange()
            }
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private func stateDidChangeListener(auth: Auth, user: User?) {
        // this is called by the FIRAuth framework.

        let result: StateChangeResult
        if let user {
            result = .user(user)
        } else {
            result = .removed
        }

        // if we have a current continuation waiting for our result, resume there
        if let currentContinuation {
            currentContinuation.resume(returning: result)
            self.currentContinuation = nil
        } else {
            // Otherwise, there might still be cases where changes are triggered externally.
            // We cannot sensibly display any error messages then, though.
            Task {
                do {
                    try await updateUser(result)
                } catch {
                    // currently, this only happens if the storage standard fails to load the additional user record
                    Self.logger.error("Failed to execute remote user change: \(error)")
                }
            }
        }
    }

    func continueWithStateChange() async throws {
        let result: StateChangeResult = await withCheckedContinuation { continuation in
            self.currentContinuation = continuation
        }

        try await updateUser(result)
    }

    func updateUser(_ state: StateChangeResult) async throws {
        switch state {
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


        let details = builder.build(owner: self)
        try await account.supplyUserDetails(details)
    }

    func notifyUserRemoval() async {
        await account.removeUserDetails()
    }
}
