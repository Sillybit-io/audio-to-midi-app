import Foundation
import Testing
@testable import SillyMIDITools

struct KeyDetectorTests {
    private func notes(_ pitches: [(Int, Double)]) -> [NoteEvent] {
        var t = 0.0
        return pitches.map { p, d in
            defer { t += d }
            return NoteEvent(onset: t, offset: t + d, pitch: p, program: 0, isDrum: false, instrument: "acoustic_piano", velocity: nil, pitchBends: nil)
        }
    }

    @Test func cMajorMelody() {
        let n = notes([(60, 2), (62, 1), (64, 1), (65, 1), (67, 2), (69, 1), (71, 0.5), (72, 2), (67, 1), (64, 1), (60, 2)])
        let top = KeyDetector.rank(notes: n).first
        #expect(top?.tonic == 0 && top?.mode == .major)
    }

    @Test func aMinorMelody() {
        let n = notes([(69, 3), (71, 1), (72, 1), (74, 1), (76, 2), (77, 1), (76, 1), (72, 1), (68, 0.5), (76, 1), (69, 3)])
        let top = KeyDetector.rank(notes: n).first
        #expect(top?.tonic == 9 && top?.mode == .minor)
    }

    @Test func dorianIsRecognisedOverRelativeMajor() {
        // D dorian: D E F G A B C with heavy emphasis on D and A.
        let n = notes([(62, 3), (64, 1), (65, 1), (67, 1), (69, 2), (71, 1.5), (72, 0.5), (69, 1), (62, 3)])
        let top = KeyDetector.rank(notes: n).first
        #expect(top?.tonic == 2 && top?.mode == .dorian)
    }

    @Test func drumsAndEmptyInputGiveNoRanking() {
        #expect(KeyDetector.rank(notes: []).isEmpty)
        let d = NoteEvent(onset: 0, offset: 1, pitch: 36, program: 128, isDrum: true, instrument: "drums", velocity: nil, pitchBends: nil)
        #expect(KeyDetector.rank(notes: [d]).isEmpty)
    }

    @Test func audioChromaFindsGMajorScale() {
        let rate = 16000.0
        // All seven G major degrees, the triad strongest.
        let tones: [(Double, Double)] = [(196.0, 1.0), (220.0, 0.4), (246.94, 0.7), (261.63, 0.5), (293.66, 0.8), (329.63, 0.4), (369.99, 0.5)]
        let audio = (0..<Int(4 * rate)).map { i in
            Float(tones.reduce(0) { $0 + $1.1 * sin(2 * .pi * $1.0 * Double(i) / rate) } * 0.1)
        }
        let top = KeyDetector.rank(samples: audio, sampleRate: rate).first
        #expect(top?.tonic == 7 && top?.mode == .major)
    }

    @Test func fileNamesCarryTheKeyInPlainAscii() {
        #expect(ExportNaming.fileName(base: "Song", key: KeyMatch(tonic: 3, mode: .minor, score: 0.9)) == "Song - Eb minor")
        #expect(ExportNaming.fileName(base: "Song", key: KeyMatch(tonic: 6, mode: .major, score: 0.9)) == "Song - F# major")
        #expect(ExportNaming.fileName(base: "Song", key: nil) == "Song")
        let n = notes([(60, 2), (62, 1), (64, 1), (65, 1), (67, 2), (69, 1), (71, 0.5), (72, 2), (67, 1), (64, 1), (60, 2)])
        #expect(ExportNaming.fileName(base: "Take", key: KeyDetector.rank(notes: n).first) == "Take - C major")
        #expect(KeyMatch.noteNames.count == 12 && (0..<12).allSatisfy { !KeyMatch(tonic: $0, mode: .major, score: 0).fileLabel.contains("♯") })
    }
}
