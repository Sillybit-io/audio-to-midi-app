import Foundation
import SwiftMIDICore
import SwiftMIDIFile

/// What a MIDI file written by the app remembers about itself, carried in one `smt:` text event on the conductor track.
/// Other software ignores the event; the app reads it back to tell a transcription from an imported file.
struct MIDIProvenance: Equatable, Hashable, Sendable {
    static let prefix = "smt:"
    static let formatVersion = 1

    /// The source audio's URL or bookmark identifier.
    var source: String?
    /// The source audio's name without its extension, so the library can title the file's group when the source can't be found.
    var sourceName: String?
    var modelID: String?
    /// Which transcription of the source this is, counting from 1. Nil in files saved before versions existed.
    var version: Int?
    /// The file has hand edits that a later transcription must not overwrite.
    var edited = false
    /// The transcription was cancelled before it finished.
    var partial = false

    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// ASCII only, with `;`, `=` and `%` in values percent-encoded, so `MIDIBuilder.ascii` never alters it.
    var text: String {
        var fields = ["v=\(Self.formatVersion)"]
        if let source { fields.append("source=\(Self.escape(source))") }
        if let sourceName { fields.append("name=\(Self.escape(sourceName))") }
        if let modelID { fields.append("model=\(Self.escape(modelID))") }
        if let version { fields.append("version=\(version)") }
        fields.append("edited=\(edited ? 1 : 0)")
        fields.append("partial=\(partial ? 1 : 0)")
        return Self.prefix + fields.joined(separator: ";")
    }

    init(source: String? = nil, sourceName: String? = nil, modelID: String? = nil, version: Int? = nil, edited: Bool = false, partial: Bool = false) {
        self.source = source
        self.sourceName = sourceName
        self.modelID = modelID
        self.version = version
        self.edited = edited
        self.partial = partial
    }

    /// Nil unless `text` starts with `smt:`. Unknown fields are ignored so a newer file still reads.
    init?(text: String) {
        guard text.hasPrefix(Self.prefix) else { return nil }
        self.init()
        for field in text.dropFirst(Self.prefix.count).split(separator: ";") {
            guard let equals = field.firstIndex(of: "=") else { continue }
            let value = String(field[field.index(after: equals)...])
            switch field[..<equals] {
            case "source": source = Self.unescape(value)
            case "name": sourceName = Self.unescape(value)
            case "model": modelID = Self.unescape(value)
            case "version": version = Int(value).flatMap { $0 > 0 ? $0 : nil }
            case "edited": edited = value == "1"
            case "partial": partial = value == "1"
            default: break
            }
        }
    }

    /// The first `smt:` text event on any track of a decoded file.
    static func read(from file: MusicalMIDI1File) -> MIDIProvenance? {
        for track in file.tracks {
            for event in track.events {
                guard case .text(let text) = event.event, text.textType == .text,
                      let provenance = MIDIProvenance(text: text.text) else { continue }
                return provenance
            }
        }
        return nil
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func unescape(_ value: String) -> String? {
        let decoded = value.removingPercentEncoding
        return decoded?.isEmpty == true ? nil : decoded
    }
}
