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
import SpeziSecureStorage
import SpeziValidation
import SwiftUI


struct EmailPasswordViewStyle: UserIdPasswordAccountSetupViewStyle {
    let service: FirebaseEmailPasswordAccountService

    var securityRelatedViewModifier: any ViewModifier {
        ReauthenticationAlertModifier()
    }
}


actor FirebaseEmailPasswordAccountService: UserIdPasswordAccountService, FirebaseAccountService {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "AccountService")

    private static let supportedKeys = AccountKeyCollection {
        \.accountId
        \.userId
        \.password
        \.name
    }


    @AccountReference var account: Account
    @_WeakInjectable var context: FirebaseContext

    let configuration: AccountServiceConfiguration
    let firebaseModel: FirebaseAccountModel

    nonisolated var viewStyle: EmailPasswordViewStyle {
        EmailPasswordViewStyle(service: self)
    }


    init(_ model: FirebaseAccountModel, passwordValidationRules: [ValidationRule] = [.minimumFirebasePassword]) {
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
        self.firebaseModel = model
    }


    func configure(with context: FirebaseContext) async {
        self._context.inject(context)
        await context.share(account: account)
    }

    func login(userId: String, password: String) async throws {
        Self.logger.debug("Received new login request...")

        try await context.dispatchFirebaseAuthAction(on: self) {
            try await Auth.auth().signIn(withEmail: userId, password: password)
            Self.logger.debug("signIn(withEmail:password:)")
        }
    }

    func signUp(signupDetails: SignupDetails) async throws {
        Self.logger.debug("Received new signup request...")

        guard let password = signupDetails.password else {
            throw FirebaseAccountError.invalidCredentials
        }

        try await context.dispatchFirebaseAuthAction(on: self) {
            if let currentUser = Auth.auth().currentUser,
               currentUser.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: signupDetails.userId, password: password)
                Self.logger.debug("Linking email-password credentials with current anonymous user account ...")
                let result = try await currentUser.link(with: credential)

                try await context.notifyUserSignIn(user: currentUser, for: self, isNewUser: true)

                return
            }

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

    func reauthenticateUser(user: User) async throws -> ReauthenticationOperationResult {
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
}


extension ValidationRule {
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
}
