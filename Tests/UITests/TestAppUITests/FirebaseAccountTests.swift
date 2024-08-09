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
final class FirebaseAccountTests: XCTestCase { // swiftlint:disable:this type_body_length
    override func setUp() {
        continueAfterFailure = false
    }

    override func setUp() async throws {
        try await FirebaseClient.deleteAllAccounts()
        try await Task.sleep(for: .seconds(0.5))
    }

    @MainActor
    func testAccountSignUp() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseAccount"].tap()

        var accounts = try await FirebaseClient.getAllAccounts()
        XCTAssert(accounts.isEmpty)
        
        try app.signup(username: "test@username1.edu", password: "TestPassword1", givenName: "Test1", familyName: "Username1")
        
        XCTAssert(app.buttons["Logout"].waitForExistence(timeout: 2.0))
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
        
        XCTAssert(app.buttons["Logout"].waitForExistence(timeout: 2.0))
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
        
        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseAccount"].tap()
        
        try app.login(username: "test@username1.edu", password: "TestPassword1")
        XCTAssert(app.staticTexts["test@username1.edu"].waitForExistence(timeout: 2.0))

        XCTAssert(app.buttons["Logout"].exists)
        app.buttons["Logout"].tap()
        
        try app.login(username: "test@username2.edu", password: "TestPassword2")
        XCTAssert(app.staticTexts["test@username2.edu"].waitForExistence(timeout: 2.0))

        XCTAssert(app.buttons["Logout"].exists)
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
            [FirestoreAccount(email: "test@username.edu", displayName: "Test Username")]
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

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 4.0))

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

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

        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("TestPassword") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()

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

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 4.0))

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 10.0))

        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 5.0))

        app.buttons["Name, E-Mail Address"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 10.0))

        // CHANGE NAME
        app.buttons["Name, Username Test"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name"].waitForExistence(timeout: 10.0))

        try app.textFields["enter last name"].delete(count: 4)
        try app.textFields["enter last name"].enter(value: "Test1")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 4.0))
        XCTAssertTrue(app.staticTexts["Name, Username Test1"].exists)

        // CHANGE EMAIL ADDRESS
        app.buttons["E-Mail Address, test@username.edu"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["E-Mail Address"].waitForExistence(timeout: 10.0))

        try app.textFields["E-Mail Address"].delete(count: 3)
        try app.textFields["E-Mail Address"].enter(value: "de", checkIfTextWasEnteredCorrectly: false)

        app.buttons["Done"].tap()

        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("TestPassword") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()

        XCTAssertTrue(app.navigationBars.staticTexts["Name, E-Mail Address"].waitForExistence(timeout: 4.0))
        XCTAssertTrue(app.staticTexts["E-Mail Address, test@username.de"].exists)


        let newAccounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(newAccounts, [FirestoreAccount(email: "test@username.de", displayName: "Username Test1")])
    }

    @MainActor
    private func passwordChangeBase() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "test@username.edu", password: "TestPassword")
        XCTAssert(app.staticTexts["test@username.edu"].waitForExistence(timeout: 2.0))

        XCTAssertTrue(app.buttons["Account Overview"].exists)
        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["test@username.edu"].waitForExistence(timeout: 2.0))

        XCTAssertTrue(app.buttons["Sign-In & Security"].exists)
        app.buttons["Sign-In & Security"].tap()
        XCTAssertTrue(app.navigationBars.staticTexts["Sign-In & Security"].waitForExistence(timeout: 2.0))

        XCTAssertTrue(app.buttons["Change Password"].exists)
        app.buttons["Change Password"].tap()


        XCTAssertTrue(app.navigationBars.staticTexts["Change Password"].waitForExistence(timeout: 2.0))

        try app.secureTextFields["enter password"].enter(value: "1234567890")
        app.dismissKeyboard()

        try app.secureTextFields["re-enter password"].enter(value: "1234567890")
        app.dismissKeyboard()

        app.buttons["Done"].tap()
    }

    @MainActor
    func testPasswordChange() async throws {
        try await passwordChangeBase()

        let app = XCUIApplication()

        
        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("TestPassword") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()

        XCTAssertTrue(app.navigationBars.buttons["Account Overview"].waitForExistence(timeout: 2.0))
        app.navigationBars.buttons["Account Overview"].tap() // back button

        XCTAssertTrue(app.navigationBars.buttons["Close"].waitForExistence(timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()

        XCTAssertTrue(app.buttons["Logout"].waitForExistence(timeout: 2.0))
        app.buttons["Logout"].tap() // we tap the custom button to be lest dependent on the other tests and not deal with the alert

        try app.login(username: "test@username.edu", password: "1234567890", close: false)
        XCTAssertTrue(app.staticTexts["Username Test"].waitForExistence(timeout: 6.0))
    }

    @MainActor
    func testPasswordChangeWrong() async throws {
        try await passwordChangeBase()

        let app = XCUIApplication()


        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("Wrong!") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()


        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 2.0))
    }

    @MainActor
    func testPasswordChangeCancel() async throws {
        try await passwordChangeBase()

        let app = XCUIApplication()


        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Cancel"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Cancel"].tap()

        XCTAssertTrue(app.navigationBars.buttons["Account Overview"].waitForExistence(timeout: 2.0))
        app.navigationBars.buttons["Account Overview"].tap() // back button

        XCTAssertTrue(app.navigationBars.buttons["Close"].waitForExistence(timeout: 2.0))
        app.navigationBars.buttons["Close"].tap()

        XCTAssertTrue(app.buttons["Logout"].waitForExistence(timeout: 2.0))
        app.buttons["Logout"].tap() // we tap the custom button to be lest dependent on the other tests and not deal with the alert

        try app.login(username: "test@username.edu", password: "TestPassword", close: false) // login with previous password!
        XCTAssertTrue(app.staticTexts["Username Test"].waitForExistence(timeout: 6.0))
    }

    @MainActor
    func testPasswordReset() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        app.buttons["Account Setup"].tap()

        XCTAssertTrue(app.buttons["Forgot Password?"].waitForExistence(timeout: 2.0))

        app.buttons["Forgot Password?"].tap()

        XCTAssertTrue(app.buttons["Reset Password"].waitForExistence(timeout: 2.0))

        let fields = app.textFields.matching(identifier: "E-Mail Address").allElementsBoundByIndex
        try fields.last?.enter(value: "non-existent@username.edu")

        app.buttons["Reset Password"].tap()

        XCTAssertTrue(app.staticTexts["Sent out a link to reset the password."].waitForExistence(timeout: 2.0))
        app.buttons["Done"].tap()
    }

    @MainActor
    func testInvalidCredentials() async throws {
        try await FirebaseClient.createAccount(email: "test@username.edu", password: "TestPassword", displayName: "Username Test")

        let accounts = try await FirebaseClient.getAllAccounts()
        XCTAssertEqual(accounts, [FirestoreAccount(email: "test@username.edu", displayName: "Username Test")])

        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseAccount"].tap()

        try app.login(username: "unknown@example.de", password: "HelloWorld", close: false)
        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 3.0))
        XCTAssertTrue(app.alerts["Invalid Credentials"].scrollViews.buttons["OK"].exists)
        app.alerts["Invalid Credentials"].scrollViews.buttons["OK"].tap()

        XCTAssertTrue(app.buttons["Close"].exists)
        app.buttons["Close"].tap()

        XCTAssertTrue(app.buttons["Account Setup"].waitForExistence(timeout: 2.0))

        // signing in with unknown credentials or credentials with a incorrect password are two different errors
        // that should, nonetheless, be treated equally in UI.
        try app.login(username: "test@username.edu", password: "HelloWorld", close: false)
        XCTAssertTrue(app.alerts["Invalid Credentials"].waitForExistence(timeout: 6.0))
        app.alerts["Invalid Credentials"].scrollViews.otherElements.buttons["OK"].tap()
    }

    @MainActor
    func testBasicSignInWithApple() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--firebaseAccount"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        app.buttons["Account Setup"].tap()

        addUIInterruptionMonitor(withDescription: "Apple Sign In") { element in
            // there will be a dialog that you have to sign in with your apple id. We just close it.
            element.buttons["Close"].tap()
            return true
        }

        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 2.0))
        app.buttons["Sign in with Apple"].tap()

        app.tap() // that triggers the interruption monitor closure
    }

    @MainActor
    func testSignupAccountLinking() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--account-storage"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseAccount"].tap()

        XCTAssertTrue(app.buttons["Account Setup"].exists)
        app.buttons["Account Setup"].tap()

        XCTAssertTrue(app.buttons["Anonymous Signup"].waitForExistence(timeout: 4.0))
        app.buttons["Anonymous Signup"].tap()

        XCTAssertTrue(app.buttons["Close"].exists)
        app.buttons["Close"].tap()

        XCTAssertTrue(app.staticTexts["User, Anonymous"].waitForExistence(timeout: 2.0))

        try app.signup(username: "test@username2.edu", password: "TestPassword2", givenName: "Leland", familyName: "Stanford", biography: "Bio")

        app.buttons["Account Overview"].tap()
        XCTAssert(app.staticTexts["Leland Stanford"].waitForExistence(timeout: 2.0))
        XCTAssert(app.staticTexts["Biography, Bio"].exists)
    }
}


extension XCUIApplication {
    func login(username: String, password: String, close: Bool = true) throws {
        XCTAssertTrue(buttons["Account Setup"].exists)
        buttons["Account Setup"].tap()
        XCTAssertTrue(self.buttons["Login"].waitForExistence(timeout: 2.0))
        
        try textFields["E-Mail Address"].enter(value: username)
        try secureTextFields["Password"].enter(value: password)

        scrollViews.buttons["Login"].tap()


        if close {
            XCTAssertTrue(staticTexts[username].waitForExistence(timeout: 5.0))
            self.buttons["Close"].tap()
        }
    }

    func signup(username: String, password: String, givenName: String, familyName: String, biography: String? = nil) throws {
        XCTAssertTrue(buttons["Account Setup"].exists)
        buttons["Account Setup"].tap()
        XCTAssertTrue(buttons["Signup"].waitForExistence(timeout: 2.0))
        buttons["Signup"].tap()

        XCTAssertTrue(staticTexts["Please fill out the details below to create your new account."].waitForExistence(timeout: 6.0))

        try collectionViews.textFields["E-Mail Address"].enter(value: username)
        try collectionViews.secureTextFields["Password"].enter(value: password)
        
        try textFields["enter first name"].enter(value: givenName)
        try textFields["enter last name"].enter(value: familyName)

        if let biography {
            try textFields["Biography"].enter(value: biography)
        }

        XCTAssertTrue(buttons["Signup"].exists)
        collectionViews.buttons["Signup"].tap()

        XCTAssertTrue(buttons["Close"].waitForExistence(timeout: 2.0))
        buttons["Close"].tap()
    }
}
