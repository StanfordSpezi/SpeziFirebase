//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziPersonalInfo
import SpeziViews
import SwiftUI


struct FirebaseAccountTestsView: View {
    @Environment(Account.self)
    var account

    @State var viewState: ViewState = .idle

    @State var showSetup = false
    @State var showOverview = false

    var body: some View {
        List {
            if let details = account.details {
                HStack {
                    UserProfileView(name: details.name ?? .init(givenName: "NOT FOUND"))
                        .frame(height: 30)
                    Text(details.userId)
                }
                if details.isAnonymous {
                    ListRow("User") {
                        Text("Anonymous")
                    }
                }

                ListRow("New User") {
                    Text(details.isNewUser ? "Yes" : "No")
                }

                AsyncButton("Logout", role: .destructive, state: $viewState) {
                    try await account.accountService.logout()
                }
            }
            Button("Account Setup") {
                showSetup = true
            }
            Button("Account Overview") {
                showOverview = true
            }
        }
            .sheet(isPresented: $showSetup) {
                NavigationStack {
                    AccountSetup()
                        .toolbar {
                            toolbar(closing: $showSetup)
                        }
                }
            }
            .sheet(isPresented: $showOverview) {
                NavigationStack {
                    AccountOverview(close: .showCloseButton)
                }
            }
    }


    @ToolbarContentBuilder
    func toolbar(closing flag: Binding<Bool>) -> some ToolbarContent {
        ToolbarItemGroup(placement: .cancellationAction) {
            Button("Close") {
                flag.wrappedValue = false
            }
        }
    }
}
