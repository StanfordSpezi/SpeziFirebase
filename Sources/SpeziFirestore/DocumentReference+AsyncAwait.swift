//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
// Function signatures and documentation are replicating the original Firebase Firestore methods: Copyright 2019 Google - Apache License, Version 2.0
// SPDX-License-Identifier: MIT
//

import Atomics
import FirebaseFirestore
import Foundation
import OSLog


#if compiler(>=6)
private struct FirestoreCompletion: Sendable {
    private static var logger: Logger {
        Logger(subsystem: "edu.stanford.spezi.firebase", category: "FirestoreCompletion")
    }

    private let continuation: UnsafeContinuation<Void, Error>
    private let resumed: ManagedAtomic<Bool>

    private init(continuation: UnsafeContinuation<Void, Error>) {
        self.continuation = continuation
        self.resumed = ManagedAtomic(false)
    }

    static func perform(
        isolation: isolated (any Actor)? = #isolation,
        file: StaticString = #filePath,
        line: Int = #line,
        action: (FirestoreCompletion) throws -> Void
    ) async throws {
        try await withUnsafeThrowingContinuation { continuation in
            let completion = FirestoreCompletion(continuation: continuation)
            do {
                try action(completion)
            } catch {
                completion.complete(with: error, file: file, line: line)
            }
        }
    }

    func complete(
        with error: Error?,
        file: StaticString = #filePath,
        line: Int = #line
    ) {
        let (exchanged, _) = resumed.compareExchange(expected: false, desired: true, ordering: .relaxed)
        if !exchanged {
            Self.logger.warning("\(file):\(line): Firestore completion handler completed twice. This time with: \(error)")
            return
        }

        if let error {
            continuation.resume(throwing: FirestoreError(error))
        } else {
            continuation.resume()
        }
    }
}
#endif


extension DocumentReference {
#if compiler(>=6)
    /// Overwrite the data of a document with an encodable value.
    ///
    /// Encodes an instance of `Encodable` and overwrites the encoded data
    /// to the document referred by this `DocumentReference`. If no document exists,
    /// it is created. If a document already exists, it is overwritten.
    ///
    /// See `Firestore.Encoder` for more details about the encoding process.
    ///
    /// Returns once the document has been successfully written to the server.
    /// Due to the Firebase SDK, it will not return when the client is offline, though local changes will be visible immediately.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation to inherit.
    ///   - value: An instance of `Encodable` to be encoded to a document.
    ///   - encoder: An encoder instance to use to run the encoding.
    public func setData<T: Encodable>( // swiftlint:disable:this function_default_parameter_at_end
        isolation: isolated (any Actor)? = #isolation,
        from value: T,
        encoder: FirebaseFirestore.Firestore.Encoder = FirebaseFirestore.Firestore.Encoder()
    ) async throws {
        try await FirestoreCompletion.perform { completion in
            try setData(from: value, encoder: encoder) { error in
                completion.complete(with: error)
            }
        }
    }

    /// Write the data of a document with an encodable value.
    ///
    /// Encodes an instance of `Encodable` and overwrites the encoded data
    /// to the document referred by this `DocumentReference`. If no document exists,
    /// it is created. If a document already exists, it is overwritten.  If you pass
    /// merge:true, the provided `Encodable` will be merged into any existing document.
    ///
    /// See `Firestore.Encoder` for more details about the encoding process.
    ///
    /// Returns once the document has been successfully written to the server.
    /// Due to the Firebase SDK, it will not return when the client is offline, though local changes will be visible immediately.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation to inherit.
    ///   - value: An instance of `Encodable` to be encoded to a document.
    ///   - merge: Whether to merge the provided `Encodable` into any existing
    ///            document.
    ///   - encoder: An encoder instance to use to run the encoding.
    public func setData<T: Encodable>( // swiftlint:disable:this function_default_parameter_at_end
        isolation: isolated (any Actor)? = #isolation,
        from value: T,
        merge: Bool,
        encoder: FirebaseFirestore.Firestore.Encoder = FirebaseFirestore.Firestore.Encoder()
    ) async throws {
        try await FirestoreCompletion.perform { completion in
            try setData(from: value, merge: merge, encoder: encoder) { error in
                completion.complete(with: error)
            }
        }
    }
    
    /// Write the data of a document by merging a set of fields.
    ///
    /// Encodes an instance of `Encodable` and writes the encoded data to the document referred
    /// by this `DocumentReference` by only replacing the fields specified under `mergeFields`.
    /// Any field that is not specified in mergeFields is ignored and remains untouched. If the
    /// document doesn’t yet exist, this method creates it and then sets the data.
    ///
    /// It is an error to include a field in `mergeFields` that does not have a corresponding
    /// field in the `Encodable`.
    ///
    /// See `Firestore.Encoder` for more details about the encoding process.
    ///
    /// Returns once the document has been successfully written to the server.
    /// Due to the Firebase SDK, it will not return when the client is offline, though local changes will be visible immediately.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation to inherit.
    ///   - value: An instance of `Encodable` to be encoded to a document.
    ///   - mergeFields: Array of `String` or `FieldPath` elements specifying which fields to
    ///                  merge. Fields can contain dots to reference nested fields within the
    ///                  document.
    ///   - encoder: An encoder instance to use to run the encoding.
    public func setData<T: Encodable>( // swiftlint:disable:this function_default_parameter_at_end
        isolation: isolated (any Actor)? = #isolation,
        from value: T,
        mergeFields: [Any],
        encoder: FirebaseFirestore.Firestore.Encoder = FirebaseFirestore.Firestore.Encoder()
    ) async throws {
        try await FirestoreCompletion.perform { completion in
            try setData(from: value, mergeFields: mergeFields, encoder: encoder) { error in
                completion.complete(with: error)
            }
        }
    }
#else
    /// Overwrite the data of a document with an encodable value.
    ///
    /// Encodes an instance of `Encodable` and overwrites the encoded data
    /// to the document referred by this `DocumentReference`. If no document exists,
    /// it is created. If a document already exists, it is overwritten.
    ///
    /// See `Firestore.Encoder` for more details about the encoding process.
    ///
    /// Returns once the document has been successfully written to the server.
    /// Due to the Firebase SDK, it will not return when the client is offline, though local changes will be visible immediately.
    ///
    /// - Parameters:
    ///   - value: An instance of `Encodable` to be encoded to a document.
    ///   - encoder: An encoder instance to use to run the encoding.
    public func setData<T: Encodable>(
        from value: T,
        encoder: FirebaseFirestore.Firestore.Encoder = FirebaseFirestore.Firestore.Encoder()
    ) async throws {
        do {
            let encoded = try encoder.encode(value)
            try await setData(encoded)
        } catch {
            throw FirestoreError(error)
        }
    }

    /// Write the data of a document with an encodable value.
    ///
    /// Encodes an instance of `Encodable` and overwrites the encoded data
    /// to the document referred by this `DocumentReference`. If no document exists,
    /// it is created. If a document already exists, it is overwritten.  If you pass
    /// merge:true, the provided `Encodable` will be merged into any existing document.
    ///
    /// See `Firestore.Encoder` for more details about the encoding process.
    ///
    /// Returns once the document has been successfully written to the server.
    /// Due to the Firebase SDK, it will not return when the client is offline, though local changes will be visible immediately.
    ///
    /// - Parameters:
    ///   - value: An instance of `Encodable` to be encoded to a document.
    ///   - merge: Whether to merge the provided `Encodable` into any existing
    ///            document.
    ///   - encoder: An encoder instance to use to run the encoding.
    public func setData<T: Encodable>(
        from value: T,
        merge: Bool,
        encoder: FirebaseFirestore.Firestore.Encoder = FirebaseFirestore.Firestore.Encoder()
    ) async throws {
        do {
            let encoded = try encoder.encode(value)
            try await setData(encoded, merge: merge)
        } catch {
            throw FirestoreError(error)
        }
    }

    /// Write the data of a document by merging a set of fields.
    ///
    /// Encodes an instance of `Encodable` and writes the encoded data to the document referred
    /// by this `DocumentReference` by only replacing the fields specified under `mergeFields`.
    /// Any field that is not specified in mergeFields is ignored and remains untouched. If the
    /// document doesn’t yet exist, this method creates it and then sets the data.
    ///
    /// It is an error to include a field in `mergeFields` that does not have a corresponding
    /// field in the `Encodable`.
    ///
    /// See `Firestore.Encoder` for more details about the encoding process.
    ///
    /// Returns once the document has been successfully written to the server.
    /// Due to the Firebase SDK, it will not return when the client is offline, though local changes will be visible immediately.
    ///
    /// - Parameters:
    ///   - value: An instance of `Encodable` to be encoded to a document.
    ///   - mergeFields: Array of `String` or `FieldPath` elements specifying which fields to
    ///                  merge. Fields can contain dots to reference nested fields within the
    ///                  document.
    ///   - encoder: An encoder instance to use to run the encoding.
    public func setData<T: Encodable>(
        from value: T,
        mergeFields: [Any],
        encoder: FirebaseFirestore.Firestore.Encoder = FirebaseFirestore.Firestore.Encoder()
    ) async throws {
        do {
            let encoded = try encoder.encode(value)
            try await setData(encoded, mergeFields: mergeFields)
        } catch {
            throw FirestoreError(error)
        }
    }
#endif
}
