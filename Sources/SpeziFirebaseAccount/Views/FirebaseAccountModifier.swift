//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import SpeziAccount
import SwiftUI


struct FirebaseAccountModifier: ViewModifier {
    @EnvironmentObject private var account: Account

    @Environment(\.authorizationController)
    private var authorizationController

    func body(content: Content) -> some View {
        content
            .task {
                for service in account.registeredAccountServices {
                    guard let firebaseService = service as? any FirebaseAccountService else {
                        continue
                    }

                    await firebaseService.inject(authorizationController: authorizationController)
                }
            }
    }
}


extension View {
    public func firebaseAccount() -> some View {
        modifier(FirebaseAccountModifier())
    }
}
