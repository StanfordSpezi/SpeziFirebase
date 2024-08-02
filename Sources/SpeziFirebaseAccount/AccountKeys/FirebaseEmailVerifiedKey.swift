//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import SpeziAccount
import SwiftUI

private struct EntryView: DataEntryView {
    @Binding private var value: Bool

    var body: some View {
        BoolEntryView(\.isEmailVerified, $value)
            .disabled(true) // you cannot manually change that
    }

    init(_ value: Binding<Bool>) {
        _value = value
    }
}


extension AccountDetails {
    /// Flag indicating if the firebase account has a verified email address.
    ///
    /// - Important: This key is read-only and cannot be modified.
    @AccountKey(
        name: LocalizedStringResource("E-Mail Verified", bundle: .atURL(from: .module)),
        as: Bool.self,
        entryView: EntryView.self
    )
    public var isEmailVerified: Bool? // swiftlint:disable:this discouraged_optional_boolean
}


@KeyEntry(\.isEmailVerified)
public extension AccountKeys {} // swiftlint:disable:this no_extension_access_modifier
