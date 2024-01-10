# ``SpeziFirestore``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Easily configure and interact with Firebase Firestore.

## Overview

The ``Firestore`` module allows for easy configuration of Firebase Firestore.

You can configure the ``Firestore`` module in the `SpeziAppDelegate`, e.g. the configure it using the Firebase emulator.
```swift
class FirestoreExampleDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Firestore(settings: .emulator)
            // ...
        }
    }
}
```

## Topics

### Firestore

- ``Firestore``
- ``FirestoreError``
