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

/// Like the sandbox: a bookmark can only be made for a file the app is currently accessing.
private final class SandboxAccess: ScopedAccess, BookmarkCodec {
    var active: [URL] = []
    struct NoAccess: Error {}
    func start(_ url: URL) -> Bool { active.append(url); return true }
    func stop(_ url: URL) { active.removeAll { $0 == url } }
    func makeBookmark(for url: URL) throws -> Data {
        guard active.contains(url) else { throw NoAccess() }
        return Data(url.path.utf8)
    }
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        (URL(fileURLWithPath: String(decoding: data, as: UTF8.self)), false)
    }
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
        let root = FileManager.default.temporaryDirectory.appending(path: "scratch-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    /// A one-note MIDI file with the given metadata, created at `created` seconds after 1970.
    private func midiFile(_ name: String, in folder: URL, _ provenance: MIDIProvenance?, created: TimeInterval) throws {
        var options = MIDIExportOptions()
        options.provenance = provenance
        let note = NoteEvent(onset: 0, offset: 1, pitch: 60, program: 0, isDrum: false, instrument: "piano", velocity: 90, pitchBends: nil)
        let url = folder.appending(path: name)
        try MIDIBuilder.build(notes: [note], options: options).write(to: url)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: created)], ofItemAtPath: url.path)
    }

    private func song(_ model: String, version: Int?) -> MIDIProvenance {
        MIDIProvenance(source: "file:///Audio/song.wav", sourceName: version == nil ? nil : "song", modelID: model, version: version)
    }

    @Test func transcriptionsOfOneAudioFileAreGroupedInCreationOrder() throws {
        let folders = try makeFolders()
        try midiFile("song - basic-pitch.mid", in: folders.midi, song("basic-pitch", version: 1), created: 100)
        try midiFile("song - muscriptor-large.mid", in: folders.midi, song("muscriptor-large", version: 3), created: 50)
        try midiFile("song - basic-pitch 2.mid", in: folders.midi, song("basic-pitch", version: 2), created: 200)
        try midiFile("Other.mid", in: folders.midi, nil, created: 10)
        try touch(folders.midi.appending(path: "Broken.mid"))
        let library = library(imports())
        library.attach(audio: folders.audio, midi: folders.midi)

        #expect(library.midi.count == 5)
        #expect(library.midiGroups.map(\.title) == ["Broken", "Other", "song"])
        #expect(library.midiGroups.prefix(2).allSatisfy { $0.versions.count == 1 })
        let group = try #require(library.midiGroups.last)
        #expect(group.versions.map(\.entry.fileName) == ["song - muscriptor-large.mid", "song - basic-pitch.mid", "song - basic-pitch 2.mid"])
        #expect(group.versions.map(\.number) == [3, 1, 2])
        #expect(group.versions.allSatisfy { $0.customName == nil })
    }

    @Test func aSingleTranscriptionIsOneRowTitledWithItsAudio() throws {
        let folders = try makeFolders()
        try midiFile("take - piano-onnx.mid", in: folders.midi,
                     MIDIProvenance(source: "file:///Audio/take.wav", sourceName: "take", modelID: "piano-onnx", version: 1), created: 100)
        let library = library(imports())
        library.attach(audio: folders.audio, midi: folders.midi)

        let group = try #require(library.midiGroups.first)
        #expect(library.midiGroups.count == 1 && group.title == "take")
        #expect(group.versions.count == 1 && group.versions[0].customName == nil)
    }

    @Test func aRenamedVersionKeepsItsOwnName() throws {
        let folders = try makeFolders()
        try midiFile("song - basic-pitch.mid", in: folders.midi, song("basic-pitch", version: 1), created: 100)
        try midiFile("Best take.mid", in: folders.midi, song("basic-pitch", version: 2), created: 200)
        let library = library(imports())
        library.attach(audio: folders.audio, midi: folders.midi)

        let group = try #require(library.midiGroups.first)
        #expect(group.versions.map(\.customName) == [nil, "Best take"])
        #expect(group.versions.map(\.number) == [1, 2])
    }

    @Test func filesFromBeforeVersionsAreNumberedByCreationAmongThemselves() throws {
        let folders = try makeFolders()
        try midiFile("song.mid", in: folders.midi, song("basic-pitch", version: nil), created: 300)
        try midiFile("song 2.mid", in: folders.midi, song("muscriptor-small", version: nil), created: 100)
        try midiFile("song - basic-pitch.mid", in: folders.midi, song("basic-pitch", version: 3), created: 400)
        let library = library(imports())
        library.attach(audio: folders.audio, midi: folders.midi)

        let group = try #require(library.midiGroups.first)
        #expect(library.midiGroups.count == 1 && group.title == "song")
        #expect(group.versions.map(\.entry.fileName) == ["song 2.mid", "song.mid", "song - basic-pitch.mid"])
        #expect(group.versions.map(\.number) == [1, 2, 3])
        #expect(group.versions.allSatisfy { $0.customName == nil })
    }

    @Test func aGroupIsTitledFromItsReferenceWhenTheFileDoesNotNameItsAudio() throws {
        let folders = try makeFolders()
        let elsewhere = FileManager.default.temporaryDirectory.appending(path: "scratch-live-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let source = elsewhere.appending(path: "Live at home.wav")
        try touch(source)
        let imports = imports()
        _ = try imports.importAudio(from: source, mode: .reference, audioFolder: folders.audio)
        let id = try #require(imports.references.first?.id)
        try midiFile("Live at home.mid", in: folders.midi, MIDIProvenance(source: "reference:\(id.uuidString)", modelID: "basic-pitch"), created: 100)
        // Its reference was removed, so only the file's own name is left.
        try midiFile("Lost take.mid", in: folders.midi, MIDIProvenance(source: "reference:\(UUID().uuidString)", modelID: "basic-pitch"), created: 100)
        let library = library(imports)
        library.attach(audio: folders.audio, midi: folders.midi)

        #expect(library.midiGroups.map(\.title) == ["Live at home", "Lost take"])
        #expect(library.midiGroups.allSatisfy { $0.versions.count == 1 && $0.versions[0].customName == nil })
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
        let source = FileManager.default.temporaryDirectory.appending(path: "scratch-src-\(UUID().uuidString)", directoryHint: .isDirectory)
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
        let source = FileManager.default.temporaryDirectory.appending(path: "scratch-ref-\(UUID().uuidString).wav")
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

    @Test func aPickedFileIsAccessedWhileItsBookmarkIsMade() throws {
        let folders = try makeFolders()
        let source = FileManager.default.temporaryDirectory.appending(path: "scratch-picked-\(UUID().uuidString).wav")
        try touch(source)
        let sandbox = SandboxAccess()
        let imports = AudioImportStore(storage: MemoryStore(), codec: sandbox, access: sandbox)
        let target = try imports.importAudio(from: source, mode: .reference, audioFolder: folders.audio)
        #expect(target.path == source.path)
        #expect(imports.references.count == 1)
        // The panel's access ends; the reference's own lease keeps the file readable.
        #expect(sandbox.active.map(\.path) == [source.path])

        let replacement = FileManager.default.temporaryDirectory.appending(path: "scratch-picked-\(UUID().uuidString).wav")
        try touch(replacement)
        try imports.relink(imports.references[0], to: replacement)
        #expect(imports.references[0].lastPath == replacement.path)
    }

    @Test func missingReferenceIsFlaggedAndRelinkRestoresIt() throws {
        let folders = try makeFolders()
        let keep = folders.audio.appending(path: "keep.wav")
        try touch(keep)
        let gone = FileManager.default.temporaryDirectory.appending(path: "scratch-gone-\(UUID().uuidString).wav")
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

        let replacement = FileManager.default.temporaryDirectory.appending(path: "scratch-new-\(UUID().uuidString).wav")
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
        let missing = FileManager.default.temporaryDirectory.appending(path: "scratch-nothing-\(UUID().uuidString).wav")
        #expect(throws: AudioImportError.self) { try imports.importAudio(from: missing, mode: .copy, audioFolder: folders.audio) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folders.audio.path).isEmpty)

        let real = FileManager.default.temporaryDirectory.appending(path: "scratch-real-\(UUID().uuidString).wav")
        try touch(real)
        codec.failsToMake = true
        #expect(throws: AudioImportError.self) { try imports.importAudio(from: real, mode: .reference, audioFolder: folders.audio) }
        #expect(imports.references.isEmpty)
        #expect(storage.values[AudioImportStore.referencesKey].flatMap { try? JSONDecoder().decode([AudioReference].self, from: $0) }?.isEmpty ?? true)
        #expect(throws: AudioImportError.noWorkingFolder) { try imports.importAudio(from: real, mode: .copy, audioFolder: nil) }
    }
}
