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


struct FirebaseSignInWithAppleButton: View {
    @Environment(FirebaseAccountService.self)
    private var service

    @Environment(\.colorScheme)
    private var colorScheme

    @State private var viewState: ViewState = .idle

    var body: some View {
        SignInWithAppleButton(state: $viewState) { request in
            service.onAppleSignInRequest(request: request)
        } onCompletion: { result in
            try await service.onAppleSignInCompletion(result: result)
        }
            .frame(height: 55)
            .viewStateAlert(state: $viewState)
    }

    nonisolated init() {}
}
