//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziFirebaseStorage
import SpeziFirestore
import SwiftUI


class TestAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        if FeatureFlags.accountStorageTests {
            return Configuration(standard: AccountStorageTestStandard(), configurationsClosure)
        } else {
            return Configuration(configurationsClosure)
        }
    }

    var configurationsClosure: () -> ModuleCollection {
        {
            self.configurations
        }
    }

    @ModuleBuilder var configurations: ModuleCollection {
        if FeatureFlags.accountStorageTests {
            AccountConfiguration(configuration: [
                .requires(\.userId),
                .requires(\.name),
                .requires(\.biography)
            ])
        } else {
            AccountConfiguration(configuration: [
                .requires(\.userId),
                .collects(\.name)
            ])
        }
        Firestore(settings: .emulator)
        FirebaseAccountConfiguration(
            authenticationMethods: [.emailAndPassword, .signInWithApple],
            emulatorSettings: (host: "localhost", port: 9099)
        )
        FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
    }
}
