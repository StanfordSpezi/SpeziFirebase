//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


/// Indicates an error on the ``FirestorePrefixUserIdAdapter``.
public enum FirestorePrefixUserIdAdapterError: Error {
    /// The user is not yet signed in.
    case userNotSignedIn
}
