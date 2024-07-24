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
    @Environment(FirebaseAccountConfiguration.self)
    private var service


    var body: some View {
        UserIdPasswordEmbeddedView { credential in
            try await service.login(userId: credential.userId, password: credential.password)
        } signup: { details in
            try await service.signUp(signupDetails: details)
        } resetPassword: { userId in
            try await service.resetPassword(userId: userId)
        }
    }

    nonisolated init() {}
}
