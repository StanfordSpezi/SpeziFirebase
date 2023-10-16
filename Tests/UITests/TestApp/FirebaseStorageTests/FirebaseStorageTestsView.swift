//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseStorage
import PDFKit
import SpeziViews
import SwiftUI


struct FirebaseStorageTestsView: View {
    @State private var viewState: ViewState = .idle
    
    
    var body: some View {
        Button("Upload") {
            uploadFile()
        }
            .buttonStyle(.borderedProminent)
            .disabled(viewState == .processing)
            .viewStateAlert(state: $viewState)
            .navigationTitle("FirestoreDataStorage")
    }


    @MainActor
    private func uploadFile() {
        viewState = .processing
        Task {
            do {
                let metadata = StorageMetadata()
                metadata.contentType = "text/plain"
                _ = try await Storage.storage().reference().child("test.txt")
                    .putDataAsync("Hello World!".data(using: .utf8) ?? .init(), metadata: metadata)
                viewState = .idle
            } catch {
                viewState = .error(AnyLocalizedError(error: error))
            }
        }
    }
}
