//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import XCTest
import XCTestExtensions


final class FirebaseAccountStorageTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func setUp() async throws {
        try await FirebaseClient.deleteAllAccounts()
        try await Task.sleep(for: .seconds(0.5))
    }


    @MainActor
    func testAdditionalAccountStorage() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--account-storage"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 2.0))

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 2.0))
        app.buttons["FirebaseAccount"].tap()

        try app.signup(
            username: "test@username1.edu",
            password: "TestPassword1",
            givenName: "Test1",
            familyName: "Username1",
            biography: "Hello Stanford"
        )


        XCTAssertTrue(app.buttons["Account Overview"].waitForExistence(timeout: 2.0))
        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["Biography, Hello Stanford"].waitForExistence(timeout: 2.0))


        // TEST ACCOUNT EDIT
        XCTAssertTrue(app.navigationBars.buttons["Edit"].exists)
        app.navigationBars.buttons["Edit"].tap()

        try app.textFields["Biography"].enter(value: "2")

        XCTAssertTrue(app.navigationBars.buttons["Done"].exists)
        app.navigationBars.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Biography, Hello Stanford2"].waitForExistence(timeout: 2.0))

        // TEST ACCOUNT DELETION
        XCTAssertTrue(app.navigationBars.buttons["Edit"].exists)
        app.navigationBars.buttons["Edit"].tap()

        XCTAssertTrue(app.buttons["Delete Account"].waitForExistence(timeout: 4.0))
        app.buttons["Delete Account"].tap()

        let alert = "Are you sure you want to delete your account?"
        XCTAssertTrue(XCUIApplication().alerts[alert].waitForExistence(timeout: 6.0))
        XCUIApplication().alerts[alert].scrollViews.otherElements.buttons["Delete"].tap()

        XCTAssertTrue(app.alerts["Authentication Required"].waitForExistence(timeout: 2.0))
        XCTAssertTrue(app.alerts["Authentication Required"].secureTextFields["Password"].waitForExistence(timeout: 0.5))
        app.typeText("TestPassword1") // the password field has focus already
        XCTAssertTrue(app.alerts["Authentication Required"].buttons["Login"].waitForExistence(timeout: 0.5))
        app.alerts["Authentication Required"].buttons["Login"].tap()

        sleep(2)
        let accountsNew = try await FirebaseClient.getAllAccounts()
        XCTAssertTrue(accountsNew.isEmpty)
    }
}
