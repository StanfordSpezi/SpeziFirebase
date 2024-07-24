//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziValidation


extension ValidationRule { // TODO: move!
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
