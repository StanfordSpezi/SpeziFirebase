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
    private class Logout: Module {
        @Application(\.logger)
        private var logger

        @Dependency(Account.self)
        private var account
        @Dependency(FirebaseAccountService.self)
        private var service

        func configure() {
            if account.signedIn {
                Task { [logger, service] in
                    do {
                        logger.info("Performing initial logout!")
                        try await service.logout()
                    } catch {
                        logger.error("Failed initial logout")
                    }
                }
            }
        }
    }

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

            Logout()

            Firestore(settings: .emulator)
            FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
        }
    }
}
