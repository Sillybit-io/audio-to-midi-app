import AppKit
import Foundation
import Observation

@MainActor
protocol FolderPanel {
    func chooseFolder(suggested: URL) -> URL?
}

struct SystemFolderPanel: FolderPanel {
    func chooseFolder(suggested: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggested.deletingLastPathComponent()
        panel.message = "Choose or create the folder where Silly MIDI Tools keeps your audio and MIDI files."
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum WorkingFolderError: LocalizedError, Equatable {
    case cannotPrepare(folder: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .cannotPrepare(let folder, let reason):
            "Silly MIDI Tools can't use \u{201C}\(folder)\u{201D}: \(reason)"
        }
    }
}

@MainActor @Observable
final class WorkingFolderStore {
    static let bookmarkKey = "workingFolder.bookmark"
    static let audioName = "Audio"
    static let midiName = "MIDI"
    static let defaultFolderName = "Silly MIDI Tools"

    private(set) var folder: URL?
    var errorMessage: String?

    var isResolved: Bool { folder != nil }
    var audioFolder: URL? { folder?.appending(path: Self.audioName, directoryHint: .isDirectory) }
    var midiFolder: URL? { folder?.appending(path: Self.midiName, directoryHint: .isDirectory) }

    /// The real `~/Documents/Silly MIDI Tools`; the sandbox home is the container, so ask the account database.
    static var suggestedFolder: URL {
        let home = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir), isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: "Documents", directoryHint: .isDirectory)
            .appending(path: defaultFolderName, directoryHint: .isDirectory)
    }

    @ObservationIgnored private let storage: any BookmarkStorage
    @ObservationIgnored private let codec: any BookmarkCodec
    @ObservationIgnored private let access: any ScopedAccess
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private var leased: URL?

    init(storage: any BookmarkStorage = UserDefaultsBookmarkStorage(),
         codec: any BookmarkCodec = SystemBookmarkCodec(),
         access: any ScopedAccess = SystemScopedAccess(),
         fileManager: FileManager = .default) {
        self.storage = storage
        self.codec = codec
        self.access = access
        self.fileManager = fileManager
    }

    /// Resolves the stored bookmark. Leaves the store unresolved (so Welcome shows) when there is none or it no longer works.
    func resolveAtLaunch() {
        guard let data = storage.data(for: Self.bookmarkKey) else { return }
        do {
            let (url, isStale) = try codec.resolve(data)
            let started = access.start(url)
            do {
                try prepare(url)
            } catch {
                if started { access.stop(url) }
                throw error
            }
            if isStale, let fresh = try? codec.makeBookmark(for: url) {
                storage.set(fresh, for: Self.bookmarkKey)
            }
            swapLease(to: started ? url : nil)
            folder = url
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates `Audio/` and `MIDI/`, then stores the grant. Nothing is stored and the previous folder stays when this throws.
    func adopt(_ url: URL) throws {
        try prepare(url)
        let bookmark = try codec.makeBookmark(for: url)
        storage.set(bookmark, for: Self.bookmarkKey)
        swapLease(to: access.start(url) ? url : nil)
        folder = url
        errorMessage = nil
    }

    /// Runs the folder panel. Cancelling or a folder that can't be prepared keeps the current folder. Returns whether a folder was adopted.
    @discardableResult
    func choose(using panel: any FolderPanel) -> Bool {
        guard let url = panel.chooseFolder(suggested: Self.suggestedFolder) else { return false }
        do {
            try adopt(url)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Forgets the grant; the next launch or the Welcome sheet asks for a new one.
    func reset() {
        swapLease(to: nil)
        storage.set(nil, for: Self.bookmarkKey)
        folder = nil
    }

    private func prepare(_ url: URL) throws {
        for name in [Self.audioName, Self.midiName] {
            let sub = url.appending(path: name, directoryHint: .isDirectory)
            do {
                try fileManager.createDirectory(at: sub, withIntermediateDirectories: true)
            } catch {
                throw WorkingFolderError.cannotPrepare(folder: url.lastPathComponent, reason: "the \(name) folder can't be created.")
            }
            guard fileManager.isWritableFile(atPath: sub.path) else {
                throw WorkingFolderError.cannotPrepare(folder: url.lastPathComponent, reason: "the \(name) folder isn't writable.")
            }
        }
    }

    private func swapLease(to url: URL?) {
        if let leased { access.stop(leased) }
        leased = url
    }
}
