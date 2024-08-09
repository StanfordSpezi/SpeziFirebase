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


/// An alert to authorize security-sensitive operations.
///
/// The alert will request the user's password to authorize security-sensitive operations like account deletion or change of
/// sensitive account details.
public struct FirebaseSecurityAlert: ViewModifier {
    @Environment(FirebaseAccountModel.self)
    private var firebaseModel: FirebaseAccountModel


    @ValidationState private var validation

    @State private var password: String = ""
    @State private var isActive = false


    @MainActor private var isPresented: Binding<Bool> {
        Binding {
            firebaseModel.isPresentingReauthentication && isActive
        } set: { newValue in
            firebaseModel.isPresentingReauthentication = newValue
        }
    }

    @MainActor private var context: ReauthenticationContext? {
        firebaseModel.reauthenticationContext
    }

    nonisolated init() {}


    public func body(content: Content) -> some View {
        content
            .onAppear {
                isActive = true
            }
            .onDisappear {
                isActive = false
            }
            .alert(Text("Authentication Required", bundle: .module), isPresented: isPresented, presenting: context) { context in
                SecureField(text: $password) {
                    Text(PasswordFieldType.password.localizedStringResource)
                }
                .textContentType(.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .validate(input: password, rules: .nonEmpty)
                .receiveValidation(in: $validation)
                .onDisappear {
                    password = "" // make sure we don't hold onto passwords
                }

                Button(role: .cancel) {
                    context.continuation.resume(returning: .cancelled)
                } label: {
                    Text("Cancel", bundle: .module)
                }

                Button {
                    guard validation.validateSubviews() else {
                        context.continuation.resume(returning: .cancelled)
                        return
                    }
                    context.continuation.resume(returning: .password(password))
                } label: {
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
        .modifier(FirebaseSecurityAlert())
        .environment(model)
        .task {
            let password = await model.reauthenticateUser(userId: "lelandstandford@stanford.edu")
            print("Password: \(password)")
        }
}
#endif
