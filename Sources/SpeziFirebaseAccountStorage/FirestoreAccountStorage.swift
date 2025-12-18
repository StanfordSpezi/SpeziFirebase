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


private struct AccountDetailsConfiguration: DecodingConfigurationProviding, EncodingConfigurationProviding {
    @TaskLocal static var decodingConfiguration = AccountDetails.DecodingConfiguration(keys: [])
    @TaskLocal static var encodingConfiguration = AccountDetails.EncodingConfiguration()
}


// Firebase doesn't support DecodableWithConfiguration yet. So that's our workaround.
// Feature is tracked as https://github.com/firebase/firebase-ios-sdk/issues/13552
private struct AccountDetailsWrapper: Codable {
    let details: AccountDetails

    init(details: AccountDetails) {
        self.details = details
    }

    init(from decoder: any Decoder) throws {
        self.details = try AccountDetails(from: decoder, configuration: AccountDetailsConfiguration.decodingConfiguration)
    }

    func encode(to encoder: any Encoder) throws {
        try details.encode(to: encoder, configuration: AccountDetailsConfiguration.encodingConfiguration)
    }
}


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
/// - ``init(storeIn:mapping:encoder:decoder:)``
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
    private let encoder: FirebaseFirestore.Firestore.Encoder
    private let decoder: FirebaseFirestore.Firestore.Decoder

    private var listenerRegistrations: [String: any ListenerRegistration] = [:]
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
    /// ### Custom Encoder/Decoder Configuration
    ///
    /// For advanced use cases, such as integrating with libraries like PhoneNumberKit where you might want to set specific encoding/decoding strategies,
    /// you can provide custom encoder and decoder instances with specific userInfo configurations.
    ///
    /// ```swift
    /// private var customEncoder: FirebaseFirestore.Firestore.Encoder {
    ///     let encoder = FirebaseFirestore.Firestore.Encoder()
    ///     encoder.userInfo[.phoneNumberEncodingStrategy] = PhoneNumberDecodingStrategy.e164
    ///     return encoder
    /// }
    ///
    /// private var customDecoder: FirebaseFirestore.Firestore.Decoder {
    ///     let decoder = FirebaseFirestore.Firestore.Decoder()
    ///     decoder.userInfo[.phoneNumberDecodingStrategy] = PhoneNumberDecodingStrategy.e164
    ///     return decoder
    /// }
    ///
    /// override var configuration: Configuration {
    ///     Configuration(standard: YourStandard()) {
    ///         AccountConfiguration(
    ///             storageProvider: FirestoreAccountStorage(
    ///                 storeIn: Firestore.userCollection,
    ///                 mapping: [
    ///                     "phoneNumbers": AccountKeys.phoneNumbers,
    ///                     // ... other mappings ...
    ///                 ],
    ///                 encoder: customEncoder,
    ///                 decoder: customDecoder
    ///             ),
    ///         // ... other configuration ...
    ///         )
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - collection: The Firestore collection that all users records are stored in. The `accountId` is used for the name of
    ///     each user document. The field names are derived from the stable `AccountKey/identifier`.
    ///   - identifierMapping: An optional mapping of string identifiers to their `AccountKey`. Use that to customize the scheme used to store account keys
    ///     or provide backwards compatibility with details stored with SpeziAccount 1.0.
    ///   - encoder: A custom Firestore encoder instance with specific userInfo configuration. If not provided, a default encoder will be used.
    ///   - decoder: A custom Firestore decoder instance with specific userInfo configuration. If not provided, a default decoder will be used.
    public init(
        storeIn collection: @Sendable @autoclosure @escaping () -> CollectionReference,
        mapping identifierMapping: [String: any AccountKey.Type]? = nil, // swiftlint:disable:this discouraged_optional_collection
        encoder: FirebaseFirestore.Firestore.Encoder = FirebaseFirestore.Firestore.Encoder(),
        decoder: FirebaseFirestore.Firestore.Decoder = FirebaseFirestore.Firestore.Decoder()
    ) {
        self.collection = collection // make it a auto-closure. Firestore.firstore() is only configured later on
        self.identifierMapping = identifierMapping
        self.encoder = encoder
        self.decoder = decoder
    }


    nonisolated private func userDocument(for accountId: String) -> DocumentReference {
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

        let localCache = localCache
        await localCache.communicateRemoteChanges(for: accountId, details)

        externalStorage.notifyAboutUpdatedDetails(for: accountId, details)
    }

    private func buildAccountDetails(from snapshot: DocumentSnapshot, keys: [any AccountKey.Type]) -> AccountDetails {
        guard snapshot.exists else {
            return AccountDetails()
        }

        let configuration = AccountDetails.DecodingConfiguration(keys: keys, identifierMapping: identifierMapping)

        do {
            return try AccountDetailsConfiguration.$decodingConfiguration.withValue(configuration) {
                try snapshot.data(as: AccountDetailsWrapper.self, decoder: decoder).details
            }
        } catch {
            logger.error("Failed to decode account details from firestore snapshot: \(error)")
            return AccountDetails()
        }
    }

    @_documentation(visibility: internal)
    public func load(_ accountId: String, _ keys: [any AccountKey.Type]) async -> AccountDetails? {
        let localCache = localCache
        let cached = await localCache.loadEntry(for: accountId, keys)

        if listenerRegistrations[accountId] == nil { // check that there is a snapshot listener in place
            snapshotListener(for: accountId, with: keys)
        }

        return cached
    }

    @_documentation(visibility: internal)
    public func store(_ accountId: String, _ modifications: SpeziAccount.AccountModifications) async throws {
        let document = userDocument(for: accountId)
        let batch = Firestore.firestore().batch()

        if !modifications.modifiedDetails.isEmpty {
            let configuration = AccountDetails.EncodingConfiguration(identifierMapping: identifierMapping)

            try AccountDetailsConfiguration.$encodingConfiguration.withValue(configuration) {
                let wrapper = AccountDetailsWrapper(details: modifications.modifiedDetails)
                let encoded = try encoder.encode(wrapper)

                batch.setData(encoded, forDocument: document, merge: true)
            }
        }

        let removedFields: [String: Any] = modifications.removedAccountDetails.keys.reduce(into: [:]) { result, key in
            result[key.identifier] = FieldValue.delete()
        }

        if !removedFields.isEmpty {
            batch.updateData(removedFields, forDocument: document)
        }

        do {
            try await batch.commit()
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
