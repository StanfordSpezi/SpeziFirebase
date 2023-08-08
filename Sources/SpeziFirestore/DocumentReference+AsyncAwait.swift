//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
// Function signatures and documentation are replicating the original Firebase Firestore methods: Copyright 2019 Google - Apache License, Version 2.0
// SPDX-License-Identifier: MIT
//


@_exported import FirebaseFirestore
@_exported import FirebaseFirestoreSwift
import Foundation


extension DocumentReference {
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let encoded = try encoder.encode(value)
                setData(encoded) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    }
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let encoded = try encoder.encode(value)
                setData(encoded, merge: merge) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    }
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
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
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let encoded = try encoder.encode(value)
                setData(encoded, mergeFields: mergeFields) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    }
                    continuation.resume()
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
