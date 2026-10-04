import Foundation
import Observation
import UniformTypeIdentifiers

struct LibraryEntry: Identifiable, Hashable {
    enum Kind { case audio, midi }

    let url: URL
    let kind: Kind
    var isReference = false
    var isMissing = false
    var referenceID: UUID?

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var fileName: String { url.lastPathComponent }
}

enum LibraryNaming {
    /// `name.ext`, then `name 2.ext`, `name 3.ext` … the first that doesn't exist yet in `folder`.
    static func uniqueURL(base: String, ext: String, in folder: URL, fileManager: FileManager = .default) -> URL {
        var number = 1
        while true {
            let name = number == 1 ? "\(base).\(ext)" : "\(base) \(number).\(ext)"
            let candidate = folder.appending(path: name, directoryHint: .notDirectory)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            number += 1
        }
    }
}

@MainActor
protocol FolderWatching: AnyObject {
    func cancel()
}

@MainActor
protocol FolderWatcher {
    func watch(_ url: URL, onChange: @escaping @MainActor () -> Void) -> (any FolderWatching)?
}

@MainActor
final class DispatchFolderWatching: FolderWatching {
    private let source: any DispatchSourceFileSystemObject

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler { Task { @MainActor in onChange() } }
        source.setCancelHandler { close(descriptor) }
        source.activate()
    }

    func cancel() { source.cancel() }
}

struct DispatchFolderWatcher: FolderWatcher {
    func watch(_ url: URL, onChange: @escaping @MainActor () -> Void) -> (any FolderWatching)? {
        DispatchFolderWatching(url: url, onChange: onChange)
    }
}

@MainActor @Observable
final class LibraryStore {
    private(set) var audio: [LibraryEntry] = []
    private(set) var midi: [LibraryEntry] = []

    @ObservationIgnored private let imports: AudioImportStore
    @ObservationIgnored private let watcher: any FolderWatcher
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private var audioFolder: URL?
    @ObservationIgnored private var midiFolder: URL?
    @ObservationIgnored private var watches: [any FolderWatching] = []

    init(imports: AudioImportStore, watcher: any FolderWatcher = DispatchFolderWatcher(), fileManager: FileManager = .default) {
        self.imports = imports
        self.watcher = watcher
        self.fileManager = fileManager
    }

    /// Points the library at a working folder's two subfolders (or at nothing). Files already in the previous folders stay where they are.
    func attach(audio: URL?, midi: URL?) {
        watches.forEach { $0.cancel() }
        watches = []
        audioFolder = audio
        midiFolder = midi
        refresh()
        for folder in [audio, midi].compactMap({ $0 }) {
            if let watch = watcher.watch(folder, onChange: { [weak self] in self?.refresh() }) { watches.append(watch) }
        }
    }

    func refresh() {
        var audioEntries = scan(audioFolder, kind: .audio) { Self.isAudio($0) }
        for reference in imports.references {
            let resolved = imports.resolved(reference)
            let url = resolved ?? URL(fileURLWithPath: reference.lastPath)
            audioEntries.append(LibraryEntry(url: url, kind: .audio, isReference: true, isMissing: resolved == nil, referenceID: reference.id))
        }
        audio = audioEntries.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
        midi = scan(midiFolder, kind: .midi) { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
    }

    private func scan(_ folder: URL?, kind: LibraryEntry.Kind, matching: (URL) -> Bool) -> [LibraryEntry] {
        guard let folder,
              let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }
        return urls
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true && matching($0) }
            .map { LibraryEntry(url: $0, kind: kind) }
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    static func isAudio(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .audio) ?? false
    }
}
