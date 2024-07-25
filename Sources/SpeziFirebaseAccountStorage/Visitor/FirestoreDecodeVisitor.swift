//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import SpeziAccount


class FirestoreDecodeVisitor: AccountKeyVisitor {
    private let builder: SimpleBuilder<AccountDetails>
    private let value: Any
    private let reference: DocumentReference

    private var error: Error?


    init(value: Any, builder: SimpleBuilder<AccountDetails>, in reference: DocumentReference) {
        self.value = value
        self.builder = builder
        self.reference = reference
    }


    func visit<Key: AccountKey>(_ key: Key.Type) {
        let decoder = Firestore.Decoder()

        do {
            // TODO: do we really need to pass the doc reference?
            try builder.set(key, value: decoder.decode(Key.Value.self, from: value, in: reference))
        } catch {
            self.error = error
        }
    }

    func final() -> Result<Void, Error> {
        if let error {
            return .failure(error)
        } else {
            return .success(())
        }
    }
}
