//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import XCTest


struct FirestoreAccount: Decodable, Equatable {
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
        let container: KeyedDecodingContainer<FirestoreAccount.CodingKeys> = try decoder.container(
            keyedBy: FirestoreAccount.CodingKeys.self
        )
        self.email = try container.decode(String.self, forKey: FirestoreAccount.CodingKeys.email)
        self.displayName = try container.decode(String.self, forKey: FirestoreAccount.CodingKeys.displayName)

        struct ProviderUserInfo: Decodable {
            let providerId: String
        }

        self.providerIds = try container
            .decode(
                [ProviderUserInfo].self,
                forKey: FirestoreAccount.CodingKeys.providerIds
            )
            .map(\.providerId)
    }
}


enum FirebaseClient {
    private static let projectId = "nams-e43ed"

    // curl -H "Authorization: Bearer owner" -X DELETE http://localhost:9099/emulator/v1/projects/spezifirebaseuitests/accounts
    static func deleteAllAccounts() async throws {
        let emulatorDocumentsURL = try XCTUnwrap(
            URL(string: "http://localhost:9099/emulator/v1/projects/\(projectId)/accounts")
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
    static func getAllAccounts() async throws -> [FirestoreAccount] {
        let emulatorAccountsURL = try XCTUnwrap(
            URL(string: "http://localhost:9099/identitytoolkit.googleapis.com/v1/projects/\(projectId)/accounts:query")
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
    static func createAccount(email: String, password: String, displayName: String) async throws {
        let emulatorAccountsURL = try XCTUnwrap(
            URL(string: "http://localhost:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(projectId)")
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
