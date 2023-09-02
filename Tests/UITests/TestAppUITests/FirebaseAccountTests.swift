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
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        
        try disablePasswordAutofill()

        try await FirebaseClient.deleteAllAccounts()
        try await Task.sleep(for: .seconds(0.5))
    }

    
    @MainActor
    func testAccountSignUp() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()
        
        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        var accounts = try await FirebaseClient.getAllAccounts()
        XCTAssert(accounts.isEmpty)

        if app.buttons["Logout"].waitForExistence(timeout: 5.0) && app.buttons["Logout"].isHittable {
            app.buttons["Logout"].tap()
        }
        
        try app.signup(username: "test@username1.edu", password: "TestPassword1", givenName: "Test1", familyName: "Username1")
        
        XCTAssert(app.buttons["Logout"].waitForExistence(timeout: 10.0))
        app.buttons["Logout"].tap()
        
        try app.signup(username: "test@username2.edu", password: "TestPassword2", givenName: "Test2", familyName: "Username2")

        try await Task.sleep(for: .seconds(0.5))
        
        accounts = try await FirebaseClient.getAllAccounts()
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
        try await FirebaseClient.createAccount(email: "test@username1.edu", password: "TestPassword1", displayName: "Test1 Username1")
        try await FirebaseClient.createAccount(email: "test@username2.edu", password: "TestPassword2", displayName: "Test2 Username2")
        
        let accounts = try await FirebaseClient.getAllAccounts()
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
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Test Username")

        let accounts = try await FirebaseClient.getAllAccounts()
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
        logoutButtons.last!.tap() // swiftlint:disable:this force_unwrapping

        let alert = "Are you sure you want to logout?"
        XCTAssertTrue(XCUIApplication().alerts[alert].waitForExistence(timeout: 6.0))
        XCUIApplication().alerts[alert].scrollViews.otherElements.buttons["Logout"].tap()

        sleep(2)
        let accounts2 = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(
            accounts2.sorted(by: { $0.email < $1.email }),
            [
                FirestoreAccount(email: "test@username.edu", displayName: "Test Username")
            ]
        )
    }

    @MainActor
    func testAccountRemoval() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Test Username")

        let accounts = try await FirebaseClient.getAllAccounts()
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
        let accountsNew = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accountsNew, [])
    }

    @MainActor
    func testAccountEdit() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

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

        app.buttons["Name, E-Mail Address"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 10.0))

        // CHANGE NAME
        app.buttons["Name, Username Test"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name"].waitForExistence(timeout: 10.0))

        try app.textFields["Enter your last name ..."].delete(count: 4)
        app.typeText("Test1")

        app.buttons["Done"].tap()
        sleep(3)
        XCTAssertTrue(app.staticTexts["Username Test1"].waitForExistence(timeout: 5.0))

        // CHANGE EMAIL ADDRESS
        app.buttons["E-Mail Address, test@username.edu"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["E-Mail Address"].waitForExistence(timeout: 10.0))

        try app.textFields["E-Mail Address"].delete(count: 3)
        app.typeText("de")

        app.buttons["Done"].tap()
        sleep(3)
        XCTAssertTrue(app.staticTexts["test@username.de"].waitForExistence(timeout: 5.0))


        let newAccounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(newAccounts, [FirestoreAccount(email: "test@username.de", displayName: "Username Test1")])
    }


    @MainActor
    func testPasswordChange() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

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

        app.buttons["Password & Security"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Password & Security"].waitForExistence(timeout: 10.0))

        app.buttons["Change Password"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Change Password"].waitForExistence(timeout: 10.0))
        sleep(2)

        try app.secureTextFields["New Password"].enter(value: "1234567890")
        app.dismissKeyboard()

        try app.secureTextFields["Repeat Password"].enter(value: "1234567890")
        app.dismissKeyboard()

        app.buttons["Done"].tap()
        sleep(1)
        app.navigationBars.buttons["Account Overview"].tap() // back button
        sleep(1)
        app.buttons["Close"].tap()
        sleep(1)
        app.buttons["Logout"].tap() // we tap the custom button to be lest dependent on the other tests and not deal with the alert

        try app.login(username: "test@username.edu", password: "1234567890", close: false)
        XCTAssertTrue(app.staticTexts["Username Test"].waitForExistence(timeout: 6.0))
    }

    @MainActor
    func testInvalidCredentials() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        if app.buttons["Logout"].waitForExistence(timeout: 5.0) && app.buttons["Logout"].isHittable {
            app.buttons["Logout"].tap()
        }

        try app.login(username: "unknown@example.de", password: "HelloWorld", close: false)
        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 6.0))
        app.alerts["Invalid Credentials"].scrollViews.otherElements.buttons["OK"].tap()
        app.buttons["Close"].tap()
        sleep(2)

        // signing in with unknown credentials or credentials with a incorrect password are two different errors
        // that should, nonetheless, be treated equally in UI.
        try app.login(username: "test@username.edu", password: "HelloWorld", close: false)
        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 6.0))
        app.alerts["Invalid Credentials"].scrollViews.otherElements.buttons["OK"].tap()
    }
}


extension XCUIApplication {
    func extendedDismissKeyboard() {
        let keyboard = keyboards.firstMatch

        if keyboard.waitForExistence(timeout: 1.0) && keyboard.buttons["Done"].isHittable {
            keyboard.buttons["Done"].tap()
        }
    }

    fileprivate func login(username: String, password: String, close: Bool = true) throws {
        buttons["Account Setup"].tap()
        XCTAssertTrue(self.buttons["Login"].waitForExistence(timeout: 2.0))
        
        try textFields["E-Mail Address"].enter(value: username)
        extendedDismissKeyboard()
        
        try secureTextFields["Password"].enter(value: password)
        extendedDismissKeyboard()
        
        swipeUp()

        scrollViews.buttons["Login"].tap()

        if close {
            sleep(3)
            self.buttons["Close"].tap()
        }
    }
    
    
    fileprivate func signup(username: String, password: String, givenName: String, familyName: String) throws {
        buttons["Account Setup"].tap()
        buttons["Signup"].tap()

        XCTAssertTrue(staticTexts["Please fill out the details below to create a new account."].waitForExistence(timeout: 6.0))
        sleep(2)

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
