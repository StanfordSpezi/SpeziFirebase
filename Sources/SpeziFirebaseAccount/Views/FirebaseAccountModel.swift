//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import Observation
import SwiftUI


@Observable
class FirebaseAccountModel {
    var authorizationController: AuthorizationController?

    init() {}
}
