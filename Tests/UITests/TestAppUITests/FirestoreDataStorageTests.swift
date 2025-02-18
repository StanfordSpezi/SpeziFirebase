//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// The `FirestoreDataStorageTests` require the Firebase Firestore Emulator to run at port 8080.
///
/// Refer to https://firebase.google.com/docs/emulator-suite/connect_firestore about more information about the
/// Firebase Local Emulator Suite.
final class FirestoreDataStorageTests: XCTestCase {
    private struct FirestoreElement: Decodable, Equatable {
        let name: String
        let fields: [String: [String: String]]
        
        
        init(name: String, fields: [String: [String: String]]) {
            self.name = name
            self.fields = fields
        }
        
        init(id: String, content: String) {
            self.init(
                name: "projects/spezifirebaseuitests/databases/(default)/documents/Test/\(id)",
                fields: [
                    "id": [
                        "stringValue": id
                    ],
                    "content": [
                        "stringValue": content
                    ]
                ]
            )
        }
        
        
        subscript(dynamicMember member: String) -> [String: String] {
            fields[member, default: [:]]
        }
    }
    
    
    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false

        try await Self.deleteAllDocuments()
        try await Task.sleep(for: .seconds(0.5))
    }
    
    
    @MainActor
    func testFirestoreAdditions() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["FirestoreDataStorage"].tap()
        
        var documents = try await Self.getAllDocuments()
        XCTAssert(documents.isEmpty)
        
        try add(id: "Identifier1", content: "1")
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await Self.getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )
    }
    
    @MainActor
    func testFirestoreMerge() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["FirestoreDataStorage"].tap()
        
        var documents = try await Self.getAllDocuments()
        XCTAssert(documents.isEmpty)
        
        try merge(id: "Identifier1", content: "1")
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await Self.getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )
    }
    
    @MainActor
    func testFirestoreUpdate() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["FirestoreDataStorage"].tap()
        
        var documents = try await Self.getAllDocuments()
        XCTAssert(documents.isEmpty)
        
        try add(id: "Identifier1", content: "1")
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await Self.getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )
        
        try add(id: "Identifier1", content: "2")
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await Self.getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "2"
                )
            ]
        )
    }
    
    
    @MainActor
    func testFirestoreDelete() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["FirestoreDataStorage"].tap()
        
        var documents = try await Self.getAllDocuments()
        XCTAssert(documents.isEmpty)
        
        try add(id: "Identifier1", content: "1")
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await Self.getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    content: "1"
                )
            ]
        )
        
        try remove(id: "Identifier1", content: "1")
        
        documents = try await Self.getAllDocuments()
        XCTAssert(documents.isEmpty)
    }
    

    @MainActor
    private func add(id: String, content: String) throws {
        try enterFirestoreElement(id: id, content: content)
        XCUIApplication().buttons["Upload Element"].tap()
    }

    @MainActor
    private func merge(id: String, content: String) throws {
        try enterFirestoreElement(id: id, content: content)
        XCUIApplication().buttons["Merge Element"].tap()
    }

    @MainActor
    private func remove(id: String, content: String) throws {
        try enterFirestoreElement(id: id, content: content)
        XCUIApplication().buttons["Delete Element"].tap()
    }

    @MainActor
    private func enterFirestoreElement(id: String, content: String) throws {
        let app = XCUIApplication()
        
        let identifierTextFieldIdentifier = "Enter the element's identifier."
        try app.textFields[identifierTextFieldIdentifier].delete(count: 42, options: .disableKeyboardDismiss)
        try app.textFields[identifierTextFieldIdentifier].enter(value: id, options: .skipTextFieldSelection)

        let contentFieldIdentifier = "Enter the element's optional content."
        try app.textFields[contentFieldIdentifier].delete(count: 100, options: .disableKeyboardDismiss)
        //try app.textFields[contentFieldIdentifier].enter(value: content, options: .skipTextFieldSelection)
        app.textFields[contentFieldIdentifier].typeText(content)
    }
}


extension FirestoreDataStorageTests {
    private static func deleteAllDocuments() async throws {
        let emulatorDocumentsURL = try XCTUnwrap(
            URL(string: "http://localhost:8080/emulator/v1/projects/spezifirebaseuitests/databases/(default)/documents")
        )
        var request = URLRequest(url: emulatorDocumentsURL)
        request.httpMethod = "DELETE"

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirestoreDataStorageTests` require the Firebase Firestore Emulator to run at port 8080.
                
                Refer to https://firebase.google.com/docs/emulator-suite/connect_firestore about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }
    }

    private static func getAllDocuments() async throws -> [FirestoreElement] {
        let documentsURL = try XCTUnwrap(
            URL(string: "http://localhost:8080/v1/projects/spezifirebaseuitests/databases/(default)/documents/")
        )
        let (data, response) = try await URLSession.shared.data(from: documentsURL)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirestoreDataStorageTests` require the Firebase Firestore Emulator to run at port 8080.
                
                Refer to https://firebase.google.com/docs/emulator-suite/connect_firestore about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }

        struct ResponseWrapper: Decodable {
            let documents: [FirestoreElement]
        }

        do {
            return try JSONDecoder().decode(ResponseWrapper.self, from: data).documents
        } catch {
            return []
        }
    }
}
