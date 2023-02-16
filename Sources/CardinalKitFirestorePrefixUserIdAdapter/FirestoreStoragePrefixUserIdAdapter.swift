//
// This source file is part of the CardinalKit open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import CardinalKit
import CardinalKitFirestore
import FirebaseAuth


/// Adds a `users/<USER_ID>/` prefix to any uploaded or removed firestore element.
///
/// You can, e.g., use the ``FirestorePrefixUserIdAdapter`` as a final transformation step in the adapter chain to add the
/// `users/<USER_ID>/` prefix:
/// ```
/// Firestore(
///     adapter: {
///         // ...
///         FirestoreStoragePrefixUserIdAdapter()
///     },
///     settings: .emulator
/// )
/// ```
public actor FirestorePrefixUserIdAdapter: SingleValueAdapter {
    public typealias InputElement = FirestoreElement
    public typealias InputRemovalContext = FirestoreRemovalContext
    public typealias OutputElement = FirestoreElement
    public typealias OutputRemovalContext = FirestoreRemovalContext
    
    
    public init() {}
    
    
    public func transform(element: FirestoreElement) throws -> FirestoreElement {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw FirestorePrefixUserIdAdapterError.userNotSignedIn
        }
        
        var modifiedElement = element
        modifiedElement.collectionPath = "users/" + userID.id + "/" + element.collectionPath
        return modifiedElement
    }
    
    public func transform(removalContext: FirestoreRemovalContext) throws -> FirestoreRemovalContext {
        guard let userID = Auth.auth().currentUser?.uid else {
            throw FirestorePrefixUserIdAdapterError.userNotSignedIn
        }
        
        var modifiedRemovalContext = removalContext
        modifiedRemovalContext.collectionPath = "users/" + userID.id + "/" + removalContext.collectionPath
        return modifiedRemovalContext
    }
}
