import Foundation
import SwiftMIDICore
import SwiftMIDIFile

/// What a MIDI file written by the app remembers about itself, carried in one `smt:` text event on the conductor track.
/// Other software ignores the event; the app reads it back to tell a transcription from an imported file.
struct MIDIProvenance: Equatable, Hashable, Sendable {
    static let prefix = "smt:"
    static let formatVersion = 1
    /// A source in the working folder's Audio folder, named by its file name there.
    static let audioPrefix = "audio:"
    /// A source the app keeps a bookmark to, named by the bookmark's id.
    static let referencePrefix = "reference:"

    /// The source audio, as `audio:{file name}` or `reference:{bookmark id}`. Never a path.
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
            case "source": source = Self.unescape(value).map(Self.withoutPath)
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

    /// Files saved before sources were named by file name hold the audio's full file URL, which names the user's folders
    /// and account. Read back, that URL becomes the `audio:` source it stands for.
    static func withoutPath(_ source: String) -> String {
        guard source.hasPrefix("file:") else { return source }
        let name = URL(string: source)?.lastPathComponent
            ?? source.split(separator: "/").last.map { String($0).removingPercentEncoding ?? String($0) } ?? ""
        return audioPrefix + name
    }

    /// `text` with a `source` field that holds a file URL rewritten as its `audio:` source, every other field as it was,
    /// or nil when the text isn't `smt:` or names no path.
    static func textWithoutPath(_ text: String) -> String? {
        guard text.hasPrefix(prefix) else { return nil }
        var changed = false
        let fields = text.dropFirst(prefix.count).split(separator: ";", omittingEmptySubsequences: false).map { field -> String in
            let key = "source="
            guard field.hasPrefix(key), let value = unescape(String(field.dropFirst(key.count))), value.hasPrefix("file:") else {
                return String(field)
            }
            changed = true
            return key + escape(withoutPath(value))
        }
        return changed ? prefix + fields.joined(separator: ";") : nil
    }

    /// `data` with every `smt:` text event that names its source by path rewritten without the path, or nil when the file
    /// has none or isn't a MIDI file the walk understands. Every other byte stays as it was.
    static func removingPaths(from data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count >= 14, Array(bytes[0..<4]) == Array("MThd".utf8) else { return nil }
        var output = Array(bytes[0..<8])
        var position = 8
        var changed = false
        let headerLength = Int(readUInt32(bytes, at: 4))
        guard position + headerLength <= bytes.count else { return nil }
        output += bytes[position..<(position + headerLength)]
        position += headerLength

        while position + 8 <= bytes.count {
            let id = Array(bytes[position..<(position + 4)])
            let length = Int(readUInt32(bytes, at: position + 4))
            let start = position + 8
            guard start + length <= bytes.count else { return nil }
            var chunk = Array(bytes[start..<(start + length)])
            if id == Array("MTrk".utf8) {
                guard let rewritten = rewriteTrack(chunk) else { return nil }
                if rewritten != chunk { changed = true; chunk = rewritten }
            }
            output += id
            output += withUnsafeBytes(of: UInt32(chunk.count).bigEndian, Array.init)
            output += chunk
            position = start + length
        }
        guard position == bytes.count else { return nil }
        return changed ? Data(output) : nil
    }

    /// One track's events with path-carrying `smt:` texts rewritten, or nil when an event can't be walked.
    private static func rewriteTrack(_ track: [UInt8]) -> [UInt8]? {
        var output: [UInt8] = []
        var i = 0
        var running: UInt8?
        while i < track.count {
            guard let delta = readVariable(track, at: i) else { return nil }
            output += track[i..<delta.end]
            i = delta.end
            guard i < track.count else { return nil }
            let status = track[i]
            if status == 0xFF {
                guard i + 1 < track.count, let length = readVariable(track, at: i + 2) else { return nil }
                let end = length.end + length.value
                guard end <= track.count else { return nil }
                let payload = Array(track[length.end..<end])
                if track[i + 1] == 0x01, let text = String(bytes: payload, encoding: .ascii), let cleaned = textWithoutPath(text) {
                    let replacement = Array(cleaned.utf8)
                    output += [0xFF, 0x01] + writeVariable(replacement.count) + replacement
                } else {
                    output += track[i..<end]
                }
                i = end
            } else if status == 0xF0 || status == 0xF7 {
                guard let length = readVariable(track, at: i + 1) else { return nil }
                let end = length.end + length.value
                guard end <= track.count else { return nil }
                output += track[i..<end]
                i = end
            } else {
                var at = i
                if status & 0x80 != 0 { running = status; at += 1 }
                guard let current = running else { return nil }
                let end = at + ((current & 0xF0) == 0xC0 || (current & 0xF0) == 0xD0 ? 1 : 2)
                guard end <= track.count else { return nil }
                output += track[i..<end]
                i = end
            }
        }
        return output
    }

    private static func readUInt32(_ bytes: [UInt8], at index: Int) -> UInt32 {
        bytes[index..<(index + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func readVariable(_ bytes: [UInt8], at index: Int) -> (value: Int, end: Int)? {
        var value = 0
        var i = index
        while i < bytes.count, i < index + 4 {
            value = value << 7 | Int(bytes[i] & 0x7F)
            if bytes[i] & 0x80 == 0 { return (value, i + 1) }
            i += 1
        }
        return nil
    }

    private static func writeVariable(_ value: Int) -> [UInt8] {
        var bytes = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 {
            bytes.insert(UInt8(rest & 0x7F) | 0x80, at: 0)
            rest >>= 7
        }
        return bytes
    }

    private static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func unescape(_ value: String) -> String? {
        let decoded = value.removingPercentEncoding
        return decoded?.isEmpty == true ? nil : decoded
    }
}
