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

> Important: The `FirestoreAccountStorage` uses the [`accountId`](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountdetails/accountid)
  of the user for the document identifier. When using the `FirebaseAccountService`, this is the primary, firebase user identifier. Make sure to configure your firestore security rules respectively.

To configure Firestore as your external storage provider, just supply the ``FirestoreAccountStorage`` as an argument to the `AccountConfiguration`.

> Note: For more information refer to the
 [Account Configuration](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/initial-setup#Account-Configuration) article.

The example below illustrates a configuration example, setting up the `FirebaseAccountService` in combination with the `FirestoreAccountStorage` provider.

```swift
import Spezi
import SpeziAccount
import SpeziFirebase
import SpeziFirebaseAccount
import SpeziFirebaseAccountStorage

class ExampleAppDelegate: SpeziAppDelegate {
override var configuration: Configuration {
    Configuration {
        AccountConfiguration(
            service: FirebaseAccountService(),
            storageProvider: FirestoreAccountStorage(storeIn: Firestore.firestore().collection("users"))
            configuration: [/* ... */]
        )
    }
}
```

> Important: In order to use the `FirestoreAccountStorage`, you must have [`Firestore`](https://swiftpackageindex.com/stanfordspezi/spezifirebase/main/documentation/spezifirestore/firestore)
    configured in your app. Refer to the documentation page for more information.

## Topics

### Configuration

- ``FirestoreAccountStorage``
