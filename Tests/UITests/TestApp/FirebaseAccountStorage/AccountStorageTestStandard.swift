//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import Spezi
import SpeziAccount
import SpeziFirebaseAccountStorage


actor AccountStorageTestStandard: Standard, AccountStorageConstraint {
    static var collection: CollectionReference {
        Firestore.firestore().collection("users")
    }

    @Dependency var storage = FirestoreAccountStorage(storeIn: collection)


    func create(_ identifier: AdditionalRecordId, _ details: SignupDetails) async throws {
        try await storage.create(identifier, details)
    }
    
    func load(_ identifier: AdditionalRecordId, _ keys: [any AccountKey.Type]) async throws -> PartialAccountDetails {
        try await storage.load(identifier, keys)
    }
    
    func modify(_ identifier: AdditionalRecordId, _ modifications: SpeziAccount.AccountModifications) async throws {
        try await storage.modify(identifier, modifications)
    }
    
    func clear(_ identifier: AdditionalRecordId) async {
        await storage.clear(identifier)
    }
    
    func delete(_ identifier: AdditionalRecordId) async throws {
        try await storage.delete(identifier)
    }
}
