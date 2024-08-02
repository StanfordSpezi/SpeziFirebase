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
    @Environment(\.defaultErrorDescription)
    private var defaultErrorDescription

    @State private var viewState: ViewState = .idle

    var body: some View {
        SignInWithAppleButton { request in
            service.onAppleSignInRequest(request: request)
        } onCompletion: { result in
            Task {
                do {
                    try await service.onAppleSignInCompletion(result: result)
                } catch {
                    if let localizedError = error as? LocalizedError {
                        viewState = .error(localizedError)
                    } else {
                        viewState = .error(AnyLocalizedError(
                            error: error,
                            defaultErrorDescription: defaultErrorDescription
                        ))
                    }
                }
            }
        }
            .viewStateAlert(state: $viewState)
    }

    nonisolated init() {}
}
