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


/// Flag indicating if the firebase account has a verified email address.
///
/// - Important: This key is read-only and cannot be modified.
public struct FirebaseEmailVerifiedKey: AccountKey {
    public typealias Value = Bool
    public static let name: LocalizedStringResource = "E-Mail Verified" // not translated as never shown
    public static let category: AccountKeyCategory = .other
    public static let initialValue: InitialValue<Bool> = .default(false)
}


extension AccountKeys {
    /// The email-verified ``FirebaseEmailVerifiedKey`` metatype.
    public var isEmailVerified: FirebaseEmailVerifiedKey.Type {
        FirebaseEmailVerifiedKey.self
    }
}


extension FirebaseEmailVerifiedKey {
    public struct DataEntry: DataEntryView {
        public typealias Key = FirebaseEmailVerifiedKey

        public var body: some View {
            Text(verbatim: "The FirebaseEmailVerifiedKey cannot be set!")
        }

        public init(_ value: Binding<Value>) {}
    }
}
