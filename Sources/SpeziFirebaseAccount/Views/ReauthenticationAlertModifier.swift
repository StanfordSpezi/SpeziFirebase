//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziAccount
import SpeziValidation
import SpeziViews
import SwiftUI


struct ReauthenticationAlertModifier: ViewModifier {
    @Environment(FirebaseAccountModel.self)
    private var firebaseModel: FirebaseAccountModel


    @ValidationState private var validation

    @State private var password: String = ""


    private var isPresented: Binding<Bool> {
        Binding {
            firebaseModel.isPresentingReauthentication
        } set: { newValue in
            firebaseModel.isPresentingReauthentication = newValue
        }
    }

    private var context: ReauthenticationContext? {
        firebaseModel.reauthenticationContext
    }


    func body(content: Content) -> some View {
        content
            .alert(Text("Authentication Required", bundle: .module), isPresented: isPresented, presenting: context) { context in
                SecureField(text: $password) {
                    Text(PasswordFieldType.password.localizedStringResource)
                }
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .validate(input: password, rules: .nonEmpty)
                    .receiveValidation(in: $validation)

                Button(role: .cancel, action: {
                    context.continuation.resume(returning: .cancelled)
                }) {
                    Text("Cancel", bundle: .module)
                }

                Button(action: {
                    guard validation.validateSubviews() else {
                        context.continuation.resume(returning: .cancelled)
                        return
                    }
                    context.continuation.resume(returning: .password(password))
                }) {
                    Text("Login", bundle: .module)
                }
            } message: { context in
                Text("Please enter your password for \(context.userId).")
            }
    }
}


#if DEBUG
#Preview {
    let model = FirebaseAccountModel()

    return Text(verbatim: "")
        .modifier(ReauthenticationAlertModifier())
        .environment(model)
        .task {
            let password = await model.reauthenticateUser(userId: "lelandstandford@stanford.edu")
            print("Password: \(password)")
        }
}
#endif
