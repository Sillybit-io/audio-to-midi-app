import Foundation
import MetricKit

/// Keeps the debug log in step with the Settings switch and the working folder, from launch on.
@MainActor
enum DebugLogSetup {
    private static let diagnostics = SystemDiagnostics(log: .shared)
    private static var subscribed = false

    static func connect(preferences: AppPreferences, folder: WorkingFolderStore) {
        let apply = { [weak preferences, weak folder] in
            guard let preferences, let folder else { return }
            let wasOn = DebugLog.shared.isEnabled
            DebugLog.shared.configure(enabled: preferences.debugLogging, folder: folder.folder)
            let isOn = DebugLog.shared.isEnabled
            if isOn && !wasOn { describe(preferences) }
            if isOn != subscribed {
                if isOn { MXMetricManager.shared.add(diagnostics) } else { MXMetricManager.shared.remove(diagnostics) }
                subscribed = isOn
            }
        }
        preferences.onDebugLoggingChange = { _ in apply() }
        folder.onFolderChange = { _ in apply() }
        apply()
    }

    private static func describe(_ preferences: AppPreferences) {
        debugLog(.app, "Debug logging is on. Settings: default model \(preferences.defaultModelID), added audio is "
                 + "\(preferences.addAudioMode == .copy ? "copied into Audio/" : "left where it is"), appearance "
                 + "\(preferences.appearance.rawValue), follow playhead \(preferences.followPlayhead ? "on" : "off").")
    }
}

/// MetricKit hands the app the system's own diagnostics, usually on the launch after a crash or a hang. They are saved
/// next to the logs. Whether macOS delivers them to an app that isn't from the App Store is up to macOS.
final class SystemDiagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let log: DebugLog

    init(log: DebugLog) {
        self.log = log
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let saved = log.saveAttachment(payload.jsonRepresentation(), named: "system diagnostics.json")
            log.log(.app, "macOS delivered diagnostics from \(payload.timeStampBegin) to \(payload.timeStampEnd): \(crashes) crash(es), "
                    + "\(hangs) hang(s). " + (saved.map { "Saved as \($0.lastPathComponent)." } ?? "They couldn\u{2019}t be saved."))
        }
    }
}
