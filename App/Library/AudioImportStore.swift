import Foundation
import Observation

enum AddAudioMode: String, CaseIterable, Sendable {
    case copy
    case reference
}

struct AudioReference: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var lastPath: String
    var bookmark: Data
}

enum AudioImportError: LocalizedError, Equatable {
    case noWorkingFolder
    case copyFailed(String)
    case referenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .noWorkingFolder: "Choose a working folder first."
        case .copyFailed(let name): "Couldn\u{2019}t copy \u{201C}\(name)\u{201D} into the Audio folder."
        case .referenceFailed(let name): "Couldn\u{2019}t keep access to \u{201C}\(name)\u{201D}."
        }
    }
}

@MainActor @Observable
final class AudioImportStore {
    static let referencesKey = "audioReferences"

    private(set) var references: [AudioReference]

    @ObservationIgnored private let storage: any BookmarkStorage
    @ObservationIgnored private let codec: any BookmarkCodec
    @ObservationIgnored private let access: any ScopedAccess
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private var leases: [UUID: URL] = [:]

    init(storage: any BookmarkStorage = UserDefaultsBookmarkStorage(),
         codec: any BookmarkCodec = SystemBookmarkCodec(),
         access: any ScopedAccess = SystemScopedAccess(),
         fileManager: FileManager = .default) {
        self.storage = storage
        self.codec = codec
        self.access = access
        self.fileManager = fileManager
        references = storage.data(for: Self.referencesKey).flatMap { try? JSONDecoder().decode([AudioReference].self, from: $0) } ?? []
    }

    /// Copies `source` into the Audio folder, or keeps a bookmark to it where it is. Returns the URL to open.
    /// Nothing is recorded when the copy or the bookmark fails.
    func importAudio(from source: URL, mode: AddAudioMode, audioFolder: URL?) throws -> URL {
        switch mode {
        case .copy:
            guard let audioFolder else { throw AudioImportError.noWorkingFolder }
            if source.standardizedFileURL.deletingLastPathComponent() == audioFolder.standardizedFileURL { return source }
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let target = LibraryNaming.uniqueURL(base: source.deletingPathExtension().lastPathComponent,
                                                 ext: source.pathExtension, in: audioFolder, fileManager: fileManager)
            do {
                try fileManager.copyItem(at: source, to: target)
            } catch {
                throw AudioImportError.copyFailed(source.lastPathComponent)
            }
            return target
        case .reference:
            if let existing = references.first(where: { $0.lastPath == source.path }), let url = resolved(existing) { return url }
            let bookmark = try makeBookmark(for: source)
            let reference = AudioReference(name: source.lastPathComponent, lastPath: source.path, bookmark: bookmark)
            references.append(reference)
            persist()
            // Open it through the bookmark, which keeps access after the panel's grant ends.
            return resolved(reference) ?? source
        }
    }

    /// The reference's current file, or nil when it's gone or can't be reached (the library shows it as needing a relink).
    func resolved(_ reference: AudioReference) -> URL? {
        guard let (url, isStale) = try? codec.resolve(reference.bookmark) else { return nil }
        if leases[reference.id] == nil, access.start(url) { leases[reference.id] = url }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        if isStale, let fresh = try? codec.makeBookmark(for: url), let index = references.firstIndex(where: { $0.id == reference.id }) {
            references[index].bookmark = fresh
            references[index].lastPath = url.path
            persist()
        }
        return url
    }

    func relink(_ reference: AudioReference, to url: URL) throws {
        guard let index = references.firstIndex(where: { $0.id == reference.id }) else { return }
        let bookmark = try makeBookmark(for: url)
        if let lease = leases.removeValue(forKey: reference.id) { access.stop(lease) }
        references[index].bookmark = bookmark
        references[index].lastPath = url.path
        references[index].name = url.lastPathComponent
        persist()
    }

    func remove(_ reference: AudioReference) {
        if let lease = leases.removeValue(forKey: reference.id) { access.stop(lease) }
        references.removeAll { $0.id == reference.id }
        persist()
    }

    /// A security-scoped bookmark needs access to the file while it is made; a file picked in a panel only has that
    /// access between start and stop.
    private func makeBookmark(for url: URL) throws -> Data {
        let scoped = access.start(url)
        defer { if scoped { access.stop(url) } }
        do {
            return try codec.makeBookmark(for: url)
        } catch {
            throw AudioImportError.referenceFailed(url.lastPathComponent)
        }
    }

    private func persist() {
        storage.set(try? JSONEncoder().encode(references), for: Self.referencesKey)
    }
}
