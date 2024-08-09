//
// This source file is part of the Stanford Spezi open-source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import FirebaseStorage
import Spezi
import SpeziFirebaseConfiguration


/// Configures the Firebase Storage that can then be used within any application via `Storage.storage()`.
///
/// The `FirebaseStorageConfiguration` can be used to connect to the Firebase Storage emulator:
/// ```
/// class ExampleAppDelegate: SpeziAppDelegate {
///     override var configuration: Configuration {
///         Configuration {
///             FirebaseStorageConfiguration(emulatorSettings: (host: "localhost", port: 9199))
///             // ...
///         }
///     }
/// }
/// ```
///
/// ## Topics
///
/// ### Configuration
/// - ``init()``
/// - ``init(emulatorSettings:)``
public final class FirebaseStorageConfiguration: Module, DefaultInitializable {
    @Dependency(ConfigureFirebaseApp.self)
    private var configureFirebaseApp

    private let emulatorSettings: (host: String, port: Int)?
    

    /// Default configuration.
    public required convenience init() {
        self.init(emulatorSettings: nil)
    }
    
    /// Configure with emulator settings.
    /// - Parameters:
    ///   - emulatorSettings: The emulator settings. When using `nil`, FirebaseStorage module will connect to the FirebaseStorage cloud instance.
    public init(
        emulatorSettings: (host: String, port: Int)?
    ) {
        self.emulatorSettings = emulatorSettings
    }
    

    @_documentation(visibility: internal)
    public func configure() {
        if let emulatorSettings {
            Storage.storage().useEmulator(withHost: emulatorSettings.host, port: emulatorSettings.port)
        }
    }
}
