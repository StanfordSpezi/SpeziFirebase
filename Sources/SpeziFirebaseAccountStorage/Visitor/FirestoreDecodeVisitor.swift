//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import SpeziAccount


struct FirestoreDecodeVisitor: AccountKeyVisitor {
    private var details: AccountDetails
    private let value: Any
    private let reference: DocumentReference

    private var error: Error?


    init(value: Any, details: AccountDetails, in reference: DocumentReference) {
        self.value = value
        self.details = details
        self.reference = reference
    }


    mutating func visit<Key: AccountKey>(_ key: Key.Type) {
        let decoder = Firestore.Decoder()

        do {
            let value = try decoder.decode(Key.Value.self, from: value, in: reference)
            details.set(key, value: value)
        } catch {
            self.error = error
        }
    }

    func final() -> Result<AccountDetails, Error> {
        if let error {
            return .failure(error)
        } else {
            return .success(details)
        }
    }
}
