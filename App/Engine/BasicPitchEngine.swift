import CoreML
import Foundation

enum BasicPitchError: LocalizedError {
    case modelMissing
    case unexpectedOutput

    var errorDescription: String? {
        switch self {
        case .modelMissing: "The bundled Basic Pitch model could not be loaded."
        case .unexpectedOutput: "Basic Pitch returned output of an unexpected shape."
        }
    }
}

/// Basic Pitch on Core ML, run in-process. Windowing and unwrapping follow the reference inference module.
struct BasicPitchEngine: Sendable {
    static let sampleRate = 22050.0
    static let windowSamples = 43844
    static let overlapFrames = 30
    static let hopSamples = windowSamples - overlapFrames * 256
    static let leadingPad = overlapFrames * 256 / 2
    static let framesPerWindow = 172
    static let keptFramesPerWindow = framesPerWindow - overlapFrames

    var modelURL: URL? = Bundle(for: ModelStoreProbe.self).url(forResource: "BasicPitch", withExtension: "mlmodelc")

    /// How many windows cover `sampleCount` samples once the leading pad is added.
    static func windowCount(sampleCount: Int) -> Int {
        (leadingPad + sampleCount + hopSamples - 1) / hopSamples
    }

    /// Writes window `index` into `buffer`, which holds `windowSamples`: zeros for the leading pad, then the samples,
    /// then zeros past their end. Windows are made one at a time, so a long recording is never held twice.
    static func fillWindow(_ index: Int, of samples: [Float], into buffer: UnsafeMutableBufferPointer<Float>) {
        let first = index * hopSamples - leadingPad
        for i in 0..<windowSamples {
            let source = first + i
            buffer[i] = source >= 0 && source < samples.count ? samples[source] : 0
        }
    }

    static func framesKept(originalLength: Int, windowCount: Int) -> Int {
        min(windowCount * keptFramesPerWindow, Int(Double(originalLength) / Double(hopSamples) * Double(keptFramesPerWindow)))
    }

    func load() throws -> MLModel {
        guard let modelURL else { throw BasicPitchError.modelMissing }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        do { return try MLModel(contentsOf: modelURL, configuration: configuration) } catch { throw BasicPitchError.modelMissing }
    }

    /// Runs the model over mono 22.05 kHz samples and returns the unwrapped note, onset and contour matrices.
    func infer(samples: [Float], model: MLModel, progress: (Double) -> Void = { _ in }) throws -> (note: Matrix, onset: Matrix, contour: Matrix) {
        let count = Self.windowCount(sampleCount: samples.count)
        let trim = Self.overlapFrames / 2
        let keep = trim..<(Self.framesPerWindow - trim)
        var note: [Float] = [], onset: [Float] = [], contour: [Float] = []
        note.reserveCapacity(count * keep.count * 88)
        onset.reserveCapacity(count * keep.count * 88)
        contour.reserveCapacity(count * keep.count * 264)
        let input = try MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples), 1], dataType: .float32)
        for index in 0..<count {
            try Task.checkCancellation()
            input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in Self.fillWindow(index, of: samples, into: buffer) }
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_2": MLFeatureValue(multiArray: input)]))
            guard let n = output.featureValue(for: "Identity_1")?.multiArrayValue,
                  let o = output.featureValue(for: "Identity_2")?.multiArrayValue,
                  let c = output.featureValue(for: "Identity")?.multiArrayValue else { throw BasicPitchError.unexpectedOutput }
            try Self.append(n, cols: 88, keep: keep, to: &note)
            try Self.append(o, cols: 88, keep: keep, to: &onset)
            try Self.append(c, cols: 264, keep: keep, to: &contour)
            progress(Double(index + 1) / Double(count))
        }
        let frames = Self.framesKept(originalLength: samples.count, windowCount: count)
        note.removeLast(note.count - frames * 88)
        onset.removeLast(onset.count - frames * 88)
        contour.removeLast(contour.count - frames * 264)
        return (Matrix(rows: frames, cols: 88, data: note), Matrix(rows: frames, cols: 88, data: onset),
                Matrix(rows: frames, cols: 264, data: contour))
    }

    private static func append(_ array: MLMultiArray, cols: Int, keep: Range<Int>, to result: inout [Float]) throws {
        let shape = array.shape.map(\.intValue)
        guard shape.count == 3, shape[1] == framesPerWindow, shape[2] == cols else { throw BasicPitchError.unexpectedOutput }
        let strides = array.strides.map(\.intValue)
        if array.dataType == .float32 {
            array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                for t in keep { for f in 0..<cols { result.append(buffer[t * strides[1] + f * strides[2]]) } }
            }
        } else {
            for t in keep { for f in 0..<cols { result.append(array[[0, NSNumber(value: t), NSNumber(value: f)]].floatValue) } }
        }
    }

    func notes(samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [BasicPitchNote] {
        let model = try load()
        let out = try infer(samples: samples, model: model, progress: progress)
        return BasicPitchNotes.decode(note: out.note, onset: out.onset, contour: out.contour)
    }

    /// Same event stream as the sidecar, so the session treats both engines alike.
    func stream(samples: [Float], sourceRate: Double) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let resampled = try Resampler.resample(samples, from: sourceRate, to: Self.sampleRate)
                    let model = try load()
                    let device = EngineDevice(index: 0, name: "Core ML (CPU)", backend: "CoreML", integrated: nil, memoryTotal: nil)
                    continuation.yield(.ready(device: device, chunks: Self.windowCount(sampleCount: resampled.count)))
                    let out = try infer(samples: resampled, model: model) { p in
                        continuation.yield(.update(progress: p, finalizedThrough: 0, notes: []))
                    }
                    let decoded = BasicPitchNotes.decode(note: out.note, onset: out.onset, contour: out.contour)
                    let kept = BasicPitchNotes.dropOverlappingBends(decoded)
                    let notes = kept.map {
                        EngineNote(onset: $0.start, offset: $0.end, pitch: $0.pitch, program: 4, isDrum: false,
                                   instrument: "electric_piano", velocity: $0.velocity, pitchBends: $0.bends)
                    }
                    continuation.yield(.update(progress: 1, finalizedThrough: Double(resampled.count) / Self.sampleRate, notes: notes))
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
