import Foundation
import Testing
@testable import SillyMIDITools

@MainActor
private final class FakeInstaller: ModelInstalling {
    var states: [String: InstallState] = [:]
    var installs: [String] = []
    var outcome: InstallState = .installed
    var consentWasAskedBeforeInstall: (() -> Bool)?
    var consentAtInstall: Bool?
    var hold = false

    func state(for entry: ModelEntry) -> InstallState {
        entry.needsDownload ? (states[entry.id] ?? .notInstalled) : .installed
    }

    func install(_ entry: ModelEntry) async {
        consentAtInstall = consentWasAskedBeforeInstall?()
        installs.append(entry.id)
        states[entry.id] = .downloading(0)
        while hold { await Task.yield() }
        states[entry.id] = outcome
    }
}

private func entry(_ id: String) -> ModelEntry {
    ModelCatalog.entries.first { $0.id == id }!
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<2000 where !condition() { await Task.yield() }
}

@MainActor
struct FirstUseTranscriptionTests {
    private let installer = FakeInstaller()

    @Test func freshPreferencesSelectBasicPitchAndKeepTheChoice() {
        let suite = "smt-prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.defaultModelID == "basic-pitch")
        preferences.defaultModelID = "muscriptor-medium"
        #expect(AppPreferences(defaults: defaults).defaultModelID == "muscriptor-medium")
        defaults.set("no-such-model", forKey: AppPreferences.defaultModelKey)
        #expect(AppPreferences(defaults: defaults).defaultModelID == "basic-pitch")
    }

    @Test func basicPitchIsReadyWithoutAnyInstall() async {
        let outcome = await FirstUseTranscription(installer: installer, settle: .zero).prepare(entry("basic-pitch"))
        #expect(outcome == .ready)
        #expect(installer.installs.isEmpty)
    }

    @Test func installedModelNeverInstallsAgain() async {
        installer.states["muscriptor-small"] = .installed
        let outcome = await FirstUseTranscription(installer: installer, settle: .zero).prepare(entry("muscriptor-small"))
        #expect(outcome == .ready)
        #expect(installer.installs.isEmpty)
    }

    @Test func gatedModelAsksBeforeItInstalls() async {
        let firstUse = FirstUseTranscription(installer: installer, settle: .zero)
        installer.consentWasAskedBeforeInstall = { [weak firstUse] in firstUse?.consentRequest == nil }
        let task = Task { await firstUse.prepare(entry("muscriptor-small")) }
        await waitUntil { firstUse.consentRequest != nil }
        #expect(firstUse.consentRequest?.id == "muscriptor-small")
        #expect(installer.installs.isEmpty)
        firstUse.answerConsent(true)
        #expect(await task.value == .ready)
        #expect(installer.installs == ["muscriptor-small"])
        #expect(installer.consentAtInstall == true)
        #expect(firstUse.consentRequest == nil && firstUse.preparing == nil)
    }

    @Test func decliningTheAlertInstallsNothing() async {
        let firstUse = FirstUseTranscription(installer: installer, settle: .zero)
        let task = Task { await firstUse.prepare(entry("muscriptor-medium")) }
        await waitUntil { firstUse.consentRequest != nil }
        firstUse.answerConsent(false)
        #expect(await task.value == .cancelled)
        #expect(installer.installs.isEmpty)
        #expect(firstUse.preparing == nil)
    }

    @Test func pianoDownloadsInlineWithoutTheAlert() async {
        let firstUse = FirstUseTranscription(installer: installer, settle: .zero)
        #expect(await firstUse.prepare(entry("piano-onnx")) == .ready)
        #expect(installer.installs == ["piano-onnx"])
        #expect(firstUse.consentRequest == nil)
    }

    @Test func offlineFailureIsFriendlyAndRetryWorks() async {
        let firstUse = FirstUseTranscription(installer: installer, settle: .zero)
        installer.outcome = .failed("The Internet connection appears to be offline.")
        let failed = await firstUse.prepare(entry("piano-onnx"))
        #expect(failed == .failed("You\u{2019}re offline. Check your connection, then try again. Nothing was changed."))

        installer.outcome = .installed
        #expect(await firstUse.prepare(entry("piano-onnx")) == .ready)
        #expect(installer.installs == ["piano-onnx", "piano-onnx"])
    }

    @Test func otherFailuresKeepTheirMessage() async {
        installer.outcome = .failed(ModelStoreError.checksumMismatch.localizedDescription)
        let outcome = await FirstUseTranscription(installer: installer, settle: .zero).prepare(entry("piano-onnx"))
        #expect(outcome == .failed("The downloaded file failed its checksum and was deleted."))
    }

    @Test func aSecondRequestWhileDownloadingDoesNotInstallTwice() async {
        let firstUse = FirstUseTranscription(installer: installer, settle: .zero)
        installer.hold = true
        let first = Task { await firstUse.prepare(entry("piano-onnx")) }
        await waitUntil { installer.installs.count == 1 }
        #expect(await firstUse.prepare(entry("piano-onnx")) == .cancelled)
        installer.hold = false
        #expect(await first.value == .ready)
        #expect(installer.installs == ["piano-onnx"])
    }

    @Test func screenModelStartsOnBasicPitchAndLabelsAMissingModel() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "smt-models-\(UUID().uuidString)", directoryHint: .isDirectory)
        let suite = "smt-screen-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let screen = AudioScreenModel(document: DocumentModel(), store: ModelStore(directory: directory),
                                      session: TranscriptionSession(), access: AccessCoordinator(keychain: KeychainStore(service: "smt-test-\(UUID().uuidString)")),
                                      preferences: AppPreferences(defaults: defaults))
        #expect(screen.selectedModel == "basic-pitch")
        #expect(screen.transcribeLabel == "Transcribe")
        screen.selectedModel = "muscriptor-small"
        #expect(screen.transcribeLabel == "Download & Transcribe")
        #expect(!screen.canStart)
        #expect(screen.runPanel == nil)
    }
}
