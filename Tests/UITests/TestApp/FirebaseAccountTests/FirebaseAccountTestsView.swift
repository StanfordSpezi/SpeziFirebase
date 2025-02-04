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
    @Environment(AccountTestModel.self)
    private var testModel

    @State var viewState: ViewState = .idle

    @State var showSetup = false
    @State var showOverview = false
    @State private var accountIdFromAnonymousUser: String?

    var body: some View {
        List {
            Section {
                ListRow("User Present on Startup", value: testModel.accountUponConfigure ? "Yes" : "No")
            }
            if let details = account.details {
                Section {
                    accountHeader(for: details)
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
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") {
                                    showSetup = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $showOverview) {
                NavigationStack {
                    AccountOverview(close: .showCloseButton)
                }
            }
    }


    @ViewBuilder
    @MainActor
    private func accountHeader(for details: AccountDetails) -> some View {
        HStack {
            UserProfileView(name: details.name ?? .init(givenName: "NOT FOUND"))
                .frame(height: 30)
            Text(details.userId)
        }
        if details.isAnonymous {
            ListRow("User") {
                Text("Anonymous")
            }
            .onAppear {
                accountIdFromAnonymousUser = details.accountId
            }
        }

        ListRow("New User") {
            Text(details.isNewUser ? "Yes" : "No")
        }

        if let accountIdFromAnonymousUser {
            ListRow("Account Id") {
                if details.accountId == accountIdFromAnonymousUser {
                    Text(verbatim: "Stable")
                        .foregroundStyle(.green)
                } else {
                    Text(verbatim: "Changed")
                        .foregroundStyle(.red)
                }
            }
        }

        AsyncButton("Logout", role: .destructive, state: $viewState) {
            try await account.accountService.logout()
        }
    }
}


#if DEBUG
#Preview {
    NavigationStack {
        FirebaseAccountTestsView()
    }
        .environment(AccountTestModel())
        .previewWith {
            AccountConfiguration(service: InMemoryAccountService(), configuration: .default)
        }
}
#endif
