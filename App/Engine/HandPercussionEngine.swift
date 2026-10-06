import Accelerate
import Foundation

enum HandPercussionError: LocalizedError {
    case fftUnavailable

    var errorDescription: String? { "The hand percussion detector could not set up its spectrum analysis." }
}

/// A real-input FFT of one fixed size: the magnitudes of its first half.
private final class RealFFT {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var real: [Float]
    private var imaginary: [Float]

    init?(size: Int) {
        self.size = size
        log2n = vDSP_Length(size.trailingZeroBitCount)
        guard size > 1, size & (size - 1) == 0, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// |DFT| of the `size` samples in `frame` for bins 0..<size/2. The Nyquist bin is left out.
    func magnitudes(of frame: [Float], into out: inout [Float]) {
        let half = size / 2
        frame.withUnsafeBufferPointer { samples in
            samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { packed in
                real.withUnsafeMutableBufferPointer { re in
                    imaginary.withUnsafeMutableBufferPointer { im in
                        var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                        vDSP_ctoz(packed, 2, &split, 1, vDSP_Length(half))
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    }
                }
            }
        }
        // vDSP's real transform is twice the DFT, and packs the Nyquist bin into the imaginary part of bin 0.
        out[0] = abs(real[0]) / 2
        for k in 1..<half { out[k] = (real[k] * real[k] + imaginary[k] * imaginary[k]).squareRoot() / 2 }
    }
}

/// Finds the strokes of a hand drum, such as a darbuka or a doumbek, and labels each one low (doum) or high (tek, ka).
///
/// This is signal processing, not a trained model: no open model for hand drums that may be used commercially exists.
/// Strokes are the peaks of the spectral flux. Each one is labelled by how its energy splits between a low band, where
/// the bass tone from the centre of the head sits, and a high band, where the rim tones sit. The low tone becomes a
/// General MIDI Low Conga and the high tone an Open Hi Conga. It expects one hand drum on its own, and it cannot tell
/// tek from ka, which are the same sound played by each hand.
struct HandPercussionEngine: Sendable {
    static let sampleRate = 44100.0
    /// General MIDI Low Conga: the doum.
    static let lowPitch = 64
    /// General MIDI Open Hi Conga: the tek and the ka.
    static let highPitch = 63

    /// Analysis window and hop of the onset detector: 23 ms and 2.9 ms.
    static let frameSize = 1024
    static let hop = 128
    /// A stroke is judged on the 70 ms that start 4 ms after its onset, once the click of the attack has passed.
    static let strokeDelay = 0.004
    static let strokeLength = 0.07
    static let strokeFFT = 4096
    /// Strokes quieter than about -60 dBFS are noise.
    static let minimumStrokeRMS: Float = 0.001
    /// The closest two strokes can be.
    static let minimumGap = 0.06
    /// A flux peak counts when it is this much above the median of the flux in the quarter second around it.
    static let thresholdWindow = 0.25
    static let thresholdOffset: Float = 0.12
    /// Bands whose energy ratio labels a stroke, in Hz.
    static let lowBand: Range<Double> = 60..<400
    static let highBand: Range<Double> = 1500..<9000
    /// log10(low / high) above which a stroke is low, when the strokes don't fall into two clear groups.
    static let fallbackSplit: Float = 1.5
    /// How far apart the two groups' centres must be to split between them instead.
    static let minimumSeparation: Float = 1.2
    /// ... and how many times the spread inside a group.
    static let minimumDistinctness: Float = 4
    static let minimumStrokesToAdapt = 8

    // MARK: Onsets

    /// Positive change of the log spectrum from frame to frame, one value per frame of `hop` samples.
    static func flux(_ samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [Float] {
        let n = frameSize
        let half = n / 2
        guard let fft = RealFFT(size: n) else { throw HandPercussionError.fftUnavailable }
        let frames = samples.count / hop + 1
        // Frames are centred on every `hop`th sample, so half a frame of silence goes on each side.
        let padded = [Float](repeating: 0, count: half) + samples + [Float](repeating: 0, count: n)
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(n)) }
        let scale = 1 / Float(half)
        var frame = [Float](repeating: 0, count: n)
        var magnitude = [Float](repeating: 0, count: half)
        var previous = [Float](repeating: 0, count: half)
        var current = [Float](repeating: 0, count: half)
        var flux = [Float](repeating: 0, count: frames)
        for t in 0..<frames {
            if t % 512 == 0 {
                try Task.checkCancellation()
                progress(Double(t) / Double(frames))
            }
            vDSP.multiply(padded[(t * hop)..<(t * hop + n)], window, result: &frame)
            fft.magnitudes(of: frame, into: &magnitude)
            for k in 0..<half { current[k] = log1pf(100 * magnitude[k] * scale) }
            if t > 0 {
                var rise: Float = 0
                for k in 0..<half { rise += max(0, current[k] - previous[k]) }
                flux[t] = rise
            }
            swap(&previous, &current)
        }
        return flux
    }

    /// The median of the `size` values around each one, reflecting at the ends.
    static func medianFilter(_ x: [Float], size: Int) -> [Float] {
        let n = x.count
        guard n > 0, size > 1 else { return x }
        var window = [Float](repeating: 0, count: size)
        return (0..<n).map { i in
            for j in 0..<size {
                var k = i - size / 2 + j
                if k < 0 { k = -k - 1 }
                if k >= n { k = 2 * n - k - 1 }
                window[j] = x[min(max(k, 0), n - 1)]
            }
            window.sort()
            return window[size / 2]
        }
    }

    /// The frames that are onsets: local peaks of the flux above its running median, the strongest of any that are
    /// closer than `minimumGap`.
    static func onsetFrames(flux raw: [Float]) -> [Int] {
        guard raw.count >= 3, let top = raw.max(), top > 0 else { return [] }
        let flux = raw.map { $0 / top }
        let medians = medianFilter(flux, size: Int(thresholdWindow * sampleRate / Double(hop)))
        var candidates: [Int] = []
        for i in 1..<(flux.count - 1) {
            let isPeak = flux[i] > flux[i - 1] && flux[i] >= flux[i + 1]
            let floor: Float = medians[i] + thresholdOffset
            if isPeak && flux[i] >= floor { candidates.append(i) }
        }
        let gap = Int(minimumGap * sampleRate / Double(hop))
        var accepted: [Int] = []
        for frame in candidates.sorted(by: { flux[$0] > flux[$1] }) where !accepted.contains(where: { abs($0 - frame) < gap }) {
            accepted.append(frame)
        }
        return accepted.sorted()
    }

    // MARK: Strokes

    /// log10 of the energy below 400 Hz over the energy above 1.5 kHz in the stroke that starts at `start`, or nil when
    /// the audio ends too soon or is too quiet to be a stroke.
    private static func lowHighRatio(_ samples: [Float], from start: Int, fft: RealFFT) -> Float? {
        let length = min(Int(strokeLength * sampleRate), samples.count - start)
        guard start >= 0, length >= 512 else { return nil }
        let stroke = samples[start..<(start + length)]
        var rms: Float = 0
        vDSP_rmsqv(Array(stroke), 1, &rms, vDSP_Length(length))
        guard rms >= minimumStrokeRMS else { return nil }
        var frame = [Float](repeating: 0, count: fft.size)
        let turn = 2 * Float.pi / Float(length - 1)
        for (i, value) in stroke.enumerated() {
            let hann: Float = 0.5 - 0.5 * cos(turn * Float(i))
            frame[i] = value * hann
        }
        var magnitude = [Float](repeating: 0, count: fft.size / 2)
        fft.magnitudes(of: frame, into: &magnitude)
        var low: Float = 0
        var high: Float = 0
        for (k, m) in magnitude.enumerated() {
            let frequency = Double(k) * sampleRate / Double(fft.size)
            if lowBand.contains(frequency) { low += m * m } else if highBand.contains(frequency) { high += m * m }
        }
        return log10f((low + 1e-12) / (high + 1e-12))
    }

    /// The ratio above which a stroke is low. Two distinct groups of strokes are split halfway between their centres;
    /// anything else, such as a recording of only one tone whose strokes vary a little, is judged against a fixed value.
    static func split(ratios: [Float]) -> Float {
        guard ratios.count >= minimumStrokesToAdapt, let lowest = ratios.min(), let highest = ratios.max() else { return fallbackSplit }
        var lower = lowest
        var upper = highest
        for _ in 0..<20 {
            var sums: (Float, Float) = (0, 0)
            var counts = (0, 0)
            for ratio in ratios {
                if abs(ratio - lower) <= abs(ratio - upper) { sums.0 += ratio; counts.0 += 1 } else { sums.1 += ratio; counts.1 += 1 }
            }
            if counts.0 > 0 { lower = sums.0 / Float(counts.0) }
            if counts.1 > 0 { upper = sums.1 / Float(counts.1) }
        }
        // Cutting any spread of values in two leaves centres about three spreads apart, so the groups only count as
        // distinct when their centres are further apart than that.
        var squares: Float = 0
        for ratio in ratios {
            let centre = abs(ratio - lower) <= abs(ratio - upper) ? lower : upper
            squares += (ratio - centre) * (ratio - centre)
        }
        let spread = (squares / Float(ratios.count)).squareRoot()
        let separation = upper - lower
        let distinct = separation >= minimumSeparation && separation >= minimumDistinctness * max(spread, 0.05)
        return distinct ? (lower + upper) / 2 : fallbackSplit
    }

    /// Every stroke of `samples`, which are mono at 44.1 kHz, with its time and its low-to-high ratio.
    func strokes(samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [(time: Double, ratio: Float)] {
        guard samples.count >= Self.frameSize else { return [] }
        let frames = Self.onsetFrames(flux: try Self.flux(samples) { progress($0 * 0.9) })
        guard let fft = RealFFT(size: Self.strokeFFT) else { throw HandPercussionError.fftUnavailable }
        let delay = Int(Self.strokeDelay * Self.sampleRate)
        var strokes: [(time: Double, ratio: Float)] = []
        for frame in frames {
            try Task.checkCancellation()
            let centre = frame * Self.hop
            if let ratio = Self.lowHighRatio(samples, from: centre + delay, fft: fft) {
                strokes.append((Double(centre) / Self.sampleRate, ratio))
            }
        }
        progress(1)
        return strokes
    }

    /// One hit per stroke of `samples`, which are mono at 44.1 kHz.
    func hits(samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [DrumHit] {
        let strokes = try strokes(samples: samples, progress: progress)
        let boundary = Self.split(ratios: strokes.map(\.ratio))
        return strokes.map { DrumHit(time: $0.time, pitch: $0.ratio >= boundary ? Self.lowPitch : Self.highPitch, velocity: nil) }
    }

    /// Same event stream as the other engines. `samples` are mono 44.1 kHz.
    func stream(samples: [Float]) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let device = EngineDevice(index: 0, name: "Built in", backend: "DSP", integrated: nil, memoryTotal: nil)
                    continuation.yield(.ready(device: device, chunks: 1))
                    let duration = Double(samples.count) / Self.sampleRate
                    let hits = try self.hits(samples: samples) { p in
                        continuation.yield(.update(progress: p * 0.95, finalizedThrough: 0, notes: []))
                    }
                    let notes = DrumOnnxEngine.notes(from: hits, duration: duration)
                    continuation.yield(.update(progress: 1, finalizedThrough: duration, notes: notes))
                    continuation.yield(.done(noteCount: notes.count))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
