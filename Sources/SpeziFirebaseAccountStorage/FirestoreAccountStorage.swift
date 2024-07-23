//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import Spezi
import SpeziAccount
import SpeziFirestore


/// Store additional account details directly in Firestore.
///
/// Certain account services, like the account services provided by Firebase, can only store certain account details.
/// The `FirestoreAccountStorage` can be used to store additional account details, that are not supported out of the box by your account services,
/// inside Firestore in a custom user collection.
///
/// - Note: The `FirestoreAccountStorage` relies on the primary [AccountId](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountidkey)
///     as the document identifier. Fore Firebase-based account service, this is the primary, firebase user identifier. Make sure to configure your firestore security rules respectively.
///
/// Once you have [AccountConfiguration](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/initial-setup#Account-Configuration)
/// and the [FirebaseAccountConfiguration](https://swiftpackageindex.com/stanfordspezi/spezifirebase/documentation/spezifirebaseaccount/firebaseaccountconfiguration)
/// set up, you can adopt the [AccountStorageConstraint](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountstorageconstraint)
/// protocol to provide a custom storage for SpeziAccount.
///
/// - Important: In order to use the `FirestoreAccountStorage`, you must have [Firestore](https://swiftpackageindex.com/stanfordspezi/spezifirebase/main/documentation/spezifirestore/firestore)
///     configured in your app. Refer to the documentation page for more information.
///
/// ```swift
/// import FirebaseFirestore
/// import Spezi
/// import SpeziAccount
/// import SpeziFirebaseAccountStorage
///
///
/// actor ExampleStandard: Standard, AccountStorageConstraint {
///     // Define the collection where you want to store your additional user data, ...
///     static var collection: CollectionReference {
///         Firestore.firestore().collection("users")
///     }
///
///     // ... define and initialize the `FirestoreAccountStorage` dependency ...
///     @Dependency private var accountStorage = FirestoreAccountStorage(storedIn: Self.collection)
///
///
///     // ... and forward all implementations of `AccountStorageConstraint` to the `FirestoreAccountStorage`.
///
///     public func create(_ identifier: AdditionalRecordId, _ details: SignupDetails) async throws {
///         try await accountStorage.create(identifier, details)
///     }
///
///     public func load(_ identifier: AdditionalRecordId, _ keys: [any AccountKey.Type]) async throws -> PartialAccountDetails {
///         try await accountStorage.load(identifier, keys)
///     }
///
///     public func modify(_ identifier: AdditionalRecordId, _ modifications: AccountModifications) async throws {
///         try await accountStorage.modify(identifier, modifications)
///     }
///
///     public func clear(_ identifier: AdditionalRecordId) async {
///         await accountStorage.clear(identifier)
///     }
///
///     public func delete(_ identifier: AdditionalRecordId) async throws {
///         try await accountStorage.delete(identifier)
///     }
/// }
/// ```
public actor FirestoreAccountStorage: Module, AccountStorageConstraint {
    @Dependency private var firestore: SpeziFirestore.Firestore // ensure firestore is configured

    private let collection: () -> CollectionReference


    public init(storeIn collection: @Sendable @autoclosure @escaping () -> CollectionReference) {
        self.collection = collection
    }


    private func userDocument(for accountId: String) -> DocumentReference {
        collection().document(accountId)
    }

    public func create(_ identifier: AdditionalRecordId, _ details: SignupDetails) async throws {
        let result = details.acceptAll(FirestoreEncodeVisitor())

        do {
            switch result {
            case let .success(data):
                guard !data.isEmpty else {
                    return
                }
                
                try await userDocument(for: identifier.accountId)
                    .setData(data, merge: true)
            case let .failure(error):
                throw error
            }
        } catch {
            throw FirestoreError(error)
        }
    }

    public func load(_ identifier: AdditionalRecordId, _ keys: [any AccountKey.Type]) async throws -> PartialAccountDetails {
        let builder = PartialAccountDetails.Builder()

        let document = userDocument(for: identifier.accountId)

        do {
            let data = try await document
                .getDocument()
                .data()

            if let data {
                for key in keys {
                    guard let value = data[key.identifier] else {
                        continue
                    }

                    let visitor = FirestoreDecodeVisitor(value: value, builder: builder, in: document)
                    key.accept(visitor)
                    if case let .failure(error) = visitor.final() {
                        throw error
                    }
                }
            }
        } catch {
            throw FirestoreError(error)
        }

        return builder.build()
    }

    public func modify(_ identifier: AdditionalRecordId, _ modifications: AccountModifications) async throws {
        let result = modifications.modifiedDetails.acceptAll(FirestoreEncodeVisitor())

        do {
            switch result {
            case let .success(data):
                try await userDocument(for: identifier.accountId)
                    .updateData(data)
            case let .failure(error):
                throw error
            }

            let removedFields: [String: Any] = modifications.removedAccountDetails.keys.reduce(into: [:]) { result, key in
                result[key.identifier] = FieldValue.delete()
            }

            try await userDocument(for: identifier.accountId)
                .updateData(removedFields)
        } catch {
            throw FirestoreError(error)
        }
    }

    public func clear(_ identifier: AdditionalRecordId) async {
        // nothing we can do ...
    }

    public func delete(_ identifier: AdditionalRecordId) async throws {
        do {
            try await userDocument(for: identifier.accountId)
                .delete()
        } catch {
            throw FirestoreError(error)
        }
    }
}
