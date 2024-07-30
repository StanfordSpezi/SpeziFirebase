//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import FirebaseFirestore
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
public actor FirestoreAccountStorage: AccountStorageProvider { // TODO: completely restructure docs!
    @Application(\.logger) private var logger

    @Dependency private var firestore: SpeziFirestore.Firestore // ensure firestore is configured
    @Dependency private var externalStorage: ExternalAccountStorage
    @Dependency private var localCache: LocalDetailsCache

    private let collection: @Sendable () -> CollectionReference


    private var listenerRegistrations: [String: ListenerRegistration] = [:]

    public init(storeIn collection: @Sendable @autoclosure @escaping () -> CollectionReference) {
        self.collection = collection
    }


    private nonisolated func userDocument(for accountId: String) -> DocumentReference {
        collection().document(accountId)
    }

    private func snapshotListener(for accountId: String, with keys: [any AccountKey.Type]) {
        if let existingListener = listenerRegistrations[accountId] {
            existingListener.remove()
        }
        let document = userDocument(for: accountId)

        listenerRegistrations[accountId] = document.addSnapshotListener { [weak self] snapshot, error in
            guard let self else {
                return
            }

            guard let snapshot else {
                // TODO: error happened, how to best notify about error?
                return
            }

            Task {
                await self.processUpdatedSnapshot(for: accountId, with: keys, snapshot)
            }
        }
    }

    private func processUpdatedSnapshot(for accountId: String, with keys: [any AccountKey.Type], _ snapshot: DocumentSnapshot) {
        do {
            let details = try buildAccountDetails(from: snapshot, keys: keys)
            localCache.communicateRemoteChanges(for: accountId, details)

            externalStorage.notifyAboutUpdatedDetails(for: accountId, details)
        } catch {
            logger.error("")
            // TODO: log or do something with that info!
            // TODO: does it make sense to notify the account service about the error?
        }
    }

    private nonisolated func buildAccountDetails(from snapshot: DocumentSnapshot, keys: [any AccountKey.Type]) throws -> AccountDetails {
        guard let data = snapshot.data() else {
            return AccountDetails()
        }

        var details = AccountDetails()

        for key in keys {
            guard let value = data[key.identifier] else {
                continue
            }

            var visitor = FirestoreDecodeVisitor(value: value, details: details, in: snapshot.reference)
            key.accept(&visitor)
            switch visitor.final() {
            case let .success(value):
                details = value
            case let .failure(error):
                throw FirestoreError(error)
            }
        }

        return details
    }

    public func create(_ accountId: String, _ details: AccountDetails) async throws {
        // we just treat it as modifications
        let modifications = try AccountModifications(modifiedDetails: details)
        try await modify(accountId, modifications)
    }

    public func load(_ accountId: String, _ keys: [any AccountKey.Type]) async throws -> AccountDetails? { // TODO: transport keys as set?
        let cached = localCache.loadEntry(for: accountId, keys)

        if listenerRegistrations[accountId] != nil { // check that there is a snapshot listener in place
            snapshotListener(for: accountId, with: keys)
        }

        return cached
    }

    public func modify(_ accountId: String, _ modifications: AccountModifications) async throws {
        let result = modifications.modifiedDetails.acceptAll(FirestoreEncodeVisitor())

        do {
            switch result {
            case let .success(data):
                try await userDocument(for: accountId)
                    .setData(data, merge: true)
            case let .failure(error):
                throw error
            }

            let removedFields: [String: Any] = modifications.removedAccountDetails.keys.reduce(into: [:]) { result, key in
                result[key.identifier] = FieldValue.delete()
            }

            try await userDocument(for: accountId)
                .updateData(removedFields)
        } catch {
            throw FirestoreError(error)
        }

        localCache.communicateModifications(for: accountId, modifications)


        // TODO: check if the snapshot listener is in place with the same set of keys (add remove)!
        if listenerRegistrations[accountId] != nil {
            // TODO: if we have sets, its easier!
            // TODO: actually keep track of all account keys, this will fail!
            snapshotListener(for: accountId, with: modifications.modifiedDetails.keys)
        }
    }

    public func disassociate(_ accountId: String) {
        guard let registration = listenerRegistrations.removeValue(forKey: accountId) else {
            return
        }
        registration.remove()

        localCache.clearEntry(for: accountId)
    }

    public func delete(_ accountId: String) async throws {
        disassociate(accountId)

        do {
            try await userDocument(for: accountId)
                .delete()
        } catch {
            throw FirestoreError(error)
        }
    }
}
