//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices


struct ReauthenticationOperation {
    enum Result {
        case success
        case cancelled
    }

    let result: Result
    /// The OAuth Credential if re-authentication was made through Single-Sign-On Provider.
    let credential: ASAuthorizationAppleIDCredential?

    private init(result: Result, credential: ASAuthorizationAppleIDCredential? = nil) {
        self.result = result
        self.credential = credential
    }
}


extension ReauthenticationOperation {
    static var cancelled: ReauthenticationOperation {
        .init(result: .cancelled)
    }

    static var success: ReauthenticationOperation {
        .init(result: .success)
    }


    static func success(with credential: ASAuthorizationAppleIDCredential) -> ReauthenticationOperation {
        .init(result: .success, credential: credential)
    }
}


extension ReauthenticationOperation: Hashable {}
