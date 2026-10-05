import Foundation
import Testing
@testable import SillyMIDITools

@MainActor
struct SettingsPreferencesTests {
    private func suite() -> (UserDefaults, () -> Void) {
        let name = "smt-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func freshInstallDefaults() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.defaultModelID == "basic-pitch")
        #expect(preferences.appearance == .automatic)
        #expect(preferences.addAudioMode == .copy)
        #expect(preferences.followPlayhead)
        #expect(preferences.appearance.colorScheme == nil)
    }

    @Test func choicesPersistAcrossLaunches() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        let first = AppPreferences(defaults: defaults)
        first.appearance = .dark
        first.addAudioMode = .reference
        first.followPlayhead = false
        first.defaultModelID = "piano-onnx"

        let relaunched = AppPreferences(defaults: defaults)
        #expect(relaunched.appearance == .dark)
        #expect(relaunched.addAudioMode == .reference)
        #expect(!relaunched.followPlayhead)
        #expect(relaunched.defaultModelID == "piano-onnx")
    }

    @Test func unreadableStoredValuesFallBack() {
        let (defaults, cleanup) = suite()
        defer { cleanup() }
        defaults.set("sepia", forKey: AppPreferences.appearanceKey)
        defaults.set("teleport", forKey: AppPreferences.addAudioModeKey)
        defaults.set("gone", forKey: AppPreferences.defaultModelKey)
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.appearance == .automatic)
        #expect(preferences.addAudioMode == .copy)
        #expect(preferences.defaultModelID == "basic-pitch")
    }

    private func installedStore() throws -> (ModelStore, ModelEntry, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "scratch-models-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = ModelCatalog.entries.first { $0.id == "muscriptor-small" }!
        let file = directory.appending(path: entry.fileName)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(entry.byteSize))
        try handle.close()
        return (ModelStore(directory: directory), entry, file)
    }

    @Test func confirmedDeleteRemovesTheFileAndResetsTheRow() throws {
        let (store, entry, file) = try installedStore()
        #expect(store.state(for: entry) == .installed)
        store.delete(entry)
        #expect(store.state(for: entry) == .notInstalled)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(store.deleteError == nil)
    }

    @Test func aDeleteThatFailsKeepsTheModelInstalledAndSaysWhy() throws {
        let (store, entry, file) = try installedStore()
        let directory = file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        store.delete(entry)
        #expect(store.state(for: entry) == .installed)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(store.deleteError?.contains(entry.displayName) == true)
    }

    @Test func deletingAFileThatIsAlreadyGoneStillResetsTheRow() throws {
        let (store, entry, file) = try installedStore()
        try FileManager.default.removeItem(at: file)
        store.delete(entry)
        #expect(store.state(for: entry) == .notInstalled)
        #expect(store.deleteError == nil)
    }
}
