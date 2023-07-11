//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseAuth
import Foundation


enum FirebaseAccountError: LocalizedError {
    case invalidEmail
    case accountAlreadyInUse
    case weakPassword
    case invalidCredentials
    case internalPasswordResetError
    case setupError
    case unknown(AuthErrorCode.Code)
    
    
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
        case .unknown:
            return "FIREBASE_ACCOUNT_UNKNOWN"
        }
    }

    var errorDescription: String? {
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
        case .unknown:
            return "FIREBASE_ACCOUNT_UNKNOWN_SUGGESTION"
        }
    }

    var recoverySuggestion: String? {
        .init(localized: recoverySuggestionValue, bundle: .module)
    }

    
    init(authErrorCode: AuthErrorCode) {
        switch authErrorCode.code {
        case .invalidEmail, .invalidRecipientEmail:
            self = .invalidEmail
        case .emailAlreadyInUse:
            self = .accountAlreadyInUse
        case .weakPassword:
            self = .weakPassword
        case .userDisabled, .wrongPassword:
            self = .invalidCredentials
        case .invalidSender, .invalidMessagePayload:
            self = .internalPasswordResetError
        case .operationNotAllowed, .invalidAPIKey, .appNotAuthorized, .keychainError, .internalError:
            self = .setupError
        default:
            self = .unknown(authErrorCode.code)
        }
    }
}
