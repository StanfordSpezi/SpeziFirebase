//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziFirebaseAccount
import SpeziFirestore
import SwiftUI


class TestAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration {
            Firestore(settings: .emulator)
            FirebaseAccountConfiguration(emulatorSettings: (host: "localhost", port: 9099))
        }
    }
}
