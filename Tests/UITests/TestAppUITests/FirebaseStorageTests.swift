//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// The `FirebaseStorageTests` require the Firebase Storage Emulator to run at port 9199.
///
/// Refer to https://firebase.google.com/docs/emulator-suite#storage about more information about the
/// Firebase Local Emulator Suite.
final class FirebaseStorageTests: XCTestCase {
    struct FirebaseStorageItem: Decodable {
        let name: String
        let bucket: String
    }
    
   
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        
        try await deleteAllFiles()
        try await Task.sleep(for: .seconds(0.5))
    }
    
    @MainActor
    func testFirebaseStorageFileUpload() async throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssert(app.buttons["FirebaseStorage"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseStorage"].tap()
        
        var documents = try await getAllFiles()
        XCTAssert(documents.isEmpty)
        
        XCTAssert(app.buttons["Upload"].waitForExistence(timeout: 2.0))
        app.buttons["Upload"].tap()
        
        try await Task.sleep(for: .seconds(2.0))
        documents = try await getAllFiles()
        XCTAssertEqual(documents.count, 1)
    }
    
    private func getAllFiles() async throws -> [FirebaseStorageItem] {
        let documentsURL = try XCTUnwrap(
            URL(string: "http://localhost:9199/v0/b/STORAGE_BUCKET/o")
        )
        let (data, response) = try await URLSession.shared.data(from: documentsURL)
        
        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirebaseStorageTests` require the Firebase Storage Emulator to run at port 9199.
                
                Refer to https://firebase.google.com/docs/emulator-suite#storage about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }
        
        struct ResponseWrapper: Decodable {
            let items: [FirebaseStorageItem]
        }
        
        do {
            return try JSONDecoder().decode(ResponseWrapper.self, from: data).items
        } catch {
            return []
        }
    }
    
    private func deleteAllFiles() async throws {
        for storageItem in try await getAllFiles() {
            let url = try XCTUnwrap(
                URL(string: "http://localhost:9199/v0/b/STORAGE_BUCKET/o/\(storageItem.name)")
            )
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let urlResponse = response as? HTTPURLResponse,
                  200...299 ~= urlResponse.statusCode else {
                print(
                    """
                    The `FirebaseStorageTests` require the Firebase Storage Emulator to run at port 9199.
                    
                    Refer to https://firebase.google.com/docs/emulator-suite#storage about more information about the
                    Firebase Local Emulator Suite.
                    """
                )
                throw URLError(.fileDoesNotExist)
            }
        }
    }
}
