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
        Configuration {
            AccountConfiguration(configuration: [
                .requires(\.userId),
                .collects(\.name)
            ])
            Firestore(settings: .emulator)
            FirebaseAccountConfiguration(
                authenticationMethods: [.emailAndPassword, .signInWithApple],
                emulatorSettings: (host: "localhost", port: 9099)
            )
            FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
        }
    }
}
