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
    private let enable: Bool

    @EnvironmentObject private var account: Account

    @Environment(\.authorizationController)
    private var authorizationController


    init(_ enable: Bool) {
        self.enable = enable
    }


    func body(content: Content) -> some View {
        if enable {
            content
                .task {
                    for service in account.registeredAccountServices {
                        guard let firebaseService = service as? any FirebaseAccountService else {
                            continue
                        }

                        await firebaseService.inject(authorizationController: authorizationController)
                    }
                }
        } else {
            content
        }
    }
}


extension View {
    public func firebaseAccount(_ enable: Bool = true) -> some View {
        modifier(FirebaseAccountModifier(enable))
    }
}
