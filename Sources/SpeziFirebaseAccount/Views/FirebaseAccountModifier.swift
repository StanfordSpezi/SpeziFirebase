//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import OSLog
import SwiftUI


struct FirebaseAccountModifier: ViewModifier {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "FirebaseAccount")

    @Environment(\.authorizationController)
    private var authorizationController

    @Environment(FirebaseAccountModel.self)
    private var firebaseModel


    nonisolated init() {}


    func body(content: Content) -> some View {
        content
            .task {
                firebaseModel.authorizationController = authorizationController
                Self.logger.debug("Retrieved the Sign in With Apple authorization controller from the SwiftUI environment!")
            }
    }
}
