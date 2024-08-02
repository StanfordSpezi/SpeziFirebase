//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

@preconcurrency import FirebaseAuth
import OSLog
import Spezi
import SpeziAccount
import SpeziLocalStorage
import SpeziSecureStorage


private enum UserChange {
    case user(_ user: User)
    case removed
}

private struct UserUpdate {
    let change: UserChange
    var authResult: AuthDataResult?
}


final class FirebaseContext: Module, DefaultInitializable {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "InternalStorage")

    @Dependency private var localStorage = LocalStorage()
    @Dependency private var secureStorage = SecureStorage()
    @Dependency(Account.self)
    private var account


    init() {}
}
