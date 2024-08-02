//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziAccount
import SwiftUI


struct FirebaseLoginView: View {
    @Environment(FirebaseAccountService.self)
    private var service


    var body: some View {
        // you can customize appearance using the `preferredAccountSetupStyle(_:)` modifier
        AccountSetupProviderView { credential in
            try await service.login(userId: credential.userId, password: credential.password)
        } signup: { details in
            try await service.signUp(with: details)
        } resetPassword: { userId in
            try await service.resetPassword(userId: userId)
        }
    }

    nonisolated init() {}
}
