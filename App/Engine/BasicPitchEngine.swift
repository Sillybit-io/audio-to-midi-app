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

    static func windows(for samples: [Float]) -> [[Float]] {
        let padded = [Float](repeating: 0, count: leadingPad) + samples
        return stride(from: 0, to: padded.count, by: hopSamples).map { start in
            var window = Array(padded[start..<min(start + windowSamples, padded.count)])
            if window.count < windowSamples { window += [Float](repeating: 0, count: windowSamples - window.count) }
            return window
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
        let windows = Self.windows(for: samples)
        var note: [Float] = [], onset: [Float] = [], contour: [Float] = []
        let trim = Self.overlapFrames / 2
        for (index, window) in windows.enumerated() {
            try Task.checkCancellation()
            let input = try MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples), 1], dataType: .float32)
            input.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
                for i in 0..<Self.windowSamples { buffer[i] = window[i] }
            }
            let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["input_2": MLFeatureValue(multiArray: input)]))
            guard let n = output.featureValue(for: "Identity_1")?.multiArrayValue,
                  let o = output.featureValue(for: "Identity_2")?.multiArrayValue,
                  let c = output.featureValue(for: "Identity")?.multiArrayValue else { throw BasicPitchError.unexpectedOutput }
            note += try Self.rows(n, cols: 88, keep: trim..<(Self.framesPerWindow - trim))
            onset += try Self.rows(o, cols: 88, keep: trim..<(Self.framesPerWindow - trim))
            contour += try Self.rows(c, cols: 264, keep: trim..<(Self.framesPerWindow - trim))
            progress(Double(index + 1) / Double(windows.count))
        }
        let frames = Self.framesKept(originalLength: samples.count, windowCount: windows.count)
        func matrix(_ data: [Float], _ cols: Int) -> Matrix { Matrix(rows: frames, cols: cols, data: Array(data[0..<(frames * cols)])) }
        return (matrix(note, 88), matrix(onset, 88), matrix(contour, 264))
    }

    private static func rows(_ array: MLMultiArray, cols: Int, keep: Range<Int>) throws -> [Float] {
        let shape = array.shape.map(\.intValue)
        guard shape.count == 3, shape[1] == framesPerWindow, shape[2] == cols else { throw BasicPitchError.unexpectedOutput }
        let strides = array.strides.map(\.intValue)
        var result = [Float](); result.reserveCapacity(keep.count * cols)
        if array.dataType == .float32 {
            array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
                for t in keep { for f in 0..<cols { result.append(buffer[t * strides[1] + f * strides[2]]) } }
            }
        } else {
            for t in keep { for f in 0..<cols { result.append(array[[0, NSNumber(value: t), NSNumber(value: f)]].floatValue) } }
        }
        return result
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
                    continuation.yield(.ready(device: device, chunks: Self.windows(for: resampled).count))
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
