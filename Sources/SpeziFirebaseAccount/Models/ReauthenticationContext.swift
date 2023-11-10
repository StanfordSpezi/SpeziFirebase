//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


enum ReauthenticationResult {
    case cancelled
    case password(_ password: String)
}


struct ReauthenticationContext {
    /// The userId for which we are doing the re-authentication.
    let userId: String

    /// A continuation that accepts the password the user, once retrieved!
    let continuation: CheckedContinuation<ReauthenticationResult, Never>
}
