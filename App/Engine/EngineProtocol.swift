import Foundation

struct EngineDevice: Codable, Equatable, Sendable {
    var index: Int
    var name: String
    var backend: String
    var integrated: Bool?
    var memoryTotal: Int?

    enum CodingKeys: String, CodingKey {
        case index, name, backend, integrated
        case memoryTotal = "memory_total"
    }
}

struct EngineInstrument: Codable, Equatable, Sendable {
    var name: String
    var program: Int
}

struct EngineNote: Codable, Equatable, Sendable {
    var onset: Double
    var offset: Double
    var pitch: Int
    var program: Int
    var isDrum: Bool
    var instrument: String

    enum CodingKeys: String, CodingKey {
        case onset, offset, pitch, program, instrument
        case isDrum = "is_drum"
    }
}

/// One line of the sidecar's newline-delimited JSON output.
enum EngineEvent: Equatable, Sendable {
    case devices(auto: Int, devices: [EngineDevice])
    case instruments([EngineInstrument])
    case load(progress: Double)
    case ready(device: EngineDevice, chunks: Int)
    case update(progress: Double, finalizedThrough: Double, notes: [EngineNote])
    case done(noteCount: Int)
    case error(code: String, message: String)

    static func decode(line: String) throws -> EngineEvent {
        try JSONDecoder().decode(EngineEvent.self, from: Data(line.utf8))
    }
}

extension EngineEvent: Decodable {
    private enum Keys: String, CodingKey {
        case type, auto, devices, instruments, progress, device, chunks
        case finalizedThrough = "finalized_through"
        case notes
        case noteCount = "note_count"
        case code, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "devices":
            self = .devices(auto: try c.decode(Int.self, forKey: .auto), devices: try c.decode([EngineDevice].self, forKey: .devices))
        case "instruments":
            self = .instruments(try c.decode([EngineInstrument].self, forKey: .instruments))
        case "load":
            self = .load(progress: try c.decode(Double.self, forKey: .progress))
        case "ready":
            self = .ready(device: try c.decode(EngineDevice.self, forKey: .device), chunks: try c.decode(Int.self, forKey: .chunks))
        case "update":
            self = .update(
                progress: try c.decode(Double.self, forKey: .progress),
                finalizedThrough: try c.decode(Double.self, forKey: .finalizedThrough),
                notes: try c.decode([EngineNote].self, forKey: .notes)
            )
        case "done":
            self = .done(noteCount: try c.decode(Int.self, forKey: .noteCount))
        case "error":
            self = .error(code: try c.decode(String.self, forKey: .code), message: try c.decode(String.self, forKey: .message))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown engine event \(other)")
        }
    }
}

/// A transcribed note as the app holds it, whichever engine produced it.
struct NoteEvent: Equatable, Sendable {
    var onset: Double
    var offset: Double
    var pitch: Int
    var program: Int
    var isDrum: Bool
    var instrument: String
    var velocity: Int?
    var pitchBends: [Int]?
}
