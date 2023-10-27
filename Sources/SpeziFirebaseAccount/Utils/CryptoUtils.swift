//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CryptoKit
import Foundation


enum CryptoUtils {
    static func randomNonceString(length: Int) -> String {
        precondition(length > 0, "Nonce length must be non-zero")
        let nonceCharacters = (0 ..< length).map { _ in
            // ASCII alphabet goes from 32 (space) to 126 (~); Firebase seems to have problems with some special characters!
            let num = Int.random(in: 48...122) // .random(in:) is secure, see https://stackoverflow.com/a/76722233
            guard let scalar = UnicodeScalar(num) else {
                preconditionFailure("Failed to generate ASCII character for nonce!")
            }
            return Character(scalar)
        }

        return String(nonceCharacters)
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .compactMap { byte in
                String(format: "%02x", byte)
            }
            .joined()
    }
}
