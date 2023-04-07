//
// This source file is part of the CardinalKit open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest


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
        
        init(id: String, collectionPath: String, content: Int) {
            self.init(
                name: "projects/cardinalkitfirebaseuitests/databases/(default)/documents/\(collectionPath)/\(id)",
                fields: [
                    "collectionPath": [
                        "stringValue": collectionPath
                    ],
                    "id": [
                        "stringValue": id
                    ],
                    "content": [
                        "integerValue": content.description
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
        try await super.setUp()
        
        try await deleteAllDocuments()
        try await Task.sleep(for: .seconds(0.5))
    }
    
    
    @MainActor
    func testFirestoreAdditions() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["FirestoreDataStorage"].tap()
        
        var documents = try await getAllDocuments()
        XCTAssert(documents.isEmpty)
        
        try add(id: "Identifier1", collectionPath: "CollectionPath1", context: 1)
        try add(id: "Identifier2", collectionPath: "CollectionPath2", context: 2)
        try add(id: "Identifier3", collectionPath: "CollectionPath1", context: 3)
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    collectionPath: "CollectionPath1",
                    content: 1
                ),
                FirestoreElement(
                    id: "Identifier3",
                    collectionPath: "CollectionPath1",
                    content: 3
                ),
                FirestoreElement(
                    id: "Identifier2",
                    collectionPath: "CollectionPath2",
                    content: 2
                )
            ]
        )
    }
    
    @MainActor
    func testFirestoreUpdate() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["FirestoreDataStorage"].tap()
        
        var documents = try await getAllDocuments()
        XCTAssert(documents.isEmpty)
        
        try add(id: "Identifier1", collectionPath: "CollectionPath1", context: 1)
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    collectionPath: "CollectionPath1",
                    content: 1
                )
            ]
        )
        
        try add(id: "Identifier1", collectionPath: "CollectionPath1", context: 2)
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    collectionPath: "CollectionPath1",
                    content: 2
                )
            ]
        )
    }
    
    
    @MainActor
    func testFirestoreDelete() async throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["FirestoreDataStorage"].tap()
        
        var documents = try await getAllDocuments()
        XCTAssert(documents.isEmpty)
        
        try add(id: "Identifier1", collectionPath: "CollectionPath1", context: 1)
        
        try await Task.sleep(for: .seconds(0.5))
        documents = try await getAllDocuments()
        XCTAssertEqual(
            documents.sorted(by: { $0.name < $1.name }),
            [
                FirestoreElement(
                    id: "Identifier1",
                    collectionPath: "CollectionPath1",
                    content: 1
                )
            ]
        )
        
        try remove(id: "Identifier1", collectionPath: "CollectionPath1", context: 1)
        
        documents = try await getAllDocuments()
        XCTAssert(documents.isEmpty)
    }
    
    
    private func add(id: String, collectionPath: String, context: Int) throws {
        try enterFirestoreElement(id: id, collectionPath: collectionPath, context: context)
        XCUIApplication().buttons["Upload Element"].tap()
    }
    
    private func remove(id: String, collectionPath: String, context: Int) throws {
        try enterFirestoreElement(id: id, collectionPath: collectionPath, context: context)
        XCUIApplication().buttons["Delete Element"].tap()
    }
    
    private func enterFirestoreElement(id: String, collectionPath: String, context: Int) throws {
        let app = XCUIApplication()
        
        let identifierTextFieldIdentifier = "Enter the element's identifier."
        try app.textFields[identifierTextFieldIdentifier].delete(count: 42)
        try app.textFields[identifierTextFieldIdentifier].enter(value: id)
        
        app.dismissKeyboard()
        
        let collectionPathTextFieldIdentifier = "Enter the element's collection path."
        try app.textFields[collectionPathTextFieldIdentifier].delete(count: 42)
        try app.textFields[collectionPathTextFieldIdentifier].enter(value: collectionPath)
        
        app.dismissKeyboard()
        
        let contextFieldIdentifier = "Enter the element's optional context."
        try app.textFields[contextFieldIdentifier].delete(count: 42)
        try app.textFields[contextFieldIdentifier].enter(value: context.description)
        
        app.dismissKeyboard()
    }
    
    private func deleteAllDocuments() async throws {
        let emulatorDocumentsURL = try XCTUnwrap(
            URL(string: "http://localhost:8080/emulator/v1/projects/cardinalkitfirebaseuitests/databases/(default)/documents")
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

    private func getAllDocuments() async throws -> [FirestoreElement] {
        let documentsURL = try XCTUnwrap(
            URL(string: "http://localhost:8080/v1/projects/cardinalkitfirebaseuitests/databases/(default)/documents/")
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
