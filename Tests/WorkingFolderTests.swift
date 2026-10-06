import Foundation
import Security
import Testing
@testable import SillyMIDITools

/// Real security-scoped bookmarks need the app-scope entitlement, which an unsigned build (`CODE_SIGNING_ALLOWED=NO`) doesn't carry.
private let canMakeScopedBookmarks: Bool = {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    return SecTaskCopyValueForEntitlement(task, "com.apple.security.files.bookmarks.app-scope" as CFString, nil) as? Bool == true
}()

private final class MemoryBookmarks: BookmarkStorage {
    var values: [String: Data] = [:]
    func data(for key: String) -> Data? { values[key] }
    func set(_ data: Data?, for key: String) { values[key] = data }
}

private final class PathCodec: BookmarkCodec {
    var isStale = false
    var failsToResolve = false
    struct Unresolvable: Error {}

    func makeBookmark(for url: URL) throws -> Data { Data(url.path.utf8) }
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        if failsToResolve { throw Unresolvable() }
        return (URL(fileURLWithPath: String(decoding: data, as: UTF8.self), isDirectory: true), isStale)
    }
}

private final class CountingAccess: ScopedAccess {
    var starts: [URL] = []
    var stops: [URL] = []
    var grants = true
    var open: Int { starts.count - stops.count }
    func start(_ url: URL) -> Bool {
        if grants { starts.append(url) }
        return grants
    }
    func stop(_ url: URL) { stops.append(url) }
}

@MainActor
private final class FakePanel: FolderPanel {
    var result: Result<URL, Error>
    var asked: [(directory: URL, message: String)] = []
    init(_ result: Result<URL, Error>) { self.result = result }
    func chooseFolder(startingIn directory: URL, message: String, completion: @escaping (Result<URL, Error>) -> Void) {
        asked.append((directory, message))
        completion(result)
    }
}

@MainActor
struct WorkingFolderTests {
    private let storage = MemoryBookmarks()
    private let codec = PathCodec()
    private let access = CountingAccess()

    private func store() -> WorkingFolderStore {
        WorkingFolderStore(storage: storage, codec: codec, access: access)
    }

    private func tempFolder(_ name: String = "grant") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "scratch-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func folderChangesAreAnnouncedOnce() throws {
        let first = try tempFolder("first")
        let second = try tempFolder("second")
        let store = store()
        var announced: [URL?] = []
        store.onFolderChange = { announced.append($0) }

        store.handlePick(.success(first))
        store.handlePick(.success(first))
        store.handlePick(.success(second))
        store.reset()

        #expect(announced == [first, second, nil])
    }

    @Test func freshGrantCreatesSubfoldersAndStoresBookmark() throws {
        let folder = try tempFolder()
        let store = store()
        #expect(!store.isResolved)
        #expect(store.handlePick(.success(folder)))
        #expect(store.folder == folder)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Audio").path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "MIDI").path))
        #expect(store.audioFolder?.lastPathComponent == "Audio")
        #expect(store.midiFolder?.lastPathComponent == "MIDI")
        #expect(storage.values[WorkingFolderStore.bookmarkKey] == Data(folder.path.utf8))
    }

    @Test func thePanelIsAskedAtTheSuggestedPlaceAndItsChoiceAdopted() throws {
        let folder = try tempFolder()
        let store = store()
        let panel = FakePanel(.success(folder))
        var adopted: Bool?
        store.choose(using: panel, startingIn: WorkingFolderStore.suggestedFolder.deletingLastPathComponent()) { adopted = $0 }
        #expect(adopted == true && store.folder == folder)
        #expect(panel.asked.first?.directory.lastPathComponent == "Documents")
        #expect(panel.asked.first?.message == WorkingFolderStore.panelMessage)

        panel.result = .failure(CocoaError(.userCancelled))
        store.choose(using: panel, startingIn: folder) { adopted = $0 }
        #expect(adopted == false && store.folder == folder && store.errorMessage == nil)
    }

    @Test func cancelledPanelChangesNothing() throws {
        let first = try tempFolder()
        let store = store()
        try store.adopt(first)
        let before = storage.values[WorkingFolderStore.bookmarkKey]
        #expect(!store.handlePick(.failure(CocoaError(.userCancelled))))
        #expect(store.folder == first)
        #expect(storage.values[WorkingFolderStore.bookmarkKey] == before)
        #expect(store.errorMessage == nil)
    }

    @Test func pickerErrorIsReportedAndKeepsOldGrant() throws {
        let first = try tempFolder()
        let store = store()
        try store.adopt(first)
        struct PickerFailure: LocalizedError { var errorDescription: String? { "The picker failed." } }
        #expect(!store.handlePick(.failure(PickerFailure())))
        #expect(store.folder == first)
        #expect(store.errorMessage == "The picker failed.")
    }

    @Test func readOnlyFolderIsRefusedAndKeepsOldGrant() throws {
        let good = try tempFolder("good")
        let readOnly = try tempFolder("readonly")
        let store = store()
        try store.adopt(good)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path) }

        #expect(!store.handlePick(.success(readOnly)))
        #expect(store.folder == good)
        #expect(storage.values[WorkingFolderStore.bookmarkKey] == Data(good.path.utf8))
        #expect(store.errorMessage?.contains("readonly") == true)
        #expect(access.open == 1)
        #expect(!FileManager.default.fileExists(atPath: readOnly.appending(path: "Audio").path))
    }

    @Test func staleBookmarkIsRenewedOnResolve() throws {
        let folder = try tempFolder()
        storage.set(Data("old-bookmark".utf8), for: WorkingFolderStore.bookmarkKey)
        let renewing = PathCodecRenewal(folder: folder)
        let store = WorkingFolderStore(storage: storage, codec: renewing, access: access)
        store.resolveAtLaunch()
        #expect(store.folder == folder)
        #expect(storage.values[WorkingFolderStore.bookmarkKey] == Data("fresh:\(folder.path)".utf8))
    }

    @Test func relaunchResolvesStoredBookmark() throws {
        let folder = try tempFolder()
        try store().adopt(folder)

        let relaunched = store()
        #expect(!relaunched.isResolved)
        relaunched.resolveAtLaunch()
        #expect(relaunched.folder == folder)
        #expect(relaunched.errorMessage == nil)
    }

    @Test func unresolvableBookmarkLeavesWelcomeVisible() throws {
        let folder = try tempFolder()
        try store().adopt(folder)
        codec.failsToResolve = true
        let relaunched = store()
        relaunched.resolveAtLaunch()
        #expect(!relaunched.isResolved)
        #expect(relaunched.errorMessage != nil)
    }

    @Test func scopedAccessStaysBalancedAcrossSwapAndReset() throws {
        let a = try tempFolder("a")
        let b = try tempFolder("b")
        let store = store()
        try store.adopt(a)
        #expect(access.open == 1)
        try store.adopt(b)
        #expect(access.open == 1)
        #expect(access.stops == [a])
        store.reset()
        #expect(access.open == 0)
        #expect(!store.isResolved)
        #expect(storage.values[WorkingFolderStore.bookmarkKey] == nil)
    }

    @Test func changingFolderNeverMovesExistingFiles() throws {
        let old = try tempFolder("old")
        let new = try tempFolder("new")
        let store = store()
        try store.adopt(old)
        let audio = old.appending(path: "Audio/take.wav")
        try Data([1, 2, 3]).write(to: audio)

        try store.adopt(new)
        #expect(FileManager.default.fileExists(atPath: audio.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: new.appending(path: "Audio").path).isEmpty)
    }

    @Test(.enabled(if: canMakeScopedBookmarks, "needs the app-scope bookmark entitlement; run with CODE_SIGN_IDENTITY=-"))
    func systemCodecRoundTripsAFolderBookmark() throws {
        let folder = try tempFolder()
        let codec = SystemBookmarkCodec()
        let data = try codec.makeBookmark(for: folder)
        let resolved = try codec.resolve(data)
        #expect(resolved.url.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath())
        #expect(!resolved.isStale)
    }
}

private final class PathCodecRenewal: BookmarkCodec {
    let folder: URL
    init(folder: URL) { self.folder = folder }
    func makeBookmark(for url: URL) throws -> Data { Data("fresh:\(url.path)".utf8) }
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) { (folder, true) }
}
