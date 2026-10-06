import Foundation
@preconcurrency import OnnxRuntimeBindings

enum DrumOnnxError: LocalizedError {
    case modelUnavailable(String)
    case unexpectedOutput

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): "The drum model could not be loaded: \(reason)"
        case .unexpectedOutput: "The drum model returned output of an unexpected shape."
        }
    }
}

/// What differs between the two drum models: the ONNX output names and how the activations become hits.
struct DrumModelSpec: Sendable {
    enum Decoder: Sendable { case adtof, oaf }

    let decoder: Decoder
    let outputNames: [String]
    let classes: Int
    /// True when the model predicts the velocity of each hit itself.
    let predictsVelocity: Bool

    static let adtof = DrumModelSpec(decoder: .adtof, outputNames: ["activations"], classes: DrumNotes.adtofPitches.count,
                                     predictsVelocity: false)
    static let oaf = DrumModelSpec(decoder: .oaf, outputNames: ["onset_probs", "velocity"], classes: DrumNotes.oafPitches.count,
                                   predictsVelocity: true)
}

/// One ONNX Runtime session over a drum model. Takes a mono 44.1 kHz waveform and returns one matrix per output.
final class DrumOnnxSession: @unchecked Sendable {
    private let env: ORTEnv
    private let session: ORTSession
    private let spec: DrumModelSpec

    init(modelURL: URL, spec: DrumModelSpec, threads: Int) throws {
        self.spec = spec
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            func make(_ level: ORTGraphOptimizationLevel) throws -> ORTSession {
                let options = try ORTSessionOptions()
                try options.setGraphOptimizationLevel(level)
                if threads > 0 { try options.setIntraOpNumThreads(Int32(threads)) }
                return try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
            }
            let session: ORTSession
            do { session = try make(.all) } catch { session = try make(.none) }
            self.env = env
            self.session = session
        } catch {
            throw DrumOnnxError.modelUnavailable(error.localizedDescription)
        }
    }

    /// The frame count follows from the waveform length, so it is read back from the first output.
    func run(samples: [Float]) throws -> [Matrix] {
        let data = NSMutableData(bytes: samples, length: samples.count * MemoryLayout<Float>.size)
        let input = try ORTValue(tensorData: data, elementType: .float, shape: [1, NSNumber(value: samples.count)])
        let outputs = try session.run(withInputs: ["waveform": input], outputNames: Set(spec.outputNames), runOptions: nil)
        return try spec.outputNames.map { name in
            guard let value = outputs[name] else { throw DrumOnnxError.unexpectedOutput }
            let bytes = try value.tensorData()
            let floats = Data(bytes).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            guard !floats.isEmpty, floats.count % spec.classes == 0 else { throw DrumOnnxError.unexpectedOutput }
            return Matrix(rows: floats.count / spec.classes, cols: spec.classes, data: floats)
        }
    }
}

/// ADTOF Frame_RNN or Onsets and Frames Drums on ONNX Runtime. Both models take 44.1 kHz audio and answer at 100 frames
/// per second. Long recordings run in 50 s pieces with 5 s of context on each side; the context is thrown away, so the
/// recurrent layers see the same audio around every kept frame and the frames line up on the global 10 ms grid.
struct DrumOnnxEngine: Sendable {
    static let sampleRate = 44100.0
    static let hop = 441
    static let coreSamples = hop * 5000
    static let contextSamples = hop * 500
    /// Shorter recordings are padded to this; the frames past the real end are dropped with the hits beyond the duration.
    static let minimumSamples = hop * 10
    /// The length every hit is drawn and exported with.
    static let hitLength = 0.1

    var modelURL: URL
    var spec: DrumModelSpec
    var threads = 0
    /// When set, the drums are isolated from the mix first and the model listens to that.
    var separator: DrumSeparator?
    /// The share of the progress bar the separation takes: it is much the slower of the two steps.
    static let separationShare = 0.85

    struct Chunk: Equatable {
        /// The samples fed to the model.
        var input: Range<Int>
        /// Frames of the model's answer to skip: the left context.
        var skip: Int
        /// Frames of the answer to keep, or nil for everything that is left (the last chunk).
        var keep: Int?
    }

    static func chunks(sampleCount: Int) -> [Chunk] {
        guard sampleCount > 0 else { return [] }
        if sampleCount <= coreSamples + contextSamples { return [Chunk(input: 0..<sampleCount, skip: 0, keep: nil)] }
        let count = (sampleCount + coreSamples - 1) / coreSamples
        return (0..<count).map { index in
            let start = index * coreSamples
            let end = min(sampleCount, start + coreSamples)
            let from = max(0, start - contextSamples)
            let to = min(sampleCount, end + contextSamples)
            return Chunk(input: from..<to, skip: (start - from) / hop, keep: index == count - 1 ? nil : (end - start) / hop)
        }
    }

    /// Joins the per-chunk answers into one matrix on the global frame grid.
    static func assemble(_ parts: [Matrix], chunks: [Chunk]) -> Matrix {
        guard let cols = parts.first?.cols else { return Matrix(rows: 0, cols: 0, data: []) }
        var data: [Float] = []
        for (part, chunk) in zip(parts, chunks) {
            let from = min(chunk.skip, part.rows)
            let to = min(part.rows, chunk.keep.map { from + $0 } ?? part.rows)
            data += part.data[(from * cols)..<(to * cols)]
        }
        return Matrix(rows: data.count / cols, cols: cols, data: data)
    }

    static func notes(from hits: [DrumHit], duration: Double) -> [EngineNote] {
        hits.filter { $0.time < duration }.map { hit in
            EngineNote(onset: hit.time, offset: min(hit.time + hitLength, duration), pitch: hit.pitch, program: 0, isDrum: true,
                       instrument: "drums", velocity: hit.velocity, pitchBends: nil)
        }
        .filter { $0.offset > $0.onset }
    }

    func hits(samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [DrumHit] {
        let padded = samples.count < Self.minimumSamples
            ? samples + [Float](repeating: 0, count: Self.minimumSamples - samples.count) : samples
        let plan = Self.chunks(sampleCount: padded.count)
        guard !plan.isEmpty else { return [] }
        let session = try DrumOnnxSession(modelURL: modelURL, spec: spec, threads: threads)
        var answers: [[Matrix]] = Array(repeating: [], count: spec.outputNames.count)
        for (index, chunk) in plan.enumerated() {
            try Task.checkCancellation()
            let outputs = try session.run(samples: Array(padded[chunk.input]))
            for (slot, matrix) in outputs.enumerated() { answers[slot].append(matrix) }
            progress(Double(index + 1) / Double(plan.count))
        }
        let joined = answers.map { Self.assemble($0, chunks: plan) }
        switch spec.decoder {
        case .adtof: return DrumNotes.decodeADTOF(joined[0])
        case .oaf: return DrumNotes.decodeOaF(onset: joined[0], velocity: joined[1])
        }
    }

    func notes(samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [EngineNote] {
        let duration = Double(samples.count) / Self.sampleRate
        return Self.notes(from: try hits(samples: samples, progress: progress), duration: duration)
    }

    /// Same event stream as the other engines. `samples` are mono 44.1 kHz. The hits follow once the whole recording is
    /// decoded, because the peak picking looks across chunk borders.
    func stream(samples: [Float]) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let device = EngineDevice(index: 0, name: "ONNX Runtime (CPU)", backend: "ONNX", integrated: nil, memoryTotal: nil)
                    let pieces = Self.chunks(sampleCount: samples.count).count
                    let steps = self.separator.map { _ in DrumSeparator.starts(sampleCount: samples.count).count } ?? 0
                    continuation.yield(.ready(device: device, chunks: pieces + steps))
                    var audio = samples
                    if let separator = self.separator {
                        audio = try separator.separate(samples: samples) { p in
                            continuation.yield(.update(progress: p * Self.separationShare, finalizedThrough: 0, notes: []))
                        }
                    }
                    let base = self.separator == nil ? 0 : Self.separationShare
                    let notes = try self.notes(samples: audio) { p in
                        continuation.yield(.update(progress: base + p * (0.95 - base), finalizedThrough: 0, notes: []))
                    }
                    continuation.yield(.update(progress: 1, finalizedThrough: Double(samples.count) / Self.sampleRate, notes: notes))
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
