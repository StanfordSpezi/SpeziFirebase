# ``SpeziFirebaseAccountStorage``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Store additional account details directly in Firestore.

## Overview

Certain account services, like the account services provided by Firebase, can only store certain account details.
The ``FirestoreAccountStorage`` can be used to store additional account details, that are not supported out of the box by your account services,
inside Firestore in a custom user collection.

For more detailed information, refer to the documentation of ``FirestoreAccountStorage``.

### Example

Once you have [AccountConfiguration](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/initial-setup#Account-Configuration)
and the [FirebaseAccountConfiguration](https://swiftpackageindex.com/stanfordspezi/spezifirebase/documentation/spezifirebaseaccount/firebaseaccountconfiguration)
set up, you can adopt the [AccountStorageConstraint](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountstorageconstraint)
protocol to provide a custom storage for SpeziAccount.


```swift
import FirebaseFirestore
import Spezi
import SpeziAccount
import SpeziFirebaseAccountStorage


actor ExampleStandard: Standard, AccountStorageConstraint {
    // Define the collection where you want to store your additional user data, ...
    static var collection: CollectionReference {
        Firestore.firestore().collection("users")
    }

    // ... define and initialize the `FirestoreAccountStorage` dependency ...
    @Dependency private var accountStorage = FirestoreAccountStorage(storedIn: Self.collection)


    // ... and forward all implementations of `AccountStorageConstraint` to the `FirestoreAccountStorage`.

    public func create(_ identifier: AdditionalRecordId, _ details: SignupDetails) async throws {
        try await accountStorage.create(identifier, details)
    }

    public func load(_ identifier: AdditionalRecordId, _ keys: [any AccountKey.Type]) async throws -> PartialAccountDetails {
        try await accountStorage.load(identifier, keys)
    }

    public func modify(_ identifier: AdditionalRecordId, _ modifications: AccountModifications) async throws {
        try await accountStorage.modify(identifier, modifications)
    }

    public func clear(_ identifier: AdditionalRecordId) async {
        await accountStorage.clear(identifier)
    }

    public func delete(_ identifier: AdditionalRecordId) async throws {
        try await accountStorage.delete(identifier)
    }
}
```

## Topics

### Storage

- ``FirestoreAccountStorage``
