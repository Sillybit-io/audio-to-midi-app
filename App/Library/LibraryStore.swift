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
    /// What a MIDI file holds, or nil for audio and for a MIDI file that can't be read.
    var midiInfo: MIDIFileInfo?
    var created: Date?
    var modified: Date?

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var fileName: String { url.lastPathComponent }
}

/// One transcription in a group of the sidebar's MIDI section.
struct MIDIVersion: Identifiable, Hashable {
    let entry: LibraryEntry
    /// The version written in the file. A file saved before versions existed gets its place among the group's
    /// other such files, in creation order.
    let number: Int
    /// The file's own name when the user renamed it, shown instead of "Version {number}".
    let customName: String?

    var id: URL { entry.url }
}

/// A row of the sidebar's MIDI section: every transcription of one audio file, oldest first, or one file that isn't a
/// transcription (or can't be read).
struct MIDIGroup: Identifiable, Hashable {
    /// The source audio's identifier, or the file's URL for a file on its own.
    let id: String
    /// The audio's name, or the file's own name for a file on its own.
    let title: String
    let versions: [MIDIVersion]
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
    /// The same MIDI files as `midi`, grouped for the sidebar.
    private(set) var midiGroups: [MIDIGroup] = []

    @ObservationIgnored private let imports: AudioImportStore
    @ObservationIgnored private let watcher: any FolderWatcher
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private var audioFolder: URL?
    @ObservationIgnored private var midiFolder: URL?
    @ObservationIgnored private var watches: [any FolderWatching] = []
    @ObservationIgnored private var infoCache: [URL: (stamp: Date, size: Int, info: MIDIFileInfo?)] = [:]
    /// The last summary written to the debug log; a refresh that changes nothing isn't logged again.
    @ObservationIgnored private var loggedSummary = ""

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
        midi = scan(midiFolder, kind: .midi) { ["mid", "midi"].contains($0.pathExtension.lowercased()) }.map { entry in
            var entry = entry
            entry.midiInfo = midiInfo(for: entry.url)
            return entry
        }
        infoCache = infoCache.filter { cached in midi.contains { $0.url == cached.key } }
        midiGroups = Self.groups(of: midi, audioName: audioName(for:))
        let summary = "Library: \(audio.count) audio (\(audio.filter(\.isMissing).count) missing), \(midi.count) MIDI."
        if summary != loggedSummary {
            loggedSummary = summary
            debugLog(.library, summary)
        }
    }

    private func midiInfo(for url: URL) -> MIDIFileInfo? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = values?.contentModificationDate ?? .distantPast
        let size = values?.fileSize ?? -1
        if let cached = infoCache[url], cached.stamp == stamp, cached.size == size { return cached.info }
        let info = MIDIImporter.info(at: url)
        infoCache[url] = (stamp, size, info)
        return info
    }

    /// The name of the audio a transcription came from: the one it remembers, else its source's current name.
    private func audioName(for provenance: MIDIProvenance) -> String? {
        if let name = provenance.sourceName { return name }
        guard let source = provenance.source else { return nil }
        if source.hasPrefix("reference:") {
            let id = UUID(uuidString: String(source.dropFirst("reference:".count)))
            return imports.references.first { $0.id == id }.map { ($0.name as NSString).deletingPathExtension }
        }
        return URL(string: source).map { $0.deletingPathExtension().lastPathComponent }
    }

    /// Puts the transcriptions of each audio file together, oldest first, and leaves every other file on its own.
    /// Rows are in title order.
    static func groups(of entries: [LibraryEntry], audioName: (MIDIProvenance) -> String?) -> [MIDIGroup] {
        var bySource: [String: [LibraryEntry]] = [:]
        var groups: [MIDIGroup] = []
        for entry in entries {
            if let source = entry.midiInfo?.provenance?.source {
                bySource[source, default: []].append(entry)
            } else {
                groups.append(MIDIGroup(id: entry.url.absoluteString, title: entry.name,
                                        versions: [MIDIVersion(entry: entry, number: 1, customName: nil)]))
            }
        }
        for (source, files) in bySource {
            let ordered = files.sorted(by: createdFirst)
            let title = ordered.compactMap { $0.midiInfo?.provenance.flatMap(audioName) }.first ?? ordered[0].name
            var unnumbered = 0
            let versions = ordered.map { entry -> MIDIVersion in
                let provenance = entry.midiInfo?.provenance
                let number: Int
                if let version = provenance?.version {
                    number = version
                } else {
                    unnumbered += 1
                    number = unnumbered
                }
                let ownTitle = provenance.flatMap(audioName) ?? title
                let renamed = !TranscriptionWriter.isDefaultName(entry.name, title: ownTitle, modelID: provenance?.modelID)
                return MIDIVersion(entry: entry, number: number, customName: renamed ? entry.name : nil)
            }
            groups.append(MIDIGroup(id: source, title: title, versions: versions))
        }
        return groups.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id < $1.id
            }
        }
    }

    /// Creation date, then modification date, then name, so the order holds when the file system can't say.
    private static func createdFirst(_ a: LibraryEntry, _ b: LibraryEntry) -> Bool {
        let first = (a.created ?? .distantPast, a.modified ?? .distantPast)
        let second = (b.created ?? .distantPast, b.modified ?? .distantPast)
        if first != second { return first < second }
        return a.fileName.localizedStandardCompare(b.fileName) == .orderedAscending
    }

    private func scan(_ folder: URL?, kind: LibraryEntry.Kind, matching: (URL) -> Bool) -> [LibraryEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        guard let folder,
              let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        else { return [] }
        return urls
            .compactMap { url -> LibraryEntry? in
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isDirectory != true, matching(url) else { return nil }
                return LibraryEntry(url: url, kind: kind, created: values?.creationDate, modified: values?.contentModificationDate)
            }
            .sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
    }

    static func isAudio(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension.lowercased())?.conforms(to: .audio) ?? false
    }
}
