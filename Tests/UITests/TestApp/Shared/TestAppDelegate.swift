//
// This source file is part of the CardinalKit open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CardinalKit
import CardinalKitFirebaseAccount
import CardinalKitFirestore
import CardinalKitFirestorePrefixUserIdAdapter
import SwiftUI


class TestAppDelegate: CardinalKitAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: TestAppStandard()) {
            Firestore(
                settings: .emulator
            )
            FirebaseAccountConfiguration(emulatorSettings: (host: "localhost", port: 9099))
        }
    }
}
