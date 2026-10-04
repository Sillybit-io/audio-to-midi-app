import Foundation
import Observation
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case automatic, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor @Observable
final class AppPreferences {
    static let defaultModelKey = "defaultModel"
    static let appearanceKey = "appearance"
    static let addAudioModeKey = "addAudioMode"
    static let followPlayheadKey = "followPlayhead"
    static let fallbackModelID = "basic-pitch"

    /// The model a new Audio screen starts on. Basic Pitch is built in, so a first Transcribe never waits for a download.
    var defaultModelID: String {
        didSet { defaults.set(defaultModelID, forKey: Self.defaultModelKey) }
    }

    var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// Whether audio added from outside the working folder is copied into `Audio/` or referenced where it is.
    var addAudioMode: AddAudioMode {
        didSet { defaults.set(addAudioMode.rawValue, forKey: Self.addAudioModeKey) }
    }

    var followPlayhead: Bool {
        didSet { defaults.set(followPlayhead, forKey: Self.followPlayheadKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: Self.defaultModelKey)
        defaultModelID = ModelCatalog.entries.contains { $0.id == stored } ? stored! : Self.fallbackModelID
        appearance = defaults.string(forKey: Self.appearanceKey).flatMap(AppearancePreference.init) ?? .automatic
        addAudioMode = defaults.string(forKey: Self.addAudioModeKey).flatMap(AddAudioMode.init) ?? .copy
        followPlayhead = defaults.object(forKey: Self.followPlayheadKey) as? Bool ?? true
    }
}
