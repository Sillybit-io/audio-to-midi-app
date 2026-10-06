import Foundation
@preconcurrency import OnnxRuntimeBindings

/// Isolates the drums of a mix with the HT-Demucs drums specialist (ONNX). Segmenting and overlap-add follow the
/// `infer.py` published with the model: 7.8 s segments, a quarter of a segment overlapping, linear fades, and a division
/// by the summed fades. The model is stereo; the app holds mono audio, so both channels get the same samples and the two
/// drum channels are averaged on the way out.
struct DrumSeparator: Sendable {
    static let sampleRate = 44100.0
    static let segment = 343_980
    static let overlap = segment / 4
    static let stride = segment - overlap

    var modelURL: URL
    var threads = 0

    /// Start sample of every segment.
    static func starts(sampleCount: Int) -> [Int] {
        guard sampleCount > 0 else { return [] }
        return (0..<max(1, (sampleCount + stride - 1) / stride)).map { $0 * stride }
    }

    /// 1 in the middle, a linear fade over the first and last `overlap` samples.
    static func window() -> [Float] {
        var w = [Float](repeating: 1, count: segment)
        for i in 0..<overlap {
            let fade = Float(i) / Float(overlap - 1)
            w[i] = fade
            w[segment - 1 - i] = fade
        }
        return w
    }

    /// Overlap-adds per-segment mono drum stems into one signal of `count` samples.
    static func combine(_ stems: [[Float]], starts: [Int], count: Int) -> [Float] {
        let window = window()
        var out = [Float](repeating: 0, count: count)
        var weight = [Float](repeating: 0, count: count)
        for (stem, start) in zip(stems, starts) {
            let length = min(segment, count - start)
            for i in 0..<length {
                out[start + i] += stem[i] * window[i]
                weight[start + i] += window[i]
            }
        }
        for i in 0..<count { out[i] /= max(weight[i], 1e-8) }
        return out
    }

    func separate(samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [Float] {
        let starts = Self.starts(sampleCount: samples.count)
        guard !starts.isEmpty else { return [] }
        let session: ORTSession
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            if threads > 0 { try options.setIntraOpNumThreads(Int32(threads)) }
            session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
        } catch {
            throw DrumOnnxError.modelUnavailable(error.localizedDescription)
        }
        var stems: [[Float]] = []
        for (index, start) in starts.enumerated() {
            try Task.checkCancellation()
            // ONNX Runtime's results are autoreleased (see `PianoOnnxEngine.notes`) and each answer here is 11 MB, so the
            // pool lets it go before the next segment instead of at the end of the run.
            try autoreleasepool {
                let end = min(start + Self.segment, samples.count)
                var mono = Array(samples[start..<end])
                mono += [Float](repeating: 0, count: Self.segment - mono.count)
                let data = NSMutableData(bytes: mono + mono, length: 2 * Self.segment * MemoryLayout<Float>.size)
                let input = try ORTValue(tensorData: data, elementType: .float, shape: [1, 2, NSNumber(value: Self.segment)])
                let outputs = try session.run(withInputs: ["mix": input], outputNames: ["stems"], runOptions: nil)
                guard let value = outputs["stems"] else { throw DrumOnnxError.unexpectedOutput }
                let bytes = try value.tensorData()
                // [1, 4, 2, segment]: source 0 is the drums.
                guard bytes.length == 4 * 2 * Self.segment * MemoryLayout<Float>.size else { throw DrumOnnxError.unexpectedOutput }
                let floats = Data(bytes).withUnsafeBytes { Array($0.bindMemory(to: Float.self)[0..<(2 * Self.segment)]) }
                stems.append((0..<Self.segment).map { 0.5 * (floats[$0] + floats[Self.segment + $0]) })
            }
            progress(Double(index + 1) / Double(starts.count))
        }
        return Self.combine(stems, starts: starts, count: samples.count)
    }
}
