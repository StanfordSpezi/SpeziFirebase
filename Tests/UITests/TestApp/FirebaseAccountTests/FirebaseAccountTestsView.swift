//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseAuth
import Spezi
import SpeziAccount
import SpeziFirebaseAccount
import SpeziViews
import SwiftUI


struct FirebaseAccountTestsView: View {
    @EnvironmentObject var account: Account

    @State var viewState: ViewState = .idle

    @State var showSetup = false
    @State var showOverview = false
    @State var isEditing = false
    
    var body: some View {
        List {
            if let details = account.details {
                HStack {
                    UserProfileView(name: details.name ?? .init(givenName: "NOT FOUND"))
                        .frame(height: 30)
                    Text(details.userId)
                }
            }
            Button("Account Setup") {
                showSetup = true
            }
            Button("Account Overview") {
                showOverview = true
            }
                .sheet(isPresented: $showSetup) {
                    NavigationStack {
                        AccountSetup()
                    }
                        .toolbar {
                            toolbar(closing: $showSetup)
                        }
                }
                .sheet(isPresented: $showOverview) {
                    NavigationStack {
                        AccountOverview(isEditing: $isEditing)
                    }
                        .toolbar {
                            toolbar(closing: $showOverview)
                        }
                }
        }
    }


    @ToolbarContentBuilder
    func toolbar(closing flag: Binding<Bool>) -> some ToolbarContent {
        if !isEditing {
            ToolbarItemGroup(placement: .cancellationAction) {
                Button("Close") {
                    flag.wrappedValue = false
                }
            }
        }
    }
}
