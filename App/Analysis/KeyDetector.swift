import Foundation

enum ScaleMode: String, CaseIterable, Sendable {
    case major = "major", minor = "minor", dorian, phrygian, lydian, mixolydian, locrian

    var intervals: [Int] {
        switch self {
        case .major: [0, 2, 4, 5, 7, 9, 11]
        case .minor: [0, 2, 3, 5, 7, 8, 10]
        case .dorian: [0, 2, 3, 5, 7, 9, 10]
        case .phrygian: [0, 1, 3, 5, 7, 8, 10]
        case .lydian: [0, 2, 4, 6, 7, 9, 11]
        case .mixolydian: [0, 2, 4, 5, 7, 9, 10]
        case .locrian: [0, 1, 3, 5, 6, 8, 10]
        }
    }
}

struct KeyMatch: Equatable, Sendable, Identifiable {
    var tonic: Int
    var mode: ScaleMode
    /// Pearson correlation with the mode's template, -1...1.
    var score: Double

    var id: String { name }
    static let noteNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
    var name: String { "\(Self.noteNames[tonic]) \(mode.rawValue)" }

    private static let fileNoteNames = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    /// Plain ASCII, safe in a file name: "Eb minor".
    var fileLabel: String { "\(Self.fileNoteNames[tonic]) \(mode.rawValue)" }
}

/// Ranks keys and scales by correlating a pitch-class profile with Krumhansl-Kessler key profiles
/// (major, minor) and degree-role templates (the other modes) built from the same weights.
enum KeyDetector {
    private static let krumhanslMajor = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let krumhanslMinor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    static func template(for mode: ScaleMode) -> [Double] {
        switch mode {
        case .major: return krumhanslMajor
        case .minor: return krumhanslMinor
        default:
            // Start from the major or minor profile that shares the mode's third, then swap the weights
            // of the tones where the mode's scale differs from that base scale.
            let baseMode: ScaleMode = mode.intervals.contains(4) ? .major : .minor
            var t = baseMode == .major ? krumhanslMajor : krumhanslMinor
            let base = Set(baseMode.intervals), scale = Set(mode.intervals)
            let inScale = 3.5, outOfScale = 2.4
            for pc in base.subtracting(scale) { t[pc] = outOfScale }
            for pc in scale.subtracting(base) { t[pc] = inScale }
            return t
        }
    }

    /// Modes other than major and minor must beat them by this much to rank above them.
    static let modalPenalty = 0.01

    /// Pitch-class weights by sounding duration; drums are ignored.
    static func profile(notes: [NoteEvent]) -> [Double] {
        var p = [Double](repeating: 0, count: 12)
        for n in notes where !n.isDrum && n.offset > n.onset {
            p[((n.pitch % 12) + 12) % 12] += n.offset - n.onset
        }
        return p
    }

    static func rank(profile: [Double], modes: [ScaleMode] = ScaleMode.allCases) -> [KeyMatch] {
        guard profile.count == 12, profile.contains(where: { $0 > 0 }) else { return [] }
        var out: [KeyMatch] = []
        for mode in modes {
            let t = template(for: mode)
            for tonic in 0..<12 {
                let rotated = (0..<12).map { t[(($0 - tonic) % 12 + 12) % 12] }
                out.append(KeyMatch(tonic: tonic, mode: mode, score: correlation(profile, rotated) - (mode == .major || mode == .minor ? 0 : modalPenalty)))
            }
        }
        return out.sorted { $0.score > $1.score }
    }

    static func rank(notes: [NoteEvent]) -> [KeyMatch] { rank(profile: profile(notes: notes)) }

    /// Chroma from the audio itself: one-second blocks, square-rooted tone power at every pitch from C2 to B6.
    static func chroma(samples: [Float], sampleRate: Double) -> [Double] {
        let block = Int(sampleRate)
        var chroma = [Double](repeating: 0, count: 12)
        guard block > 0, samples.count >= block / 2 else { return chroma }
        var start = 0
        while start < samples.count {
            let end = min(start + block, samples.count)
            let n = end - start
            if n >= block / 2 {
                var window = [Double](repeating: 0, count: n)
                var gain = 0.0
                for i in 0..<n {
                    let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(n - 1))
                    window[i] = Double(samples[start + i]) * w
                    gain += w
                }
                for pitch in 36...95 {
                    let f = 440 * pow(2, Double(pitch - 69) / 12)
                    guard f < 0.45 * sampleRate else { break }
                    chroma[pitch % 12] += (VelocityEstimator.tonePower(window, frequency: f, sampleRate: sampleRate)).squareRoot() / gain
                }
            }
            start = end
        }
        return chroma
    }

    static func rank(samples: [Float], sampleRate: Double) -> [KeyMatch] {
        rank(profile: chroma(samples: samples, sampleRate: sampleRate))
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let ma = a.reduce(0, +) / 12, mb = b.reduce(0, +) / 12
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<12 {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        return da > 0 && db > 0 ? num / (da * db).squareRoot() : 0
    }
}
