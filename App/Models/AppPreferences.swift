import Foundation
import Observation

@MainActor @Observable
final class AppPreferences {
    static let defaultModelKey = "defaultModel"
    static let fallbackModelID = "basic-pitch"

    /// The model a new Audio screen starts on. Basic Pitch is built in, so a first Transcribe never waits for a download.
    var defaultModelID: String {
        didSet { defaults.set(defaultModelID, forKey: Self.defaultModelKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.defaultModelKey)
        defaultModelID = ModelCatalog.entries.contains { $0.id == stored } ? stored! : Self.fallbackModelID
    }
}
