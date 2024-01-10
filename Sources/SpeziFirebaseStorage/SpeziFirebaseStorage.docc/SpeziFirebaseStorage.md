# ``SpeziFirebaseStorage``

<!--

This source file is part of the Stanford Spezi open-source project

SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT

-->

Firebase Storage related components.

## Overview

Configures the Firebase Storage that can then be used within any application via `Storage.storage()`.

The ``FirebaseStorageConfiguration`` can be used to connect to the Firebase Storage emulator:
```
class ExampleAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
            // ...
        }
    }
}
```

## Topics

### Firebase Storage

- ``FirebaseStorageConfiguration``
