//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import Spezi
import SpeziFirestore
import SpeziViews
import SwiftUI


/// The Firestore tests require the Firebase Firestore Emulator to run at port 8080.
///
/// Refer to https://firebase.google.com/docs/emulator-suite/connect_firestore about more information about the
/// Firebase Local Emulator Suite.
struct FirestoreDataStorageTestsView: View {
    @State private var viewState: ViewState = .idle
    @State private var element = TestAppType()
    
    
    var body: some View {
        Form {
            Text("The Firestore tests require the Firebase Firestore Emulator to run at port 8080.")
            Section("Element Information") {
                TextField(
                    "Id",
                    text: $element.id,
                    prompt: Text("Enter the element's identifier.")
                )
                TextField(
                    "Context",
                    text: $element.content,
                    prompt: Text("Enter the element's optional context.")
                )
            }
            Section("Actions") {
                Button("Upload Element") {
                    uploadElement()
                }
                Button(
                    role: .destructive,
                    action: {
                        deleteElement()
                    },
                    label: {
                        Text("Delete Element")
                    }
                )
            }
                .disabled(viewState == .processing)
        }
            .viewStateAlert(state: $viewState)
            .navigationTitle("FirestoreDataStorage")
    }
    
    
    @MainActor
    private func uploadElement() {
        viewState = .processing
        Task {
            do {
                try await Firestore.firestore().collection("Test").document(element.id).setData(from: element)
                viewState = .idle
            } catch {
                viewState = .error(FirestoreError(error))
            }
        }
    }
    
    @MainActor
    private func deleteElement() {
        viewState = .processing
        Task {
            do {
                try await Firestore.firestore().collection("Test").document(element.id).delete()
                viewState = .idle
            } catch {
                viewState = .error(FirestoreError(error))
            }
        }
    }
}
