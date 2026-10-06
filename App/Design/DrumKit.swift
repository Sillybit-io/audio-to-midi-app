import SwiftUI

/// The six kit pieces a drum hit is drawn as: one colour each, so a drum track reads as a kit rather than one brown block.
enum DrumPiece: CaseIterable, Sendable {
    case kick, snare, toms, hiHat, cymbals, percussion

    var title: String {
        switch self {
        case .kick: "Kick"
        case .snare: "Snare"
        case .toms: "Toms"
        case .hiHat: "Hi-hat"
        case .cymbals: "Cymbals"
        case .percussion: "Percussion"
        }
    }

    var colour: Color {
        switch self {
        case .kick: Token.drumKick
        case .snare: Token.drumSnare
        case .toms: Token.drumToms
        case .hiHat: Token.drumHiHat
        case .cymbals: Token.drumCymbals
        case .percussion: Token.drumPercussion
        }
    }
}

/// General MIDI drum map (channel 10): which kit piece a pitch is, and what the roll calls its lane.
enum DrumKit {
    static func piece(forPitch pitch: Int) -> DrumPiece {
        switch pitch {
        case 35, 36: .kick
        case 37, 38, 39, 40: .snare
        case 41, 43, 45, 47, 48, 50: .toms
        case 42, 44, 46: .hiHat
        case 49, 51, 52, 53, 55, 57, 59: .cymbals
        default: .percussion
        }
    }

    private static let names: [Int: (full: String, short: String)] = [
        35: ("Kick 2", "Kick"), 36: ("Kick", "Kick"), 37: ("Side stick", "Stick"), 38: ("Snare", "Snare"),
        39: ("Clap", "Clap"), 40: ("Electric snare", "Snare 2"), 41: ("Low floor tom", "Floor lo"), 42: ("Closed hi-hat", "Hat"),
        43: ("High floor tom", "Floor hi"), 44: ("Pedal hi-hat", "Pedal hat"), 45: ("Low tom", "Low tom"), 46: ("Open hi-hat", "Open hat"),
        47: ("Low-mid tom", "Lo-mid"), 48: ("High-mid tom", "Hi-mid"), 49: ("Crash", "Crash"), 50: ("High tom", "High tom"),
        51: ("Ride", "Ride"), 52: ("China", "China"), 53: ("Ride bell", "Bell"), 54: ("Tambourine", "Tamb"),
        55: ("Splash", "Splash"), 56: ("Cowbell", "Cowbell"), 57: ("Crash 2", "Crash 2"), 58: ("Vibraslap", "Vibra"),
        59: ("Ride 2", "Ride 2"), 64: ("Low conga", "Conga"), 70: ("Maracas", "Maracas"), 75: ("Claves", "Claves"),
    ]

    /// The General MIDI name, for tooltips and descriptions.
    static func name(forPitch pitch: Int) -> String { names[pitch]?.full ?? "Percussion \(pitch)" }

    /// A name short enough for the key column of the roll.
    static func laneLabel(forPitch pitch: Int) -> String { names[pitch]?.short ?? "Perc \(pitch)" }

    /// The lanes to label: every pitch a drum hit sits on, with its short name and its piece's colour.
    static func lanes(pitches: some Sequence<Int>) -> [Int: (label: String, colour: Color)] {
        var lanes: [Int: (label: String, colour: Color)] = [:]
        for pitch in pitches where lanes[pitch] == nil {
            lanes[pitch] = (laneLabel(forPitch: pitch), piece(forPitch: pitch).colour)
        }
        return lanes
    }

    /// Hits per kit piece, in kit order, leaving out the pieces with none.
    static func counts(pitches: some Sequence<Int>) -> [(piece: DrumPiece, count: Int)] {
        var tally: [DrumPiece: Int] = [:]
        for pitch in pitches { tally[piece(forPitch: pitch), default: 0] += 1 }
        return DrumPiece.allCases.compactMap { piece in tally[piece].map { (piece, $0) } }
    }
}
