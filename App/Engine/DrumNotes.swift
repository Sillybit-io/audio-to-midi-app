import Foundation

/// One detected drum hit. `velocity` is nil when the model has none.
struct DrumHit: Equatable, Sendable {
    var time: Double
    var pitch: Int
    var velocity: Int?
}

/// Turns the activations of a drum model into hits. Both decoders read row-major matrices at 100 frames per second.
enum DrumNotes {
    static let framesPerSecond = 100.0

    // MARK: ADTOF

    /// GM pitches of the five ADTOF outputs: kick, snare, toms, hi-hat, cymbals and ride.
    static let adtofPitches = [36, 38, 47, 42, 49]
    /// Per-class peak thresholds the authors fitted for Frame_RNN (hyperparameters.py, "peakThreshold").
    static let adtofThresholds: [Float] = [0.22, 0.24, 0.32, 0.22, 0.30]

    /// `madmom.features.notes.NotePeakPickingProcessor(threshold, smooth=0, pre_avg=0.1, post_avg=0.01, pre_max=0.02,
    /// post_max=0.01, combine=0.02, fps=100)` run on each class separately, as ADTOF's `PeakPicking.predict` does.
    static func decodeADTOF(_ activations: Matrix) -> [DrumHit] {
        guard activations.cols == adtofPitches.count else { return [] }
        var hits: [DrumHit] = []
        for (column, pitch) in adtofPitches.enumerated() {
            let series = (0..<activations.rows).map { activations.data[$0 * activations.cols + column] }
            for frame in peakFrames(series, threshold: adtofThresholds[column]) {
                hits.append(DrumHit(time: Double(frame) / framesPerSecond, pitch: pitch, velocity: nil))
            }
        }
        return hits.sorted { ($0.time, $0.pitch) < ($1.time, $1.pitch) }
    }

    private static let preAverage = 10, postAverage = 1, preMax = 2, postMax = 1, combineFrames = 2

    /// madmom's `peak_picking` followed by `combine_events(..., "left")`: a frame is a peak when it is at least the
    /// threshold above the moving average (zero-padded, `preAverage` frames before and `postAverage` after) and the
    /// maximum of its window (`preMax` before, `postMax` after); peaks closer than `combineFrames` keep the first.
    static func peakFrames(_ x: [Float], threshold: Float) -> [Int] {
        let n = x.count
        guard n > 0 else { return [] }
        var prefix = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + Double(x[i]) }
        let length = Double(preAverage + postAverage + 1)
        var detections = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let lo = max(0, i - preAverage), hi = min(n - 1, i + postAverage)
            let average = Float((prefix[hi + 1] - prefix[lo]) / length)
            if x[i] >= average + threshold { detections[i] = x[i] }
        }
        var peaks: [Int] = []
        for i in 0..<n where detections[i] > 0 {
            let lo = max(0, i - preMax), hi = min(n - 1, i + postMax)
            var window: Float = 0
            for j in lo...hi { window = max(window, detections[j]) }
            if detections[i] == window { peaks.append(i) }
        }
        var combined: [Int] = []
        for frame in peaks {
            if let last = combined.last, frame - last <= combineFrames { continue }
            combined.append(frame)
        }
        return combined
    }

    // MARK: Onsets and Frames Drums

    /// The eight pitches the E-GMD model was trained on (drum_mappings '8-hit'): kick, snare, toms, closed hi-hat,
    /// ride, ride bell and cowbell, crash, clave.
    static let oafPitches = [36, 38, 48, 42, 51, 53, 49, 75]
    static let oafOnsetThreshold: Float = 0.5

    /// Magenta's drum inference (`onset_probs > 0.5`, velocity `int(clip(v, 0, 1) * 127)`), with one change: a run of
    /// consecutive active frames is one hit, placed on the frame with the highest probability.
    static func decodeOaF(onset: Matrix, velocity: Matrix) -> [DrumHit] {
        guard onset.cols == oafPitches.count, velocity.cols == onset.cols, velocity.rows == onset.rows else { return [] }
        var hits: [DrumHit] = []
        for (column, pitch) in oafPitches.enumerated() {
            var row = 0
            while row < onset.rows {
                guard onset.data[row * onset.cols + column] > oafOnsetThreshold else { row += 1; continue }
                var best = row
                var next = row
                while next < onset.rows, onset.data[next * onset.cols + column] > oafOnsetThreshold {
                    if onset.data[next * onset.cols + column] > onset.data[best * onset.cols + column] { best = next }
                    next += 1
                }
                let raw = min(max(velocity.data[best * velocity.cols + column], 0), 1) * 127
                hits.append(DrumHit(time: Double(best) / framesPerSecond, pitch: pitch, velocity: max(1, Int(raw))))
                row = next
            }
        }
        return hits.sorted { ($0.time, $0.pitch) < ($1.time, $1.pitch) }
    }
}
