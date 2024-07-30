//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import Spezi
import SpeziAccount
import SpeziLocalStorage


struct CachedDetails {
    let details: AccountDetails

    init(_ details: AccountDetails) {
        self.details = details
    }
}


final class LocalDetailsCache: Module, DefaultInitializable {
    @Application(\.logger) private var logger

    @Dependency private var localStorage: LocalStorage

    private var localCache: [String: AccountDetails] = [:]


    init() {}

    func loadEntry(for accountId: String, _ keys: [any AccountKey.Type]) -> AccountDetails? {
        if let details = localCache[accountId] {
            return details
        }

        let decoder = JSONDecoder()
        decoder.userInfo[.accountDetailsKeys] = keys

        do {
            let stored = try localStorage.read(
                CachedDetails.self,
                decoder: decoder,
                storageKey: key(for: accountId),
                settings: .encryptedUsingKeyChain(userPresence: false, excludedFromBackup: false)
            )

            localCache[accountId] = stored.details
            return stored.details
        } catch {
            // TODO: silence error if doesn't exist
            logger.error("Failed to read cached account details from disk: \(error)")
        }

        return nil
    }

    func clearEntry(for accountId: String) {
        localCache.removeValue(forKey: accountId)
        do {
            try localStorage.delete(storageKey: key(for: accountId))
        } catch {
            // TODO: silence error if doesn't exist
            logger.error("Failed to clear cached account details from disk: \(error)")
        }
    }

    func communicateModifications(for accountId: String, _ modifications: AccountModifications) {
        // make sure our cache is consistent
        var details = AccountDetails()
        if let cached = localCache[accountId] {
            details.add(contentsOf: cached)
        }
        details.add(contentsOf: modifications.modifiedDetails, merge: true)
        details.removeAll(modifications.removedAccountKeys)

        communicateRemoteChanges(for: accountId, details)
    }

    func communicateRemoteChanges(for accountId: String, _ details: AccountDetails) {
        localCache[accountId] = details


        let storage = CachedDetails(details)
        do {
            try localStorage.store(
                storage,
                storageKey: key(for: accountId),
                settings: .encryptedUsingKeyChain(userPresence: false, excludedFromBackup: false)
            )
        } catch {
            // TODO: silence error if doesn't exist
            logger.error("Failed to update cached account details to disk: \(error)")
        }
    }

    private func key(for accountId: String) -> String {
        "edu.stanford.spezi.firebase.details.\(accountId)"
    }
}


extension CachedDetails: Codable { // TODO: can we just add Codable conformance to AccountDetails natively?
    struct CodingKeys: CodingKey, RawRepresentable { // TODO: provide a reusable codingKey in SpeziAccount?
        var stringValue: String {
            rawValue
        }

        var intValue: Int? {
            nil
        }

        let rawValue: String

        init(stringValue rawValue: String) {
            self.rawValue = rawValue
        }

        init(rawValue: String) {
            self.rawValue = rawValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    private struct EncoderVisitor: AccountValueVisitor {
        private var container: KeyedEncodingContainer<CodingKeys>
        private var firstError: Error?

        init(_ container: KeyedEncodingContainer<CodingKeys>) {
            self.container = container
        }

        mutating func visit<Key: AccountKey>(_ key: Key.Type, _ value: Key.Value) {
            guard firstError == nil else {
                return
            }

            do {
                try container.encode(value, forKey: CodingKeys(rawValue: key.identifier))
            } catch {
                firstError = error
            }
        }

        func final() -> Result<Void, Error> {
            if let firstError {
                .failure(firstError)
            } else {
                .success(())
            }
        }
    }

    private struct DecoderVisitor: AccountKeyVisitor {
        private let container: KeyedDecodingContainer<CodingKeys>
        private var details = AccountDetails()
        private var firstError: Error?

        init(_ container: KeyedDecodingContainer<CodingKeys>) {
            self.container = container
        }


        mutating func visit<Key: AccountKey>(_ key: Key.Type) {
            guard firstError == nil else {
                return
            }


            do {
                let value = try container.decode(Key.Value.self, forKey: CodingKeys(rawValue: key.identifier))
                details.set(Key.self, value: value)
            } catch {
                firstError = error
            }
        }

        func final() -> Result<AccountDetails, Error> {
            if let firstError {
                .failure(firstError)
            } else {
                .success(details)
            }
        }
    }


    init(from decoder: any Decoder) throws {
        guard let keys = decoder.userInfo[.accountDetailsKeys] as? [any AccountKey.Type] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: """
                                  AccountKeys unspecified. Do decode AccountDetails you must specify requested AccountKey types \
                                  via the `accountDetailsKeys` CodingUserInfoKey.
                                  """
            ))
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        var visitor = DecoderVisitor(container)
        let result = keys.acceptAll(&visitor)

        switch result {
        case let .success(details):
            self.details = details
        case let .failure(error):
            throw error
        }
    }

    func encode(to encoder: any Encoder) throws {
        let container = encoder.container(keyedBy: CodingKeys.self)

        var visitor = EncoderVisitor(container)
        let result = details.acceptAll(&visitor)

        if case let .failure(error) = result {
            throw error
        }
    }
}


extension CodingUserInfoKey {
    static let accountDetailsKeys = {
        guard let key = CodingUserInfoKey(rawValue: "edu.stanford.spezi.account-details") else {
            preconditionFailure("Unable to create `accountDetailsKeys` CodingUserInfoKey!")
        }
        return key
    }()
}
