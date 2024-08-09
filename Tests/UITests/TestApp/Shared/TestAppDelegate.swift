//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import Spezi
import SpeziAccount
@_spi(Internal)
import SpeziFirebaseAccount
import SpeziFirebaseAccountStorage
import SpeziFirebaseStorage
import SpeziFirestore
import SwiftUI


class TestAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            let configuration: AccountValueConfiguration = FeatureFlags.accountStorageTests
            ? [
                .requires(\.userId),
                .requires(\.name),
                .requires(\.biography)
            ]
            : [
                .requires(\.userId),
                .collects(\.name)
            ]

            let service = FirebaseAccountService(
                providers: [.emailAndPassword, .signInWithApple, .anonymousButton],
                emulatorSettings: (host: "localhost", port: 9099)
            )

            if FeatureFlags.accountStorageTests {
                AccountConfiguration(
                    service: service,
                    storageProvider: FirestoreAccountStorage(storeIn: Firestore.firestore().collection("users")),
                    configuration: configuration
                )
            } else {
                AccountConfiguration(service: service, configuration: configuration)
            }

            Firestore(settings: .emulator)
            FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
        }
    }
}
