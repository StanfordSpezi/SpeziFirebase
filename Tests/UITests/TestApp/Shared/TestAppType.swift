//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Spezi
import SpeziFirestore


struct TestAppType: Identifiable, Codable, Sendable {
    var id: String
    var content: Int
    
    
    init(id: String, content: Int = 42) {
        self.id = id
        self.content = content
    }
}
