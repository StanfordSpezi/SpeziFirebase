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
    private let data: [String: Any]
    private let reference: DocumentReference

    private var details = AccountDetails()
    private(set) var errors: [(any AccountKey.Type, Error)] = []


    init(data: [String: Any], in reference: DocumentReference) {
        self.data = data
        self.reference = reference
    }


    mutating func visit<Key: AccountKey>(_ key: Key.Type) {
        guard let dataValue = data[key.identifier] else {
            return
        }

        let decoder = Firestore.Decoder()

        do {
            let value = try decoder.decode(Key.Value.self, from: dataValue, in: reference)
            details.set(key, value: value)
        } catch {
            errors.append((key, error))
        }
    }

    func final() -> AccountDetails {
        details
    }
}
