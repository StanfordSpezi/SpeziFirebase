//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import FirebaseFirestore
import OSLog
import SpeziAccount


private struct SingleKeyContainer<Value: Codable>: Codable {
    let value: Value
}


class FirestoreEncodeVisitor: AccountValueVisitor {
    typealias Data = [String: Any]

    private let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "FirestoreEncode")

    private var values: Data = [:]
    private var errors: [String: Error] = [:]

    init() {}

    func visit<Key: AccountKey>(_ key: Key.Type, _ value: Key.Value) {
        let encoder = Firestore.Encoder()

        // the firestore encode method expects a container type!
        let container = SingleKeyContainer(value: value)

        do {
            let result = try encoder.encode(container)
            guard let encoded = result["value"] else {
                preconditionFailure("Layout of SingleKeyContainer changed. Does not contain value anymore: \(result)")
            }

            values["\(Key.self)"] = encoded
        } catch {
            logger.error("Failed to encode \("\(value)") for key \(key): \(error)")
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
