# ``SpeziFirebaseAccount``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Firebase Auth support for SpeziAccount.

## Overview

This Module adds support for Firebase Auth for SpeziAccount by implementing a respective
 [AccountService](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountservice).

The `FirebaseAccountConfiguration` can, e.g., be used to to connect to the Firebase Auth emulator:
```
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            FirebaseAccountConfiguration(emulatorSettings: (host: "localhost", port: 9099))
            // ...
        }
    }
}
```

## Topics

### Firebase Account

- ``FirebaseAccountConfiguration``
- ``FirebaseAuthAuthenticationMethods``

### Account Keys

- ``FirebaseEmailVerifiedKey``
- ``SpeziAccount/AccountValues/isEmailVerified``
- ``SpeziAccount/AccountKeys/isEmailVerified``

