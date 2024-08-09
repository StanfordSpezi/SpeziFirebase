//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseAuth
import Foundation


/// Error thrown by the `FirebaseAccountService`.
///
/// This error type might be thrown by methods of the ``FirebaseAccountService``.
public enum FirebaseAccountError {
    /// The provided email is invalid.
    case invalidEmail
    /// The account is already in use.
    case accountAlreadyInUse
    /// The password was rejected because it is too weak.
    case weakPassword
    /// The provided credentials are invalid.
    case invalidCredentials
    /// Internal error occurred when resetting the password.
    case internalPasswordResetError
    /// Internal error when performing the account operation.
    case setupError
    /// An operation was performed that requires an signed in user account.
    case notSignedIn
    /// The security operation requires a recent login.
    case requireRecentLogin
    /// The `ASAuthorizationAppleIDRequest` request failed due do an error reported from the AccountServices framework.
    case appleFailed
    /// Linking the account failed as the account was already linked with this type of account provider.
    case linkFailedDuplicate
    /// Linking the account failed as the credentials are already in use with a different account.
    case linkFailedAlreadyInUse
    /// Encountered an unrecognized provider when trying to re-authenticate the user.
    case unsupportedProvider
    /// Unrecognized Firebase account error.
    case unknown(AuthErrorCode.Code)


    /// Derive the error from the Firebase `AuthErrorCode`.
    /// - Parameter authErrorCode: The error code from the NSError reported by Firebase Auth.
    public init(authErrorCode: AuthErrorCode) {
        switch authErrorCode.code {
        case .invalidEmail, .invalidRecipientEmail:
            self = .invalidEmail
        case .emailAlreadyInUse:
            self = .accountAlreadyInUse
        case .weakPassword:
            self = .weakPassword
        case .userDisabled, .wrongPassword, .userNotFound, .userMismatch:
            self = .invalidCredentials
        case .invalidSender, .invalidMessagePayload:
            self = .internalPasswordResetError
        case .operationNotAllowed, .invalidAPIKey, .appNotAuthorized, .keychainError, .internalError:
            self = .setupError
        case .requiresRecentLogin:
            self = .requireRecentLogin
        case .providerAlreadyLinked:
            self = .linkFailedDuplicate
        case .credentialAlreadyInUse:
            self = .linkFailedAlreadyInUse
        default:
            self = .unknown(authErrorCode.code)
        }
    }
}


extension FirebaseAccountError: LocalizedError {
    private var errorDescriptionValue: String.LocalizationValue {
        switch self {
        case .invalidEmail:
            return "FIREBASE_ACCOUNT_ERROR_INVALID_EMAIL"
        case .accountAlreadyInUse:
            return "FIREBASE_ACCOUNT_ALREADY_IN_USE"
        case .weakPassword:
            return "FIREBASE_ACCOUNT_WEAK_PASSWORD"
        case .invalidCredentials:
            return "FIREBASE_ACCOUNT_INVALID_CREDENTIALS"
        case .internalPasswordResetError:
            return "FIREBASE_ACCOUNT_FAILED_PASSWORD_RESET"
        case .setupError:
            return "FIREBASE_ACCOUNT_SETUP_ERROR"
        case .notSignedIn:
            return "FIREBASE_ACCOUNT_SIGN_IN_ERROR"
        case .requireRecentLogin:
            return "FIREBASE_ACCOUNT_REQUIRE_RECENT_LOGIN_ERROR"
        case .unsupportedProvider:
            return "FIREBASE_ACCOUNT_UNSUPPORTED_PROVIDER_ERROR"
        case .appleFailed:
            return "FIREBASE_APPLE_FAILED"
        case .linkFailedDuplicate:
            return "FIREBASE_ACCOUNT_LINK_FAILED_DUPLICATE"
        case .linkFailedAlreadyInUse:
            return "FIREBASE_ACCOUNT_LINK_FAILED_ALREADY_IN_USE"
        case .unknown:
            return "FIREBASE_ACCOUNT_UNKNOWN"
        }
    }

    public var errorDescription: String? {
        .init(localized: errorDescriptionValue, bundle: .module)
    }

    private var recoverySuggestionValue: String.LocalizationValue {
        switch self {
        case .invalidEmail:
            return "FIREBASE_ACCOUNT_ERROR_INVALID_EMAIL_SUGGESTION"
        case .accountAlreadyInUse:
            return "FIREBASE_ACCOUNT_ALREADY_IN_USE_SUGGESTION"
        case .weakPassword:
            return "FIREBASE_ACCOUNT_WEAK_PASSWORD_SUGGESTION"
        case .invalidCredentials:
            return "FIREBASE_ACCOUNT_INVALID_CREDENTIALS_SUGGESTION"
        case .internalPasswordResetError:
            return "FIREBASE_ACCOUNT_FAILED_PASSWORD_RESET_SUGGESTION"
        case .setupError:
            return "FIREBASE_ACCOUNT_SETUP_ERROR_SUGGESTION"
        case .notSignedIn:
            return "FIREBASE_ACCOUNT_SIGN_IN_ERROR_SUGGESTION"
        case .requireRecentLogin:
            return "FIREBASE_ACCOUNT_REQUIRE_RECENT_LOGIN_ERROR_SUGGESTION"
        case .unsupportedProvider:
            return "FIREBASE_ACCOUNT_UNSUPPORTED_PROVIDER_ERROR_SUGGESTION"
        case .appleFailed:
            return "FIREBASE_APPLE_FAILED_SUGGESTION"
        case .linkFailedDuplicate:
            return "FIREBASE_ACCOUNT_LINK_FAILED_DUPLICATE_SUGGESTION"
        case .linkFailedAlreadyInUse:
            return "FIREBASE_ACCOUNT_LINK_FAILED_ALREADY_IN_USE_SUGGESTION"
        case .unknown:
            return "FIREBASE_ACCOUNT_UNKNOWN_SUGGESTION"
        }
    }

    public var recoverySuggestion: String? {
        .init(localized: recoverySuggestionValue, bundle: .module)
    }
}
