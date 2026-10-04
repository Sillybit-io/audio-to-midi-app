import Foundation
import Observation

@MainActor
protocol ModelInstalling: AnyObject {
    func state(for entry: ModelEntry) -> InstallState
    func install(_ entry: ModelEntry) async
}

extension ModelStore: ModelInstalling {}

/// Gets a model onto the disk before a run: the first-use alert for gated weights, then `ModelStore.install`,
/// which asks the access policy (the licence sheet) and downloads and verifies the file.
@MainActor @Observable
final class FirstUseTranscription {
    enum Outcome: Equatable {
        case ready
        case cancelled
        case failed(String)
    }

    /// Set while the first-use alert is waiting for an answer.
    private(set) var consentRequest: ModelEntry?
    /// The model being fetched; a second request for any model is ignored until this one ends.
    private(set) var preparing: ModelEntry?

    @ObservationIgnored private let installer: any ModelInstalling
    @ObservationIgnored private let settle: Duration
    @ObservationIgnored private var consent: CheckedContinuation<Bool, Never>?

    /// `settle` gives the first-use alert time to finish dismissing before the licence sheet is presented.
    init(installer: any ModelInstalling, settle: Duration = .milliseconds(400)) {
        self.installer = installer
        self.settle = settle
    }

    func prepare(_ entry: ModelEntry) async -> Outcome {
        if installer.state(for: entry) == .installed { return .ready }
        guard preparing == nil else { return .cancelled }
        preparing = entry
        defer { preparing = nil }
        if entry.gated {
            guard await askConsent(entry) else { return .cancelled }
            try? await Task.sleep(for: settle)
        }
        await installer.install(entry)
        switch installer.state(for: entry) {
        case .installed: return .ready
        case .failed(let message): return Task.isCancelled ? .cancelled : .failed(Self.friendly(message))
        default: return .failed("The download didn\u{2019}t finish.")
        }
    }

    func answerConsent(_ approved: Bool) {
        consentRequest = nil
        consent?.resume(returning: approved)
        consent = nil
    }

    private func askConsent(_ entry: ModelEntry) async -> Bool {
        consentRequest = entry
        return await withCheckedContinuation { consent = $0 }
    }

    static func friendly(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("offline") || lower.contains("internet connection") || lower.contains("network connection") {
            return "You\u{2019}re offline. Check your connection, then try again. Nothing was changed."
        }
        return message
    }
}
