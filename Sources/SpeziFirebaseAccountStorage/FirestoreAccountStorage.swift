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
/// - Important: The `FirestoreAccountStorage` uses the [`accountId`](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountdetails/accountid)
///     of the user for the document identifier. When using the `FirebaseAccountService`, this is the primary, firebase user identifier. Make sure to configure your firestore security rules respectively.
///
/// To configure Firestore as your external storage provider, just supply the ``FirestoreAccountStorage`` as an argument to the `AccountConfiguration`.
///
/// - Note: For more information refer to the
///  [Account Configuration](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/initial-setup#Account-Configuration) article.
///
/// The example below illustrates a configuration example, setting up the `FirebaseAccountService` in combination with the `FirestoreAccountStorage` provider.
///
/// ```swift
/// import Spezi
/// import SpeziAccount
/// import SpeziFirebase
/// import SpeziFirebaseAccount
/// import SpeziFirebaseAccountStorage
///
/// class ExampleAppDelegate: SpeziAppDelegate {
/// override var configuration: Configuration {
///     Configuration {
///         AccountConfiguration(
///             service: FirebaseAccountService(),
///             storageProvider: FirestoreAccountStorage(storeIn: Firestore.firestore().collection("users"))
///             configuration: [/* ... */]
///         )
///     }
/// }
/// ```
///
/// - Important: In order to use the `FirestoreAccountStorage`, you must have [`Firestore`](https://swiftpackageindex.com/stanfordspezi/spezifirebase/main/documentation/spezifirestore/firestore)
///     configured in your app. Refer to the documentation page for more information.
///
/// ## Topics
///
/// ### Configuration
/// - ``init(storeIn:mapping:)``
public actor FirestoreAccountStorage: AccountStorageProvider {
    @Application(\.logger)
    private var logger

    @Dependency(Firestore.self)
    private var firestore
    @Dependency(ExternalAccountStorage.self)
    private var externalStorage
    @Dependency(AccountDetailsCache.self)
    private var localCache

    private let collection: @Sendable () -> CollectionReference
    private let identifierMapping: [String: any AccountKey.Type]? // swiftlint:disable:this discouraged_optional_collection

    private var listenerRegistrations: [String: ListenerRegistration] = [:]
    private var registeredKeys: [String: [ObjectIdentifier: any AccountKey.Type]] = [:]

    /// Configure the Firestore Account Storage provider.
    ///
    /// - Note: The `collection` parameter is passed as an auto-closure. At the time the closure is called the
    ///   [`Firestore`](https://swiftpackageindex.com/stanfordspezi/spezifirebase/main/documentation/spezifirestore/firestore)
    ///   Module has been configured and it is safe to access `Firestore.firestore()` to derive the collection reference.
    ///
    /// ### Custom Identifier Mapping
    ///
    /// By default, the [`identifier`](https://swiftpackageindex.com/stanfordspezi/speziaccount/1.2.4/documentation/speziaccount/accountkey/identifier)
    /// provided by the account key is used as a field name.
    ///
    /// - Parameters:
    ///   - collection: The Firestore collection that all users records are stored in. The `accountId` is used for the name of
    ///     each user document. The field names are derived from the stable `AccountKey/identifier`.
    ///   - identifierMapping: An optional mapping of string identifiers to their `AccountKey`. Use that to customize the scheme used to store account keys
    ///     or provide backwards compatibility with details stored with SpeziAccount 1.0.
    public init(
        storeIn collection: @Sendable @autoclosure @escaping () -> CollectionReference,
        mapping identifierMapping: [String: any AccountKey.Type]? = nil // swiftlint:disable:this discouraged_optional_collection
    ) {
        self.collection = collection // make it a auto-closure. Firestore.firstore() is only configured later on
        self.identifierMapping = identifierMapping
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

            if snapshot?.metadata.hasPendingWrites == true {
                return // ignore updates we caused locally, see https://firebase.google.com/docs/firestore/query-data/listen#events-local-changes
            }

            Task { @Sendable in
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

        guard !details.isEmpty else {
            return
        }

        let localCache = localCache
        await localCache.communicateRemoteChanges(for: accountId, details)

        externalStorage.notifyAboutUpdatedDetails(for: accountId, details)
    }

    private func buildAccountDetails(from snapshot: DocumentSnapshot, keys: [any AccountKey.Type]) -> AccountDetails {
        guard snapshot.exists else {
            return AccountDetails()
        }

        let decoder = Firestore.Decoder()
        decoder.userInfo[.accountDetailsKeys] = keys
        if let identifierMapping {
            decoder.userInfo[.accountKeyIdentifierMapping] = identifierMapping
        }

        do {
            return try snapshot.data(as: AccountDetails.self, decoder: decoder)
        } catch {
            logger.error("Failed to decode account details from firestore snapshot: \(error)")
            return AccountDetails()
        }
    }

    @_documentation(visibility: internal)
    public func load(_ accountId: String, _ keys: [any AccountKey.Type]) async throws -> AccountDetails? {
        let localCache = localCache
        let cached = await localCache.loadEntry(for: accountId, keys)

        if listenerRegistrations[accountId] != nil { // check that there is a snapshot listener in place
            snapshotListener(for: accountId, with: keys)
        }

        return cached
    }

    @_documentation(visibility: internal)
    public func store(_ accountId: String, _ modifications: SpeziAccount.AccountModifications) async throws {
        let document = userDocument(for: accountId)

        if !modifications.modifiedDetails.isEmpty {
            do {
                let encoder = Firestore.Encoder()
                if let identifierMapping {
                    encoder.userInfo[.accountKeyIdentifierMapping] = identifierMapping
                }
                try await document.setData(from: modifications.modifiedDetails, merge: true, encoder: encoder)
            } catch {
                throw FirestoreError(error)
            }
        }

        let removedFields: [String: Any] = modifications.removedAccountDetails.keys.reduce(into: [:]) { result, key in
            result[key.identifier] = FieldValue.delete()
        }

        if !removedFields.isEmpty {
            do {
                try await document.updateData(removedFields)
            } catch {
                throw FirestoreError(error)
            }
        }


        if var keys = registeredKeys[accountId] { // we have a snapshot listener in place which we need to update the keys for
            for newKey in modifications.modifiedDetails.keys where keys[ObjectIdentifier(newKey)] == nil {
                keys.updateValue(newKey, forKey: ObjectIdentifier(newKey))
            }

            for removedKey in modifications.removedAccountKeys {
                keys.removeValue(forKey: ObjectIdentifier(removedKey))
            }

            registeredKeys[accountId] = keys
        }

        let localCache = localCache
        await localCache.communicateModifications(for: accountId, modifications)
    }

    @_documentation(visibility: internal)
    public func disassociate(_ accountId: String) async {
        guard let registration = listenerRegistrations.removeValue(forKey: accountId) else {
            return
        }
        registration.remove()
        registeredKeys.removeValue(forKey: accountId)

        let localCache = localCache
        await localCache.clearEntry(for: accountId)
    }

    @_documentation(visibility: internal)
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
