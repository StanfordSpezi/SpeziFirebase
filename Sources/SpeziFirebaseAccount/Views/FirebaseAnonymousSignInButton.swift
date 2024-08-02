//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziAccount
import SpeziViews
import SwiftUI


struct FirebaseAnonymousSignInButton: View {
    @Environment(FirebaseAccountService.self)
    private var service
    @Environment(\.colorScheme)
    private var colorScheme

    @State private var viewState: ViewState = .idle

    private var color: Color {
        // see https://firebase.google.com/brand-guidelines/
        switch colorScheme {
        case .dark:
            return Color(red: 255.0 / 255, green: 145.0 / 255, blue: 0) // firebase orange
        case .light:
            fallthrough
        @unknown default:
            return Color(red: 255.0 / 255, green: 196.0 / 255, blue: 0) // firebase yellow
        }
    }

    var body: some View {
        AccountServiceButton(state: $viewState) {
            try await service.signUpAnonymously()
        } label: {
            Text("Anonymous Signup", bundle: .module)
        }
            .tint(color)
    }

    nonisolated init() {}
}
