//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseCore
import FirebaseStorage
import Spezi


/// Configures the Firebase Storage that can then be used within any application via `Storage.storage()`.
///
/// The ``FirebaseStorageConfiguration`` can be used to connect to the Firebase Storage emulator:
/// ```
/// class ExampleAppDelegate: SpeziAppDelegate {
///     override var configuration: Configuration {
///         Configuration(standard: /* ... */) {
///             FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
///             // ...
///         }
///     }
/// }
/// ```
public final class FirebaseStorageConfiguration: Component, DefaultInitializable {
    @Dependency private var configureFirebaseApp: ConfigureFirebaseApp
    
    private let emulatorSettings: (host: String, port: Int)?
    
    
    /// - Parameters:
    ///   - emulatorSettings: The emulator settings. The default value is `nil`, connecting the FirebaseStorage module to the FirebaseStorage cloud instance.
    public init(
        emulatorSettings: (host: String, port: Int)? = nil
    ) {
        self.emulatorSettings = emulatorSettings
    }
    
    
    public func configure() {
        if let emulatorSettings {
            Storage.storage().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }
    }
}
