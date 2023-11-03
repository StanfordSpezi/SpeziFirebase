<!--

This source file is part of the Stanford Spezi open-source project.

SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)

SPDX-License-Identifier: MIT
  
-->

# Spezi Firebase

[![Build and Test](https://github.com/StanfordSpezi/SpeziFirebase/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/StanfordSpezi/SpeziFirebase/actions/workflows/build-and-test.yml)
[![codecov](https://codecov.io/gh/StanfordSpezi/SpeziFirebase/branch/main/graph/badge.svg?token=LCRkf3e2lx)](https://codecov.io/gh/StanfordSpezi/SpeziFirebase)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.7706899.svg)](https://doi.org/10.5281/zenodo.7706899)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FStanfordSpezi%2FSpeziFirebase%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/StanfordSpezi/SpeziFirebase)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FStanfordSpezi%2FSpeziFirebase%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/StanfordSpezi/SpeziFirebase)

## Overview

Module that allows you to use the [Google Firebase](https://firebase.google.com/) platform as a managed backend for authentication and data storage in your apps built with the [Spezi framework](https://github.com/StanfordSpezi/Spezi).

## Setup

The Spezi Firebase Module comes pre-configured in the [Spezi Template Application](https://github.com/StanfordSpezi/SpeziTemplateApplication), which is a great way to get started on your Spezi Application. 

If you wish to configure the Spezi Firebase Module manually, follow the instructions below.

### 1. Setup Your Firebase Account

To connect your app to the Firebase cloud platform, you will need to first create an account at [firebase.google.com](https://firebase.google.com) then start the process to [register a new iOS app] (https://firebase.google.com/docs/ios/setup). 

Once your Spezi app is registered with Firebase, place the generated `GoogleService-Info.plist` configuration file into the root of your Xcode project. You do not need to add the Firebase SDKs to your app or initialize Firebase in your app, since the Spezi Firebase Module will handle these tasks for you.

You can also install and run the Firebase Local Emulator Suite for local development. To do this, please follow the [installation instructions](https://firebase.google.com/docs/emulator-suite/install_and_configure).

### 2. Add Spezi Firebase as a Dependency

First, you will need to add the SpeziFirebase Swift package to
[your app in Xcode](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app#) or
[Swift package](https://developer.apple.com/documentation/xcode/creating-a-standalone-swift-package-with-xcode#Add-a-dependency-on-another-Swift-package). When adding the package, select the `SpeziOpenAI` target to add.

### 3. Register the Spezi Firebase Modules

> [!IMPORTANT]
> If your application is not yet configured to use Spezi, follow the [Spezi setup article](https://swiftpackageindex.com/stanfordspezi/spezi/documentation/spezi/initial-setup) to set up the core Spezi infrastructure.

The `SpeziFirebase` module provides components that you can use to configure how your application interacts with Firebase. 

In the example below, we configure our Spezi application to use Firebase Authentication with both email & password login and Sign in With Apple, and Cloud Firestore for data storage. 

```swift
import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziFirebaseStorage
import SpeziFirestore
import SwiftUI


class ExampleDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            AccountConfiguration(configuration: [
                .requires(\.userId),
                .collects(\.name)
            ])
            Firestore()
            FirebaseAccountConfiguration[
                authenticationMethods: [.emailAndPassword, .signInWithApple],
            ]
        }
    }
}
```

## Examples

**To be written**

For more information, please refer to the [API documentation](https://swiftpackageindex.com/StanfordSpezi/SpeziFirebase/documentation).


## The Spezi Template Application

The [Spezi Template Application](https://github.com/StanfordSpezi/SpeziTemplateApplication) provides a great starting point and example using the Spezi Firebase Modules.


## Contributing

Contributions to this project are welcome. Please make sure to read the [contribution guidelines](https://github.com/StanfordSpezi/.github/blob/main/CONTRIBUTING.md) and the [contributor covenant code of conduct](https://github.com/StanfordSpezi/.github/blob/main/CODE_OF_CONDUCT.md) first.


## License

This project is licensed under the MIT License. See [Licenses](https://github.com/StanfordSpezi/SpeziFirebase/tree/main/LICENSES) for more information.

![Spezi Footer](https://raw.githubusercontent.com/StanfordSpezi/.github/main/assets/FooterLight.png#gh-light-mode-only)
![Spezi Footer](https://raw.githubusercontent.com/StanfordSpezi/.github/main/assets/FooterDark.png#gh-dark-mode-only)
