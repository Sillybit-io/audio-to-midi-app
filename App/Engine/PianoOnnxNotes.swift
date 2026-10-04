import Foundation

struct PianoNote: Equatable, Sendable {
    var onset: Double
    var offset: Double
    var pitch: Int
    /// MIDI velocity, 0...128 as the reference computes it; clamp before writing a file.
    var velocity: Int
}

/// Port of the note post-processing of qiuqiangkong/piano_transcription_inference (commit 0226e74):
/// `RegressionPostProcessor` and `note_detection_with_onset_offset_regress`. The matrices are row-major,
/// one row per 10 ms frame and one column per piano key from A0.
enum PianoOnnxNotes {
    static let framesPerSecond = 100.0
    static let classes = 88
    static let beginNote = 21
    static let velocityScale: Float = 128
    static let onsetThreshold: Float = 0.3
    static let offsetThreshold: Float = 0.3
    static let frameThreshold: Float = 0.1
    static let maxHeldFrames = 600

    private struct Event {
        var begin: Int
        var end: Int
        var onsetShift: Float
        var offsetShift: Float
        var velocity: Float
    }

    static func decode(onset: Matrix, offset: Matrix, frame: Matrix, velocity: Matrix) -> [PianoNote] {
        let rows = frame.rows
        let cols = frame.cols
        guard rows > 0, cols == classes else { return [] }

        let onsets = binarize(onset, threshold: onsetThreshold, neighbour: 2)
        let offsets = binarize(offset, threshold: offsetThreshold, neighbour: 4)

        var notes: [PianoNote] = []
        for key in 0..<cols {
            let events = detect(key: key, rows: rows, cols: cols, frame: frame.data, velocity: velocity.data,
                                onset: onsets, offset: offsets)
            for e in events {
                notes.append(PianoNote(
                    onset: (Double(e.begin) + Double(e.onsetShift)) / framesPerSecond,
                    offset: (Double(e.end) + Double(e.offsetShift)) / framesPerSecond,
                    pitch: key + beginNote,
                    velocity: Int(e.velocity * velocityScale)))
            }
        }
        return notes
    }

    private struct Binarized {
        var on: [Bool]
        var shift: [Float]
    }

    /// Keeps a regression peak only where it exceeds the threshold and falls off monotonically on both sides,
    /// and estimates the sub-frame time shift of that peak.
    private static func binarize(_ matrix: Matrix, threshold: Float, neighbour: Int) -> Binarized {
        let rows = matrix.rows, cols = matrix.cols
        var out = Binarized(on: [Bool](repeating: false, count: rows * cols), shift: [Float](repeating: 0, count: rows * cols))
        guard rows > 2 * neighbour else { return out }
        let x = matrix.data
        for k in 0..<cols {
            for n in neighbour..<(rows - neighbour) {
                let centre = x[n * cols + k]
                guard centre > threshold, isMonotonic(x, column: k, cols: cols, at: n, neighbour: neighbour) else { continue }
                out.on[n * cols + k] = true
                let before = x[(n - 1) * cols + k]
                let after = x[(n + 1) * cols + k]
                out.shift[n * cols + k] = before > after
                    ? (after - before) / (centre - after) / 2
                    : (after - before) / (centre - before) / 2
            }
        }
        return out
    }

    private static func isMonotonic(_ x: [Float], column k: Int, cols: Int, at n: Int, neighbour: Int) -> Bool {
        for i in 0..<neighbour {
            if x[(n - i) * cols + k] < x[(n - i - 1) * cols + k] { return false }
            if x[(n + i) * cols + k] < x[(n + i + 1) * cols + k] { return false }
        }
        return true
    }

    private static func detect(key k: Int, rows: Int, cols: Int, frame: [Float], velocity: [Float],
                               onset: Binarized, offset: Binarized) -> [Event] {
        var events: [Event] = []
        var begin: Int?
        var frameDisappear: Int?
        var offsetOccur: Int?

        func at(_ array: [Float], _ i: Int) -> Float { array[i * cols + k] }

        for i in 0..<rows {
            if onset.on[i * cols + k] {
                if let b = begin {
                    events.append(Event(begin: b, end: max(i - 1, 0), onsetShift: at(onset.shift, b), offsetShift: 0, velocity: at(velocity, b)))
                    frameDisappear = nil
                    offsetOccur = nil
                }
                begin = i
            }

            guard let b = begin, i > b else { continue }
            if at(frame, i) <= frameThreshold && frameDisappear == nil { frameDisappear = i }
            if offset.on[i * cols + k] && offsetOccur == nil { offsetOccur = i }

            if let gone = frameDisappear {
                var end = gone
                if let occurred = offsetOccur, occurred - b > gone - occurred { end = occurred }
                events.append(Event(begin: b, end: end, onsetShift: at(onset.shift, b), offsetShift: at(offset.shift, end), velocity: at(velocity, b)))
                begin = nil
                frameDisappear = nil
                offsetOccur = nil
            }

            if let held = begin, i - held >= maxHeldFrames || i == rows - 1 {
                events.append(Event(begin: held, end: i, onsetShift: at(onset.shift, held), offsetShift: at(offset.shift, i), velocity: at(velocity, held)))
                begin = nil
                frameDisappear = nil
                offsetOccur = nil
            }
        }
        return events.sorted { $0.begin < $1.begin }
    }
}
