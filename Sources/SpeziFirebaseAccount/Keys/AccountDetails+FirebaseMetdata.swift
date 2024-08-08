//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2024 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziAccount
import SpeziFoundation


extension AccountDetails {
    private struct CreationDateKey: KnowledgeSource {
        typealias Anchor = AccountAnchor
        typealias Value = Date
    }

    private struct LastSignInDateKey: KnowledgeSource {
        typealias Anchor = AccountAnchor
        typealias Value = Date
    }

    /// The creation date of the Firebase user.
    public var creationDate: Date? {
        get {
            self[CreationDateKey.self]
        }
        set {
            self[CreationDateKey.self] = newValue
        }
    }

    /// The last sign in date of the Firebase user.
    public var lastSignInDate: Date? {
        get {
            self[LastSignInDateKey.self]
        }
        set {
            self[LastSignInDateKey.self] = newValue
        }
    }
}
