//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2026 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziAccount


extension AccountDetails {
    @AccountKey(name: "Active Session", as: String.self)
    public var activeSessionId: String?
}


@KeyEntry(\.activeSessionId)
extension AccountKeys {}
