import Foundation

struct Matrix: Sendable {
    let rows: Int
    let cols: Int
    var data: [Float]

    init(rows: Int, cols: Int, data: [Float]) {
        precondition(data.count == rows * cols)
        self.rows = rows
        self.cols = cols
        self.data = data
    }
}

struct BasicPitchNote: Equatable, Sendable {
    var start: Double
    var end: Double
    var pitch: Int
    var amplitude: Double
    /// Pitch bend per frame in units of a third of a semitone, or nil when dropped.
    var bends: [Int]?

    var velocity: Int { Int((127 * amplitude).rounded(.toNearestOrEven)) }
}

/// Port of Basic Pitch's note extraction (spotify/basic-pitch, note_creation.py at fa5997a).
enum BasicPitchNotes {
    static let midiOffset = 21
    static let maxFreqIndex = 87
    static let contourBins = 264
    static let framesPerWindow = 172
    static let fftHop = 256.0
    static let sampleRate = 22050.0
    static let windowSamples = 43844
    static let alignmentOffset = 0.0018
    static let bendTolerance = 25

    static func frameTimes(count: Int) -> [Double] {
        let windowOffset = (fftHop / sampleRate) * (Double(framesPerWindow) - Double(windowSamples) / fftHop) + alignmentOffset
        return (0..<count).map { t in
            Double(t) * fftHop / sampleRate - windowOffset * Double(t / framesPerWindow)
        }
    }

    static func decode(note: Matrix, onset: Matrix, contour: Matrix,
                       onsetThreshold: Double = 0.5, frameThreshold: Double = 0.3,
                       minNoteLength: Int = 11, energyTolerance: Int = 11,
                       inferOnsets: Bool = true, melodia: Bool = true) -> [BasicPitchNote] {
        let n = note.rows
        let cols = note.cols
        guard n > 0 else { return [] }
        let frames = note.data.map(Double.init)
        var onsets = onset.data.map(Double.init)
        if inferOnsets { onsets = inferredOnsets(onsets, frames, rows: n, cols: cols) }

        var peaks: [(t: Int, f: Int)] = []
        if n >= 3 {
            for t in 1..<(n - 1) {
                for f in 0..<cols {
                    let v = onsets[t * cols + f]
                    if v > onsets[(t - 1) * cols + f], v > onsets[(t + 1) * cols + f], v >= onsetThreshold {
                        peaks.append((t, f))
                    }
                }
            }
        }

        var remaining = frames
        var events: [(start: Int, end: Int, pitch: Int, amplitude: Double)] = []

        func zeroNeighbours(_ t: Int, _ f: Int) {
            if f < maxFreqIndex { remaining[t * cols + f + 1] = 0 }
            if f > 0 { remaining[t * cols + f - 1] = 0 }
        }

        func mean(_ from: Int, _ to: Int, _ f: Int) -> Double {
            var sum = 0.0
            for t in from..<to { sum += frames[t * cols + f] }
            return sum / Double(to - from)
        }

        for (start, f) in peaks.reversed() {
            if start >= n - 1 { continue }
            var i = start + 1
            var k = 0
            while i < n - 1 && k < energyTolerance {
                if remaining[i * cols + f] < frameThreshold { k += 1 } else { k = 0 }
                i += 1
            }
            i -= k
            if i - start <= minNoteLength { continue }
            for t in start..<i {
                remaining[t * cols + f] = 0
                zeroNeighbours(t, f)
            }
            events.append((start, i, f + midiOffset, mean(start, i, f)))
        }

        if melodia {
            // The reference repeatedly takes the global maximum; values are only ever zeroed, so
            // visiting the cells once in descending value order (ties by flat index) is identical.
            var order = remaining.indices.filter { remaining[$0] > frameThreshold }
            order.sort { remaining[$0] != remaining[$1] ? remaining[$0] > remaining[$1] : $0 < $1 }
            for index in order {
                guard remaining[index] > frameThreshold else { continue }
                let mid = index / cols
                let f = index % cols
                remaining[index] = 0

                var i = mid + 1
                var k = 0
                while i < n - 1 && k < energyTolerance {
                    if remaining[i * cols + f] < frameThreshold { k += 1 } else { k = 0 }
                    remaining[i * cols + f] = 0
                    zeroNeighbours(i, f)
                    i += 1
                }
                let end = i - 1 - k

                i = mid - 1
                k = 0
                while i > 0 && k < energyTolerance {
                    if remaining[i * cols + f] < frameThreshold { k += 1 } else { k = 0 }
                    remaining[i * cols + f] = 0
                    zeroNeighbours(i, f)
                    i -= 1
                }
                let start = i + 1 + k
                if end - start <= minNoteLength { continue }
                events.append((start, end, f + midiOffset, mean(start, end, f)))
            }
        }

        let times = frameTimes(count: contour.rows)
        return events.map { e in
            BasicPitchNote(start: times[e.start], end: times[e.end], pitch: e.pitch, amplitude: e.amplitude,
                           bends: pitchBends(contour, start: e.start, end: e.end, pitch: e.pitch))
        }
    }

    private static func inferredOnsets(_ onsets: [Double], _ frames: [Double], rows: Int, cols: Int) -> [Double] {
        var diff = [Double](repeating: 0, count: rows * cols)
        for t in 0..<rows {
            for f in 0..<cols {
                let d1 = frames[t * cols + f] - (t >= 1 ? frames[(t - 1) * cols + f] : 0)
                let d2 = frames[t * cols + f] - (t >= 2 ? frames[(t - 2) * cols + f] : 0)
                var d = min(d1, d2)
                if d < 0 || t < 2 { d = 0 }
                diff[t * cols + f] = d
            }
        }
        let maxOnset = onsets.max() ?? 0
        let maxDiff = diff.max() ?? 0
        guard maxDiff > 0 else { return onsets }
        return zip(onsets, diff).map { max($0, maxOnset * $1 / maxDiff) }
    }

    private static let bendWindow: [Double] = {
        let length = bendTolerance * 2 + 1
        return (0..<length).map { i in
            let x = Double(i) - Double(length - 1) / 2
            return exp(-x * x / (2 * 25))
        }
    }()

    private static func pitchBends(_ contour: Matrix, start: Int, end: Int, pitch: Int) -> [Int] {
        let length = bendTolerance * 2 + 1
        let freq = 3 * pitch - 63
        let from = max(freq - bendTolerance, 0)
        let to = min(contourBins, freq + bendTolerance + 1)
        let windowFrom = max(0, bendTolerance - freq)
        let shift = bendTolerance - windowFrom
        _ = length
        return (start..<end).map { t in
            var best = -Double.infinity
            var bestIndex = 0
            for (j, c) in (from..<to).enumerated() {
                let v = Double(contour.data[t * contour.cols + c]) * bendWindow[windowFrom + j]
                if v > best { best = v; bestIndex = j }
            }
            return bestIndex - shift
        }
    }

    /// Drops pitch bends from notes that overlap another note, as the reference does before writing MIDI.
    static func dropOverlappingBends(_ notes: [BasicPitchNote]) -> [BasicPitchNote] {
        var sorted = notes.sorted {
            ($0.start, $0.end, $0.pitch, $0.amplitude) < ($1.start, $1.end, $1.pitch, $1.amplitude)
        }
        if sorted.count > 1 {
            for i in 0..<(sorted.count - 1) {
                for j in (i + 1)..<sorted.count {
                    if sorted[j].start >= sorted[i].end { break }
                    sorted[i].bends = nil
                    sorted[j].bends = nil
                }
            }
        }
        return sorted
    }
}
