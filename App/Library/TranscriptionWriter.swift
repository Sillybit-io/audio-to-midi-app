import Foundation
import Observation

enum TranscriptionWriterError: LocalizedError, Equatable {
    case noFolder
    case cannotWrite(file: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .noFolder: "Choose a working folder first."
        case .cannotWrite(let file, let reason): "Couldn\u{2019}t save \u{201C}\(file)\u{201D} in the MIDI folder. \(reason)"
        }
    }
}

/// Saves a finished or cancelled transcription as a new version of its audio, in `MIDI/{audio name} - {model ID}.mid`.
/// The file remembers its source, model and version. A finished result is never replaced; only a cancelled run's partial
/// file is, by a later run of the same audio and model. A file the user has edited is never touched.
@MainActor @Observable
final class TranscriptionWriter {
    /// What the writer needs to know about a run, taken when the run starts.
    struct Run: Sendable {
        var source: URL
        var sourceID: String
        var title: String
        var modelID: String?
        var notice: String?
        var slice: AudioSlice
    }

    enum Status: Equatable {
        case idle
        case saved(URL, version: Int, partial: Bool)
        /// A cancelled run left an earlier complete result alone. Its version is nil when it was saved before versions existed.
        case keptPrevious(URL, version: Int?)
        case empty
        case failed(String)
    }

    enum Outcome: Equatable {
        case saved(URL, version: Int)
        case kept(URL, version: Int?)
    }

    private(set) var status: Status = .idle
    @ObservationIgnored private var pending: (notes: [NoteEvent], run: Run, partial: Bool)?
    @ObservationIgnored private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Identifies the audio a file came from: its URL, or the id of the bookmarked reference that points at it.
    nonisolated static func sourceIdentifier(for url: URL, references: [AudioReference]) -> String {
        if let reference = references.first(where: { $0.lastPath == url.path }) { return "reference:\(reference.id.uuidString)" }
        return url.standardizedFileURL.absoluteString
    }

    /// Call once when a run reaches a terminal state. Streaming and failed runs write nothing.
    func finish(_ state: TranscriptionSession.State, notes: [NoteEvent], run: Run, folder: URL?) {
        switch state {
        case .done: save(notes, run: run, partial: false, folder: folder)
        case .cancelled: save(notes, run: run, partial: true, folder: folder)
        case .idle, .loading, .running, .refining, .failed: break
        }
    }

    /// Tries the last save again, for example after the folder was made writable.
    func retry(folder: URL?) {
        guard let pending else { return }
        save(pending.notes, run: pending.run, partial: pending.partial, folder: folder)
    }

    func reset() {
        status = .idle
        pending = nil
    }

    private func save(_ notes: [NoteEvent], run: Run, partial: Bool, folder: URL?) {
        guard !notes.isEmpty else {
            status = .empty
            pending = nil
            return
        }
        pending = (notes, run, partial)
        guard let folder else {
            status = .failed(TranscriptionWriterError.noFolder.localizedDescription)
            return
        }
        do {
            switch try Self.write(notes, run: run, partial: partial, in: folder, fileManager: fileManager) {
            case .saved(let url, let version): status = .saved(url, version: version, partial: partial)
            case .kept(let url, let version): status = .keptPrevious(url, version: version)
            }
            pending = nil
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// The MIDI files in `folder` whose own metadata says they were made from `sourceID`, in name order.
    nonisolated static func linkedOutputs(sourceID: String, in folder: URL, fileManager: FileManager = .default) -> [(url: URL, provenance: MIDIProvenance)] {
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { ["mid", "midi"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let provenance = MIDIImporter.info(at: url)?.provenance, provenance.source == sourceID else { return nil }
                return (url, provenance)
            }
    }

    /// `{audio name} - {model ID}`. The ID keeps the name plain and stable; the app shows the model's own name instead.
    nonisolated static func baseName(title: String, modelID: String?) -> String {
        modelID.map { "\(title) - \($0)" } ?? title
    }

    /// Whether `name` is one the writer gives, `{base}` or `{base} 2` and on, either today's or the plain
    /// `{audio name}` used before versions. Anything else was renamed by the user.
    nonisolated static func isDefaultName(_ name: String, title: String, modelID: String?) -> Bool {
        let bases = Set([baseName(title: title, modelID: modelID), title])
        return bases.contains { base in
            if name == base { return true }
            guard name.hasPrefix("\(base) "), let number = Int(name.dropFirst(base.count + 1)) else { return false }
            return number >= 2
        }
    }

    /// One more than any version of the source so far. Files from before versions count too, so the numbers the library
    /// gives them stay free.
    nonisolated static func nextVersion(after linked: [(url: URL, provenance: MIDIProvenance)]) -> Int {
        max(linked.compactMap(\.provenance.version).max() ?? 0, linked.count) + 1
    }

    /// Writes the notes as a new version of the source, or over the unfinished partial file of the same model, which keeps
    /// its version. A cancelled run leaves a finished result of the same model in place and writes nothing.
    /// A finished result, a file with hand edits, and one that isn't recognisably this source's are never touched.
    nonisolated static func write(_ notes: [NoteEvent], run: Run, partial: Bool, in folder: URL, fileManager: FileManager = .default) throws -> Outcome {
        let linked = linkedOutputs(sourceID: run.sourceID, in: folder, fileManager: fileManager)
        let sameModel = linked.filter { $0.provenance.modelID == run.modelID && !$0.provenance.edited }
        if partial, let complete = sameModel.first(where: { !$0.provenance.partial }) {
            return .kept(complete.url, version: complete.provenance.version)
        }
        let unfinished = sameModel.first { $0.provenance.partial }
        let destination = unfinished?.url
            ?? LibraryNaming.uniqueURL(base: baseName(title: run.title, modelID: run.modelID), ext: "mid", in: folder, fileManager: fileManager)
        let version = unfinished?.provenance.version ?? nextVersion(after: linked)
        let name = destination.lastPathComponent

        var options = MIDIExportOptions()
        options.title = run.title
        options.sliceStart = run.slice.start
        options.sliceLength = run.slice.span
        options.relativeTimeline = run.slice.relativeTimeline
        options.copyright = run.notice
        options.provenance = MIDIProvenance(source: run.sourceID, sourceName: run.title, modelID: run.modelID, version: version,
                                            edited: false, partial: partial)

        let staging = folder.appending(path: ".save-\(UUID().uuidString).tmp", directoryHint: .notDirectory)
        do {
            let data = try MIDIBuilder.build(notes: notes, options: options)
            try data.write(to: staging)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw TranscriptionWriterError.cannotWrite(file: name, reason: reason(for: error))
        }
        return .saved(destination, version: version)
    }

    nonisolated static func reason(for error: Error) -> String {
        switch (error as? CocoaError)?.code {
        case .fileWriteNoPermission, .fileWriteVolumeReadOnly: "The folder isn\u{2019}t writable."
        case .fileWriteOutOfSpace: "The disk is full."
        default: "The file couldn\u{2019}t be written."
        }
    }
}
