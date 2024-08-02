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
    @Application(\.logger)
    private var logger

    @Dependency private var firestore = SpeziFirestore.Firestore() // ensure firestore is configured
    @Dependency(ExternalAccountStorage.self)
    private var externalStorage
    @Dependency private var localCache = AccountDetailsCache()

    private let collection: @Sendable () -> CollectionReference

    private var listenerRegistrations: [String: ListenerRegistration] = [:]
    private var registeredKeys: [String: [ObjectIdentifier: any AccountKey.Type]] = [:]

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

        registeredKeys[accountId] = keys.reduce(into: [:]) { result, key in
            result[ObjectIdentifier(key)] = key
        }

        listenerRegistrations[accountId] = document.addSnapshotListener { [weak self] snapshot, error in
            guard let self else {
                return
            }

            Task {
                guard let snapshot else {
                    await self.logger.error("Failed to retrieve user document collection: \(error)")
                    return
                }
                await self.processUpdatedSnapshot(for: accountId, snapshot)
            }
        }
    }

    private func processUpdatedSnapshot(for accountId: String, _ snapshot: DocumentSnapshot) async {
        guard let keys = registeredKeys[accountId]?.values else {
            logger.error("Failed to process updated document snapshot as we couldn't locate registered keys.")
            return
        }

        let details = buildAccountDetails(from: snapshot, keys: Array(keys))

        externalStorage.notifyAboutUpdatedDetails(for: accountId, details)

        let localCache = localCache
        await localCache.communicateRemoteChanges(for: accountId, details)
    }

    private func buildAccountDetails(from snapshot: DocumentSnapshot, keys: [any AccountKey.Type]) -> AccountDetails {
        guard let data = snapshot.data() else {
            return AccountDetails()
        }

        // TODO: just use simple decoder?
        var visitor = FirestoreDecodeVisitor(data: data, in: snapshot.reference)
        let details = keys.acceptAll(&visitor)

        for (key, error) in visitor.errors {
            logger.error("Failed to decode account value from firestore snapshot for key \(key.identifier): \(error)")
        }

        return details
    }

    public func create(_ accountId: String, _ details: AccountDetails) async throws {
        // we just treat it as modifications
        let modifications = try AccountModifications(modifiedDetails: details)
        try await modify(accountId, modifications)
    }

    public func load(_ accountId: String, _ keys: [any AccountKey.Type]) async throws -> AccountDetails? {
        let localCache = localCache
        let cached = await localCache.loadEntry(for: accountId, keys)

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

        if var keys = registeredKeys[accountId] { // we have a snapshot listener in place which we need to update the keys for
            for newKey in modifications.modifiedDetails.keys where keys[ObjectIdentifier(newKey)] == nil {
                keys.updateValue(newKey, forKey: ObjectIdentifier(newKey))
            }

            for removedKey in modifications.removedAccountKeys {
                keys.removeValue(forKey: ObjectIdentifier(removedKey))
            }
        }

        let localCache = localCache
        await localCache.communicateModifications(for: accountId, modifications)
    }

    public func disassociate(_ accountId: String) async {
        guard let registration = listenerRegistrations.removeValue(forKey: accountId) else {
            return
        }
        registration.remove()
        registeredKeys.removeValue(forKey: accountId)

        let localCache = localCache
        await localCache.clearEntry(for: accountId)
    }

    public func delete(_ accountId: String) async throws {
        await disassociate(accountId)

        do {
            try await userDocument(for: accountId)
                .delete()
        } catch {
            throw FirestoreError(error)
        }
    }
}
