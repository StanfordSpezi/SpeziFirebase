//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseAuth
import SpeziAccount
import SwiftUI


// TODO do we want this actor requirement?
public actor FirebaseEmailPasswordAccountService: UserIdPasswordAccountService {
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

    @WeakInjectable<Account> // TODO AccountReference is internal!
    private var account: Account

    public let configuration: UserIdPasswordServiceConfiguration
    private var authStateDidChangeListenerHandle: AuthStateDidChangeListenerHandle?

    // TODO make this configurable?
    init(passwordValidationRules: [ValidationRule] = [FirebaseEmailPasswordAccountService.defaultPasswordValidationRule]) {
        self.configuration = .init(
            name: LocalizedStringResource("FIREBASE_EMAIL_AND_PASSWORD", bundle: .atURL(from: .module)),
            image: Image(systemName: "envelope.fill"),
            signUpRequirements: AccountValueRequirements {
                UserIdAccountValueKey.self
                PasswordAccountValueKey.self
                NameAccountValueKey.self
            },
            userIdType: .emailAddress,
            userIdField: .emailAddress,
            userIdSignupValidations: [.minimalEmailValidationRule],
            passwordSignupValidations: passwordValidationRules
        )
    }

    public func configure() {
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

    public func login(userId: String, password: String) async throws {
        do {
            try await Auth.auth().signIn(withEmail: userId, password: password)

            // TODO why did we trigger?
            // Task { @MainActor in
                // account?.objectWillChange.send()
            // }

        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    public func signUp(signupRequest: SignupRequest) async throws {
        do {
            let authResult = try await Auth.auth().createUser(withEmail: signupRequest.userId, password: signupRequest.password)

            let profileChangeRequest = authResult.user.createProfileChangeRequest()
            profileChangeRequest.displayName = signupRequest.name.formatted(.name(style: .long))
            try await profileChangeRequest.commitChanges()

            // TODO why did we trigger?
            // Task { @MainActor in
            //     account?.objectWillChange.send()
            // }

            try await authResult.user.sendEmailVerification()
        } catch let error as NSError {
            // TODO can we inline the `invalidEmail` and `weakPassword` errors? => weakPassword has to be updated in the validation rule!
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    public func resetPassword(userId: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: userId)
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    public func logout() async throws {
        do {
            try Auth.auth().signOut()

            // TODO verify that this results in the user getting removed?
        } catch let error as NSError {
            throw FirebaseAccountError(authErrorCode: AuthErrorCode(_nsError: error))
        } catch {
            throw FirebaseAccountError.unknown(.internalError)
        }
    }

    private func stateDidChangeListener(auth: Auth, user: User?) {
        Task {
            if let user {
                await notifyUserSignIn(user: user)
            } else {
                await notifyUserRemoval()
            }
        }
    }

    func notifyUserSignIn(user: User) async {
        guard let email = user.email,
              let displayName = user.displayName else {
            // TODO log
            return // TODO how to propagate back the error?
        }

        guard let nameComponents = try? PersonNameComponents(displayName) else {
            // we wouldn't be here if we couldn't create the person name components from the given string
            // TODO log (still show error somehow?)
            return
        }

        let details = AccountDetails.Builder()
            .add(UserIdAccountValueKey.self, value: email)
            .add(NameAccountValueKey.self, value: nameComponents)
            .add(FirebaseEmailVerifiedKey.self, value: user.isEmailVerified)
            .build(owner: self)

        await account.supplyUserInfo(details)
    }

    func notifyUserRemoval() async {
        await account.removeUserInfo()
    }
}
