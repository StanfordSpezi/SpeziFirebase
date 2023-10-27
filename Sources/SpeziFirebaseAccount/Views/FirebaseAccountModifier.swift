//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import AuthenticationServices
import OSLog
import SpeziAccount
import SwiftUI


struct FirebaseAccountModifier: ViewModifier {
    static let logger = Logger(subsystem: "edu.stanford.spezi.firebase", category: "FirebaseAccount")

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
                    Self.logger.debug("Looking at \(account.registeredAccountServices.count) account services to inject authorization controller ...")
                    for service in account.registeredAccountServices {
                        guard let firebaseService = service.castFirebaseAccountService() else {
                            continue
                        }

                        Self.logger.debug("Injecting authorization controller into \(type(of: firebaseService))")
                        await firebaseService.inject(authorizationController: authorizationController)
                    }
                }
        } else {
            content
        }
    }
}


extension AccountService {
    fileprivate func castFirebaseAccountService() -> (any FirebaseAccountService)? {
        if let firebaseService = self as? any FirebaseAccountService {
            return firebaseService
        }

        let mirror = Mirror(reflecting: self) // checking if its a StandardBacked account service
        if let accountService = mirror.children["accountService"],
           let firebaseService = accountService as? any FirebaseAccountService {
            return firebaseService
        }

        return nil
    }
}


extension View {
    /// Configure FirebaseAccount for your App.
    ///
    /// This modifier is currently required to be placed on the global App level, such that FirebaseAccount can
    /// access the SwiftUI environment.
    ///
    /// - Note: If not used, this will affect the functionality of the Firebase Single Sign-On Provider.
    /// - Parameter enable: Flag indicating if the account module is enabled.
    public func firebaseAccount(_ enable: Bool = true) -> some View {
        modifier(FirebaseAccountModifier(enable))
    }
}
