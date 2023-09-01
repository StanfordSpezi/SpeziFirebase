//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


/// The `FirebaseAccountTests` require the Firebase Authentication Emulator to run at port 9099.
///
/// Refer to https://firebase.google.com/docs/emulator-suite/connect_auth about more information about the
/// Firebase Local Emulator Suite.
final class FirebaseAccountTests: XCTestCase {
    private struct FirestoreAccount: Decodable, Equatable {
        enum CodingKeys: String, CodingKey {
            case email
            case displayName
            case providerIds = "providerUserInfo"
        }
        
        
        let email: String
        let displayName: String
        let providerIds: [String]
        
        
        init(email: String, displayName: String, providerIds: [String] = ["password"]) {
            self.email = email
            self.displayName = displayName
            self.providerIds = providerIds
        }
        
        init(from decoder: Decoder) throws {
            let container: KeyedDecodingContainer<FirebaseAccountTests.FirestoreAccount.CodingKeys> = try decoder.container(
                keyedBy: FirebaseAccountTests.FirestoreAccount.CodingKeys.self
            )
            self.email = try container.decode(String.self, forKey: FirebaseAccountTests.FirestoreAccount.CodingKeys.email)
            self.displayName = try container.decode(String.self, forKey: FirebaseAccountTests.FirestoreAccount.CodingKeys.displayName)
            
            struct ProviderUserInfo: Decodable {
                let providerId: String
            }
            
            self.providerIds = try container
                .decode(
                    [ProviderUserInfo].self,
                    forKey: FirebaseAccountTests.FirestoreAccount.CodingKeys.providerIds
                )
                .map(\.providerId)
        }
    }

    private static let projectId = "nams-e43ed" // TODO  = "spezifirebaseuitests"

    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        
        // try disablePasswordAutofill()
        
        try await deleteAllAccounts()
        try await Task.sleep(for: .seconds(0.5))
    }

    
    @MainActor
    func testAccountSignUp() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()
        
        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        var accounts = try await getAllAccounts()
        XCTAssert(accounts.isEmpty)

        if app.buttons["Logout"].waitForExistence(timeout: 5.0) && app.buttons["Logout"].isHittable {
            app.buttons["Logout"].tap()
        }
        
        try app.signup(username: "test@username1.edu", password: "TestPassword1", givenName: "Test1", familyName: "Username1")
        
        XCTAssert(app.buttons["Logout"].waitForExistence(timeout: 10.0))
        app.buttons["Logout"].tap()
        
        try app.signup(username: "test@username2.edu", password: "TestPassword2", givenName: "Test2", familyName: "Username2")

        try await Task.sleep(for: .seconds(0.5))
        
        accounts = try await getAllAccounts()
        XCTAssertEqual(
            accounts.sorted(by: { $0.email < $1.email }),
            [
                FirestoreAccount(email: "test@username1.edu", displayName: "Test1 Username1"),
                FirestoreAccount(email: "test@username2.edu", displayName: "Test2 Username2")
            ]
        )
        
        XCTAssert(app.buttons["Logout"].waitForExistence(timeout: 10.0))
        app.buttons["Logout"].tap()
    }
    
    
    @MainActor
    func testAccountLogin() async throws {
        try await createAccount(email: "test@username1.edu", password: "TestPassword1", displayName: "Test1 Username1")
        try await createAccount(email: "test@username2.edu", password: "TestPassword2", displayName: "Test2 Username2")
        
        let accounts = try await getAllAccounts()
        XCTAssertEqual(
            accounts.sorted(by: { $0.email < $1.email }),
            [
                FirestoreAccount(email: "test@username1.edu", displayName: "Test1 Username1"),
                FirestoreAccount(email: "test@username2.edu", displayName: "Test2 Username2")
            ]
        )
        
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()
        
        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        if app.buttons["Logout"].waitForExistence(timeout: 10.0) && app.buttons["Logout"].isHittable {
            app.buttons["Logout"].tap()
        }
        
        try app.login(username: "test@username1.edu", password: "TestPassword1")
        XCTAssert(app.staticTexts["test@username1.edu"].waitForExistence(timeout: 10.0))
        
        XCTAssert(app.buttons["Logout"].waitForExistence(timeout: 10.0))
        app.buttons["Logout"].tap()
        
        try app.login(username: "test@username2.edu", password: "TestPassword2")
        XCTAssert(app.staticTexts["test@username2.edu"].waitForExistence(timeout: 10.0))
        
        XCTAssert(app.buttons["Logout"].waitForExistence(timeout: 10.0))
        app.buttons["Logout"].tap()
    }

    @MainActor
    func testAccountLogout() async throws {
        try await createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Test Username")

        let accounts = try await getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Test Username")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        if app.buttons["Logout"].waitForExistence(timeout: 5.0) && app.buttons["Logout"].isHittable {
            app.buttons["Logout"].tap()
        }

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 10.0))

        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 5.0))

        let logoutButtons = app.buttons.matching(identifier: "Logout").allElementsBoundByIndex
        XCTAssert(!logoutButtons.isEmpty)
        logoutButtons.last!.tap()

        let alert = "Are you sure you want to logout?"
        XCTAssertTrue(XCUIApplication().alerts[alert].waitForExistence(timeout: 6.0))
        XCUIApplication().alerts[alert].scrollViews.otherElements.buttons["Logout"].tap()

        sleep(2)
        let accounts2 = try await getAllAccounts()
        XCTAssertEqual(
            accounts2.sorted(by: { $0.email < $1.email }),
            [
                FirestoreAccount(email: "test@username.edu", displayName: "Test Username")
            ]
        )
    }

    @MainActor
    func testAccountRemoval() async throws {
        try await createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Test Username")

        let accounts = try await getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Test Username")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        if app.buttons["Logout"].waitForExistence(timeout: 5.0) && app.buttons["Logout"].isHittable {
            app.buttons["Logout"].tap()
        }

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 10.0))

        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 5.0))

        app.buttons["Edit"].tap()
        sleep(1)
        if app.buttons["Edit"].waitForExistence(timeout: 1.0) {
            app.buttons["Edit"].tap()
        }


        XCTAssertTrue(app.buttons["Delete Account"].waitForExistence(timeout: 4.0))
        app.buttons["Delete Account"].tap()

        let alert = "Are you sure you want to delete your account?"
        XCTAssertTrue(XCUIApplication().alerts[alert].waitForExistence(timeout: 6.0))
        XCUIApplication().alerts[alert].scrollViews.otherElements.buttons["Delete"].tap()

        sleep(2)
        let accounts2 = try await getAllAccounts()
        XCTAssertEqual(accounts2, [])
    }

    // TODO test edit

    
    // curl -H "Authorization: Bearer owner" -X DELETE http://localhost:9099/emulator/v1/projects/spezifirebaseuitests/accounts
    private func deleteAllAccounts() async throws {
        let emulatorDocumentsURL = try XCTUnwrap(
            URL(string: "http://localhost:9099/emulator/v1/projects/\(Self.projectId)/accounts")
        )
        var request = URLRequest(url: emulatorDocumentsURL)
        request.httpMethod = "DELETE"
        request.addValue("Bearer owner", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirebaseAccountTests` require the Firebase Authentication Emulator to run at port 9099.

                Refer to https://firebase.google.com/docs/emulator-suite/connect_auth about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }
    }

    // curl -H "Authorization: Bearer owner" -H "Content-Type: application/json" -X POST -d '{}' http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/spezifirebaseuitests/accounts:query
    private func getAllAccounts() async throws -> [FirestoreAccount] {
        let emulatorAccountsURL = try XCTUnwrap(
            URL(string: "http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/\(Self.projectId)/accounts:query")
        )
        var request = URLRequest(url: emulatorAccountsURL)
        request.httpMethod = "POST"
        request.addValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirebaseAccountTests` require the Firebase Authentication Emulator to run at port 9099.

                Refer to https://firebase.google.com/docs/emulator-suite/connect_auth about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }

        struct ResponseWrapper: Decodable {
            let userInfo: [FirestoreAccount]
        }

        return try JSONDecoder().decode(ResponseWrapper.self, from: data).userInfo
    }
    
    // curl -H 'Content-Type: application/json' -d '{"email":"[user@example.com]","password":"[PASSWORD]","returnSecureToken":true}' 'http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=spezifirebaseuitests'
    private func createAccount(email: String, password: String, displayName: String) async throws {
        let emulatorAccountsURL = try XCTUnwrap(
            URL(string: "http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(Self.projectId)")
        )
        var request = URLRequest(url: emulatorAccountsURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(
            """
            {
                "email": "\(email)",
                "password": "\(password)",
                "displayName": "\(displayName)",
                "returnSecureToken": true
            }
            """.utf8
        )
        
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let urlResponse = response as? HTTPURLResponse,
              200...299 ~= urlResponse.statusCode else {
            print(
                """
                The `FirebaseAccountTests` require the Firebase Authentication Emulator to run at port 9099.

                Refer to https://firebase.google.com/docs/emulator-suite/connect_auth about more information about the
                Firebase Local Emulator Suite.
                """
            )
            throw URLError(.fileDoesNotExist)
        }
    }
}


extension XCUIApplication {
    func extendedDismissKeyboard() {
        let keyboard = keyboards.firstMatch

        if keyboard.waitForExistence(timeout: 1.0) && keyboard.buttons["Done"].isHittable {
            keyboard.buttons["Done"].tap()
        }
    }

    fileprivate func login(username: String, password: String) throws {
        buttons["Account Setup"].tap()
        XCTAssertTrue(self.buttons["Login"].waitForExistence(timeout: 2.0))
        
        try textFields["E-Mail Address"].enter(value: username)
        extendedDismissKeyboard()
        
        try secureTextFields["Password"].enter(value: password)
        extendedDismissKeyboard()
        
        swipeUp()

        scrollViews.buttons["Login"].tap()

        sleep(3)
        self.buttons["Close"].tap()
    }
    
    
    fileprivate func signup(username: String, password: String, givenName: String, familyName: String) throws {
        buttons["Account Setup"].tap()
        buttons["Signup"].tap()

        XCTAssertTrue(staticTexts["Please fill out the details below to create a new account."].waitForExistence(timeout: 2.0))
        
        try textFields["E-Mail Address"].enter(value: username)
        extendedDismissKeyboard()
        
        try secureTextFields["Password"].enter(value: password)
        extendedDismissKeyboard()
        
        swipeUp()
        
        try textFields["Enter your first name ..."].enter(value: givenName)
        extendedDismissKeyboard()
        swipeUp()
        
        try textFields["Enter your last name ..."].enter(value: familyName)
        extendedDismissKeyboard()
        swipeUp()

        collectionViews.buttons["Signup"].tap()

        sleep(3)
        buttons["Close"].tap()
    }
}
