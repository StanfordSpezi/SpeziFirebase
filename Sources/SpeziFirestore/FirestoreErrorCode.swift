//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseFirestore
import FirebaseFirestoreSwift
import Foundation


/// Mapping of Firestore error codes to a localized error.
public enum FirestoreError: LocalizedError {
    case cancelled
    case invalidArgument
    case deadlineExceeded
    case notFound
    case alreadyExists
    case permissionDenied
    case resourceExhausted
    case failedPrecondition
    case aborted
    case outOfRange
    case unimplemented
    case `internal`
    case unavailable
    case dataLoss
    case unauthenticated
    case decodingNotSupported(String)
    case decodingFieldConflict(String)
    case encodingNotSupported(String)
    case unknown
    
    
    private var errorDescriptionValue: String.LocalizationValue {
        switch self {
        case .cancelled:
            return "FIRESTORE_ERROR_CANCELLED"
        case .invalidArgument:
            return "FIRESTORE_ERROR_INVALIDARGUMENT"
        case .deadlineExceeded:
            return "FIRESTORE_ERROR_DEADLINEEXCEEDED"
        case .notFound:
            return "FIRESTORE_ERROR_NOTFOUND"
        case .alreadyExists:
            return "FIRESTORE_ERROR_ALREADYEXISTS"
        case .permissionDenied:
            return "FIRESTORE_ERROR_PERMISSIONDENIED"
        case .resourceExhausted:
            return "FIRESTORE_ERROR_RESOURCEEXHAUSTED"
        case .failedPrecondition:
            return "FIRESTORE_ERROR_FAILEDPRECONDITION"
        case .aborted:
            return "FIRESTORE_ERROR_ABORTED"
        case .outOfRange:
            return "FIRESTORE_ERROR_OUTOFRANGE"
        case .unimplemented:
            return "FIRESTORE_ERROR_UNIMPLEMENTED"
        case .internal:
            return "FIRESTORE_ERROR_INTERNAL"
        case .unavailable:
            return "FIRESTORE_ERROR_UNAVAILABLE"
        case .dataLoss:
            return "FIRESTORE_ERROR_DATALOSS"
        case .unauthenticated:
            return "FIRESTORE_ERROR_UNAUTHENTICATED"
        case let .decodingNotSupported(reason):
            return "FIRESTORE_ERROR_DECODINGNOTSUPPORTED \(reason)"
        case let .decodingFieldConflict(reason):
            return "FIRESTORE_ERROR_DECODINGFIELDCONFLICT \(reason)"
        case let .encodingNotSupported(reason):
            return "FIRESTORE_ERROR_ENCODINGNOTSUPPORTED \(reason)"
        case .unknown:
            return "FIRESTORE_ERROR_UNKNOWN"
        }
    }

    public var errorDescription: String? {
        .init(localized: errorDescriptionValue, bundle: .module)
    }

    
    public init<E: Error>(_ error: E) {
        if let firestoreError = error as? Self {
            self = firestoreError
            return
        }
        
        if let firestoreDecodingError = error as? FirestoreDecodingError {
            switch firestoreDecodingError {
            case let .decodingIsNotSupported(reason):
                self = .decodingNotSupported(reason)
            case let .fieldNameConflict(reason):
                self = .decodingFieldConflict(reason)
            }
            return
        }
        
        if let firestoreEncodingError = error as? FirestoreEncodingError {
            switch firestoreEncodingError {
            case let .encodingIsNotSupported(reason):
                self = .encodingNotSupported(reason)
            }
            return
        }
        
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain {
            switch nsError.code {
            case FirestoreErrorCode.cancelled.rawValue:
                self = .cancelled
            case FirestoreErrorCode.unknown.rawValue:
                self = .unknown
            case FirestoreErrorCode.invalidArgument.rawValue:
                self = .invalidArgument
            case FirestoreErrorCode.deadlineExceeded.rawValue:
                self = .deadlineExceeded
            case FirestoreErrorCode.notFound.rawValue:
                self = .notFound
            case FirestoreErrorCode.alreadyExists.rawValue:
                self = .alreadyExists
            case FirestoreErrorCode.permissionDenied.rawValue:
                self = .permissionDenied
            case FirestoreErrorCode.resourceExhausted.rawValue:
                self = .resourceExhausted
            case FirestoreErrorCode.failedPrecondition.rawValue:
                self = .failedPrecondition
            case FirestoreErrorCode.aborted.rawValue:
                self = .aborted
            case FirestoreErrorCode.outOfRange.rawValue:
                self = .outOfRange
            case FirestoreErrorCode.unimplemented.rawValue:
                self = .unimplemented
            case FirestoreErrorCode.internal.rawValue:
                self = .internal
            case FirestoreErrorCode.unavailable.rawValue:
                self = .unavailable
            case FirestoreErrorCode.dataLoss.rawValue:
                self = .dataLoss
            case FirestoreErrorCode.unauthenticated.rawValue:
                self = .unauthenticated
            default:
                self = .unknown
            }
            return
        }
        
        self = .unknown
    }
}
