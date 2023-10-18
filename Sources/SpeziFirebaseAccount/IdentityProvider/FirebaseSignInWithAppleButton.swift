//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import SwiftUI


struct FirebaseSignInWithAppleButton: View {
    private let accountService: FirebaseIdentityProviderAccountService

    @Environment(\.colorScheme)
    private var colorScheme

    var body: some View {
        // TODO do we need to control the label!
        SignInWithAppleButton(onRequest: { request in
            accountService.onAppleSignInRequest(request: request)
        }, onCompletion: { result in
            // TODO display error!
            try? accountService.onAppleSignInCompletion(result: result)
        })
            .frame(height: 55)
            .signInWithAppleButtonStyle(colorScheme == .light ? .black : .white)
    }

    init(service: FirebaseIdentityProviderAccountService) {
        self.accountService = service
    }
}
