//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziAccount

// TODO docs
public struct FirebaseEmailVerifiedKey: OptionalAccountValueKey {
    public typealias Value = Bool
}

// this property is not supported in SignupRequests
extension AccountDetails {
    public var isEmailVerified: Bool? { // swiftlint:disable:this discouraged_optional_boolean
        storage[FirebaseEmailVerifiedKey.self]
    }
}
