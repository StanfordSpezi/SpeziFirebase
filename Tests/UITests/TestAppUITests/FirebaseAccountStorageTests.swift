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
    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        continueAfterFailure = false

        try disablePasswordAutofill()

        try await FirebaseClient.deleteAllAccounts()
        try await Task.sleep(for: .seconds(0.5))
    }

    @MainActor
    func testAdditionalAccountStorage() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--account-storage"]
        app.launch()

        XCTAssert(app.buttons["FirebaseAccount"].waitForExistence(timeout: 10.0))
        app.buttons["FirebaseAccount"].tap()

        if app.buttons["Logout"].waitForExistence(timeout: 5.0) && app.buttons["Logout"].isHittable {
            app.buttons["Logout"].tap()
        }


        try app.signup(username: "test@username1.edu", password: "TestPassword1", givenName: "Test1", familyName: "Username1", biography: "Hello Stanford")


        XCTAssertTrue(app.buttons["Account Overview"].waitForExistence(timeout: 2.0))
        app.buttons["Account Overview"].tap()
        XCTAssertTrue(app.staticTexts["Biography, Hello Stanford"].waitForExistence(timeout: 2.0))


        // NOW TEST ACCOUNT EDIT
        XCTAssertTrue(app.navigationBars.buttons["Edit"].exists)
        app.navigationBars.buttons["Edit"].tap()

        try app.textFields["Biography"].enter(value: "2")

        XCTAssertTrue(app.navigationBars.buttons["Done"].exists)
        app.navigationBars.buttons["Done"].tap()

        XCTAssertTrue(app.staticTexts["Biography, Hello Stanford2"].waitForExistence(timeout: 2.0))
    }
}
