# ``SpeziFirebaseAccount``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Firebase Auth support for SpeziAccount.

## Overview

This Module adds support for Firebase Auth for SpeziAccount by implementing an
 [`AccountService`](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountservice).

Configure the account service by supplying it to the
 [`AccountConfiguration`](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/accountconfiguration).

> Note: For more information refer to the 
[Account Configuration](https://swiftpackageindex.com/stanfordspezi/speziaccount/documentation/speziaccount/initial-setup#Account-Configuration) article.

```swift
import SpeziAccount
import SpeziFirebaseAccount

class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            AccountConfiguration(
                service: FirebaseAccountService()
                configuration: [/* ... */]
            )
        }
    }
}
```

> Note: Use the ``FirebaseAccountService/init(providers:emulatorSettings:passwordValidation:)`` to customize the enabled
    ``FirebaseAuthProviders`` or supplying Firebase Auth emulator settings.

## Topics

### Configuration

- ``FirebaseAccountService``
- ``FirebaseAuthProviders``

### Account Details

- ``SpeziAccount/AccountDetails/creationDate``
- ``SpeziAccount/AccountDetails/lastSignInDate``

### Errors

- ``FirebaseAccountError``

