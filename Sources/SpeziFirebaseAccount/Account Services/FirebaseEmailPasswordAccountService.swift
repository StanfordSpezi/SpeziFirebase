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
import SpeziSecureStorage
import SwiftUI


actor FirebaseEmailPasswordAccountService: UserIdPasswordAccountService, FirebaseAccountService {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "AccountService")

    private static let supportedKeys = AccountKeyCollection {
        \.userId
        \.password
        \.name
    }

    static var minimumFirebasePassword: ValidationRule {
        // Firebase as a non-configurable limit of 6 characters for an account password.
        // Refer to https://stackoverflow.com/questions/38064248/firebase-password-validation-allowed-regex
        guard let regex = try? Regex(#"(?=.*[0-9a-zA-Z]).{6,}"#) else {
            fatalError("Invalid minimumFirebasePassword regex at construction.")
        }

        return ValidationRule(
            regex: regex,
            message: "FIREBASE_ACCOUNT_DEFAULT_PASSWORD_RULE_ERROR \(6)",
            bundle: .module
        )
    }

    @AccountReference var account: Account
    @_WeakInjectable var context: FirebaseContext

    let configuration: AccountServiceConfiguration

    init(passwordValidationRules: [ValidationRule] = [minimumFirebasePassword]) {
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

    func configure(with context: FirebaseContext) async {
        self._context.inject(context)
        await context.share(account: account)
    }

    func handleAccountRemoval(userId: String?) {
        if let userId {
            context.removeCredentials(userId: userId, server: StorageKeys.emailPasswordCredentials)
        }
    }

    func login(userId: String, password: String) async throws {
        Self.logger.debug("Received new login request...")

        try await context.dispatchFirebaseAuthAction(on: self) {
            try await Auth.auth().signIn(withEmail: userId, password: password)
            Self.logger.debug("signIn(withEmail:password:)")
        }

        context.persistCurrentCredentials(userId: userId, password: password, server: StorageKeys.emailPasswordCredentials)
    }

    func signUp(signupDetails: SignupDetails) async throws {
        Self.logger.debug("Received new signup request...")

        guard let password = signupDetails.password else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await context.dispatchFirebaseAuthAction(on: self) {
            let authResult = try await Auth.auth().createUser(withEmail: signupDetails.userId, password: password)
            Self.logger.debug("createUser(withEmail:password:) for user.")

            Self.logger.debug("Sending email verification link now...")
            try await authResult.user.sendEmailVerification()

            if let displayName = signupDetails.name {
                Self.logger.debug("Creating change request for display name.")
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = displayName.formatted(.name(style: .medium))
                try await changeRequest.commitChanges()
            }
        }

        context.persistCurrentCredentials(userId: signupDetails.userId, password: password, server: StorageKeys.emailPasswordCredentials)
    }

    func resetPassword(userId: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: userId)
            Self.logger.debug("sendPasswordReset(withEmail:) for user.")
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

    func reauthenticateUser(userId: String, user: User) async {
        guard let password = context.retrieveCredential(userId: userId, server: StorageKeys.emailPasswordCredentials) else {
            return // nothing we can do
        }

        do {
            try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: userId, password: password))
        } catch {
            Self.logger.debug("Credential change might fail. Failed to reauthenticate with firebase.: \(error)")
        }
    }
}
