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
    
    var body: some View {
        List {
            if let details = account.details {
                HStack {
                    UserProfileView(name: details.name)
                        .frame(height: 30)
                    Text(details.userId) // TODO specific email key?
                }

                // TODO rename this thing and move to SpeziViews!
                AsyncDataEntrySubmitButton("Logout", state: $viewState) {
                    try await details.accountService.logout()
                }
            } else {
                AccountSetup() // TODO external parameter name
            }
        }
    }
}
