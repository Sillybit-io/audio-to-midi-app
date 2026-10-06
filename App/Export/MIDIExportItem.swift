import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct MIDIExportItem: Transferable, Sendable {
    var notes: [NoteEvent]
    var options: MIDIExportOptions
    var name: String

    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SillyMIDIToolsExport", isDirectory: true)

    static func clearTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    func writeTemporaryFile() throws -> URL {
        let folder = Self.directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name).appendingPathExtension("mid")
        try MIDIBuilder.build(notes: notes, options: options).write(to: url)
        debugLog(.export, "Wrote \"\(url.lastPathComponent)\" (\(notes.count) notes) for a drag or an export.")
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .midi) { item in
            SentTransferredFile(try item.writeTemporaryFile(), allowAccessingOriginalFile: false)
        }
        // Without a suggested name the save dialog's file wrapper gets a nil name, which throws in AppKit.
        .suggestedFileName { "\($0.name).mid" }
    }
}
