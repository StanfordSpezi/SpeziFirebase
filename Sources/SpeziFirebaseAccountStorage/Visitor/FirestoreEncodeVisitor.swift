//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import FirebaseFirestore
import SpeziAccount


class FirestoreEncodeVisitor: AccountValueVisitor {
    typealias Data = [String: Any]

    private var values: Data = [:]
    private var errors: [String: Error] = [:]

    init() {}

    func visit<Key: AccountKey>(_ key: Key.Type, _ value: Key.Value) {
        let encoder = Firestore.Encoder()
        do {
            values["\(Key.self)"] = try encoder.encode(value)
        } catch {
            errors["\(Key.self)"] = error
        }
    }

    func final() -> Result<Data, Error> {
        if let first = errors.first {
            // we just report the first error, like in a typical do-catch setup
            return .failure(first.value)
        } else {
            return .success(values)
        }
    }
}
