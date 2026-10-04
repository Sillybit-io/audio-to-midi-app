import Foundation
import Testing
@testable import SillyMIDITools

private final class MemoryStore: BookmarkStorage {
    var values: [String: Data] = [:]
    func data(for key: String) -> Data? { values[key] }
    func set(_ data: Data?, for key: String) { values[key] = data }
}

private final class PathBookmarks: BookmarkCodec {
    var failsToMake = false
    struct Failure: Error {}
    func makeBookmark(for url: URL) throws -> Data {
        if failsToMake { throw Failure() }
        return Data(url.path.utf8)
    }
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), false)
    }
}

private final class NoAccess: ScopedAccess {
    func start(_ url: URL) -> Bool { false }
    func stop(_ url: URL) {}
}

@MainActor
private final class FakeWatcher: FolderWatcher {
    var handlers: [URL: @MainActor () -> Void] = [:]
    var cancelled = 0

    @MainActor private final class Handle: FolderWatching {
        let onCancel: () -> Void
        init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
        func cancel() { onCancel() }
    }

    func watch(_ url: URL, onChange: @escaping @MainActor () -> Void) -> (any FolderWatching)? {
        handlers[url] = onChange
        return Handle { [weak self] in self?.cancelled += 1 }
    }

    func fire(_ url: URL) { handlers[url]?() }
}

@MainActor
struct LibraryStoreTests {
    private let storage = MemoryStore()
    private let codec = PathBookmarks()
    private let watcher = FakeWatcher()

    private func imports() -> AudioImportStore {
        AudioImportStore(storage: storage, codec: codec, access: NoAccess())
    }

    private func library(_ imports: AudioImportStore) -> LibraryStore {
        LibraryStore(imports: imports, watcher: watcher)
    }

    private func makeFolders(_ name: String = "wf") throws -> (audio: URL, midi: URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "smt-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .isDirectory)
        let audio = root.appending(path: "Audio", directoryHint: .isDirectory)
        let midi = root.appending(path: "MIDI", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: midi, withIntermediateDirectories: true)
        return (audio, midi)
    }

    private func touch(_ url: URL, _ bytes: [UInt8] = [0]) throws {
        try Data(bytes).write(to: url)
    }

    @Test func watcherEventRefreshesTheListing() throws {
        let folders = try makeFolders()
        let library = library(imports())
        library.attach(audio: folders.audio, midi: folders.midi)
        #expect(library.audio.isEmpty && library.midi.isEmpty)

        try touch(folders.audio.appending(path: "take.wav"))
        try touch(folders.midi.appending(path: "take.mid"))
        watcher.fire(folders.audio)
        watcher.fire(folders.midi)
        #expect(library.audio.map(\.fileName) == ["take.wav"])
        #expect(library.midi.map(\.fileName) == ["take.mid"])
    }

    @Test func listingIsInStableNaturalOrderAndSkipsOtherFiles() throws {
        let folders = try makeFolders()
        for name in ["b.wav", "a 10.wav", "a 2.wav", "notes.txt", ".hidden.wav"] { try touch(folders.audio.appending(path: name)) }
        try FileManager.default.createDirectory(at: folders.audio.appending(path: "folder.wav"), withIntermediateDirectories: true)
        let library = library(imports())
        library.attach(audio: folders.audio, midi: folders.midi)
        #expect(library.audio.map(\.fileName) == ["a 2.wav", "a 10.wav", "b.wav"])
        library.refresh()
        #expect(library.audio.map(\.fileName) == ["a 2.wav", "a 10.wav", "b.wav"])
    }

    @Test func copyImportKeepsTheOriginalAndNumbersCollisions() throws {
        let folders = try makeFolders()
        let source = FileManager.default.temporaryDirectory.appending(path: "smt-src-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let original = source.appending(path: "take.wav")
        try touch(original, [1, 2, 3])
        let imports = imports()

        let first = try imports.importAudio(from: original, mode: .copy, audioFolder: folders.audio)
        let second = try imports.importAudio(from: original, mode: .copy, audioFolder: folders.audio)
        #expect(first.lastPathComponent == "take.wav")
        #expect(second.lastPathComponent == "take 2.wav")
        #expect(try Data(contentsOf: first) == Data([1, 2, 3]))
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(imports.references.isEmpty)
        #expect(try imports.importAudio(from: first, mode: .copy, audioFolder: folders.audio) == first)
    }

    @Test func referenceSurvivesASimulatedRelaunch() throws {
        let folders = try makeFolders()
        let source = FileManager.default.temporaryDirectory.appending(path: "smt-ref-\(UUID().uuidString).wav")
        try touch(source)
        let first = imports()
        let target = try first.importAudio(from: source, mode: .reference, audioFolder: folders.audio)
        #expect(target == source)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folders.audio.path).isEmpty)

        let relaunched = imports()
        #expect(relaunched.references.count == 1)
        let library = library(relaunched)
        library.attach(audio: folders.audio, midi: folders.midi)
        let entry = try #require(library.audio.first)
        #expect(entry.isReference && !entry.isMissing)
        #expect(entry.url.standardizedFileURL == source.standardizedFileURL)
    }

    @Test func missingReferenceIsFlaggedAndRelinkRestoresIt() throws {
        let folders = try makeFolders()
        let keep = folders.audio.appending(path: "keep.wav")
        try touch(keep)
        let gone = FileManager.default.temporaryDirectory.appending(path: "smt-gone-\(UUID().uuidString).wav")
        try touch(gone)
        let imports = imports()
        _ = try imports.importAudio(from: gone, mode: .reference, audioFolder: folders.audio)
        try FileManager.default.removeItem(at: gone)

        let library = library(imports)
        library.attach(audio: folders.audio, midi: folders.midi)
        #expect(library.audio.count == 2)
        let broken = try #require(library.audio.first { $0.isReference })
        #expect(broken.isMissing)
        #expect(library.audio.first { $0.fileName == "keep.wav" }?.isMissing == false)

        let replacement = FileManager.default.temporaryDirectory.appending(path: "smt-new-\(UUID().uuidString).wav")
        try touch(replacement)
        let reference = try #require(imports.references.first)
        try imports.relink(reference, to: replacement)
        library.refresh()
        let fixed = try #require(library.audio.first { $0.isReference })
        #expect(!fixed.isMissing)
        #expect(fixed.url.standardizedFileURL == replacement.standardizedFileURL)
    }

    @Test func switchingFoldersChangesTheListingWithoutMovingFiles() throws {
        let a = try makeFolders("a")
        let b = try makeFolders("b")
        try touch(a.audio.appending(path: "one.wav"))
        let library = library(imports())
        library.attach(audio: a.audio, midi: a.midi)
        #expect(library.audio.map(\.fileName) == ["one.wav"])

        library.attach(audio: b.audio, midi: b.midi)
        #expect(library.audio.isEmpty)
        #expect(watcher.cancelled == 2)
        #expect(FileManager.default.fileExists(atPath: a.audio.appending(path: "one.wav").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: b.audio.path).isEmpty)

        library.attach(audio: nil, midi: nil)
        #expect(library.audio.isEmpty && library.midi.isEmpty)
        #expect(watcher.cancelled == 4)
    }

    @Test func failedCopyOrBookmarkRecordsNothing() throws {
        let folders = try makeFolders()
        let imports = imports()
        let missing = FileManager.default.temporaryDirectory.appending(path: "smt-nothing-\(UUID().uuidString).wav")
        #expect(throws: AudioImportError.self) { try imports.importAudio(from: missing, mode: .copy, audioFolder: folders.audio) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folders.audio.path).isEmpty)

        let real = FileManager.default.temporaryDirectory.appending(path: "smt-real-\(UUID().uuidString).wav")
        try touch(real)
        codec.failsToMake = true
        #expect(throws: AudioImportError.self) { try imports.importAudio(from: real, mode: .reference, audioFolder: folders.audio) }
        #expect(imports.references.isEmpty)
        #expect(storage.values[AudioImportStore.referencesKey].flatMap { try? JSONDecoder().decode([AudioReference].self, from: $0) }?.isEmpty ?? true)
        #expect(throws: AudioImportError.noWorkingFolder) { try imports.importAudio(from: real, mode: .copy, audioFolder: nil) }
    }
}
