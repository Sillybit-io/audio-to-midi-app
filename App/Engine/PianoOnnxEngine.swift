import Foundation
@preconcurrency import OnnxRuntimeBindings

enum PianoOnnxError: LocalizedError {
    case modelUnavailable(String)
    case unexpectedOutput

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): "The piano model could not be loaded: \(reason)"
        case .unexpectedOutput: "The piano model returned output of an unexpected shape."
        }
    }
}

/// One ONNX Runtime session over the piano model. Used from a single task at a time.
final class PianoOnnxSession: @unchecked Sendable {
    typealias Outputs = (onset: [Float], offset: [Float], frame: [Float], velocity: [Float])

    static let outputNames = ["reg_onset_output", "reg_offset_output", "frame_output", "velocity_output"]

    private let env: ORTEnv
    private let session: ORTSession

    init(modelURL: URL, threads: Int) throws {
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            func make(_ level: ORTGraphOptimizationLevel) throws -> ORTSession {
                let options = try ORTSessionOptions()
                try options.setGraphOptimizationLevel(level)
                if threads > 0 { try options.setIntraOpNumThreads(Int32(threads)) }
                return try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: options)
            }
            // Some ONNX Runtime releases mis-fuse this graph while optimising it; the unoptimised graph is correct.
            let session: ORTSession
            do { session = try make(.all) } catch { session = try make(.none) }
            self.env = env
            self.session = session
        } catch {
            throw PianoOnnxError.modelUnavailable(error.localizedDescription)
        }
    }

    func run(segment: [Float]) throws -> Outputs {
        let data = NSMutableData(bytes: segment, length: segment.count * MemoryLayout<Float>.size)
        let input = try ORTValue(tensorData: data, elementType: .float, shape: [1, NSNumber(value: segment.count)])
        let outputs = try session.run(withInputs: ["waveform": input], outputNames: Set(Self.outputNames), runOptions: nil)

        func floats(_ name: String) throws -> [Float] {
            guard let value = outputs[name] else { throw PianoOnnxError.unexpectedOutput }
            let bytes = try value.tensorData()
            let expected = PianoOnnxEngine.framesPerSegment * PianoOnnxNotes.classes
            guard bytes.length == expected * MemoryLayout<Float>.size else { throw PianoOnnxError.unexpectedOutput }
            return Data(bytes).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        return (try floats("reg_onset_output"), try floats("reg_offset_output"), try floats("frame_output"), try floats("velocity_output"))
    }
}

/// High-resolution piano transcription (Kong et al., ByteDance) on ONNX Runtime. Windowing and merging follow
/// `PianoTranscription.enframe` and `deframe` of piano_transcription_inference: 10 s segments, 5 s hop.
struct PianoOnnxEngine: Sendable {
    static let sampleRate = 16000.0
    static let segmentSamples = 160_000
    static let framesPerSegment = 1001

    var modelURL: URL
    var threads = 0

    /// How many segments, half a segment apart, cover `sampleCount` samples once they are padded to whole segments.
    static func segmentCount(sampleCount: Int) -> Int {
        guard sampleCount > 0 else { return 0 }
        let padded = (sampleCount + segmentSamples - 1) / segmentSamples * segmentSamples
        return (padded - segmentSamples) / (segmentSamples / 2) + 1
    }

    /// Segment `index`: `segmentSamples` samples starting `index` half segments in, zero past the end of the audio.
    /// Segments are cut one at a time, so a long recording is never held twice.
    static func segment(_ index: Int, of samples: [Float]) -> [Float] {
        let start = index * (segmentSamples / 2)
        var segment = start < samples.count ? Array(samples[start..<min(samples.count, start + segmentSamples)]) : []
        segment += repeatElement(0, count: segmentSamples - segment.count)
        return segment
    }

    /// The rows of segment `index` (of `count`) that go into the merged matrix: the last frame of every segment is
    /// dropped, then the middle half is kept (the first keeps its start, the last its end). A lone segment is kept whole.
    static func keptRows(segment index: Int, of count: Int) -> Range<Int> {
        guard count > 1 else { return 0..<framesPerSegment }
        let kept = framesPerSegment - 1
        return (index == 0 ? 0 : kept / 4)..<(index == count - 1 ? kept : kept * 3 / 4)
    }

    /// Appends the kept rows of segment `index` (of `count`) to `merged`.
    static func appendKept(_ part: [Float], segment index: Int, of count: Int, cols: Int, to merged: inout [Float]) {
        let rows = keptRows(segment: index, of: count)
        merged += part[(rows.lowerBound * cols)..<(rows.upperBound * cols)]
    }

    /// Joins per-segment frame matrices (each `framesPerSegment` rows) into one matrix.
    static func deframe(_ parts: [[Float]], cols: Int) -> [Float] {
        var merged: [Float] = []
        for (index, part) in parts.enumerated() { appendKept(part, segment: index, of: parts.count, cols: cols, to: &merged) }
        return merged
    }

    static func notes(onset: Matrix, offset: Matrix, frame: Matrix, velocity: Matrix, duration: Double) -> [EngineNote] {
        PianoOnnxNotes.decode(onset: onset, offset: offset, frame: frame, velocity: velocity)
            .filter { $0.onset < duration }
            .map { note in
                EngineNote(onset: note.onset, offset: min(note.offset, duration), pitch: note.pitch, program: 0, isDrum: false,
                           instrument: "acoustic_piano", velocity: min(127, max(1, note.velocity)), pitchBends: nil)
            }
            .filter { $0.offset > $0.onset }
            .sorted { ($0.onset, $0.pitch) < ($1.onset, $1.pitch) }
    }

    func notes(samples: [Float], progress: (Double) -> Void = { _ in }) throws -> [EngineNote] {
        let count = Self.segmentCount(sampleCount: samples.count)
        guard count > 0 else { return [] }
        let session = try PianoOnnxSession(modelURL: modelURL, threads: threads)
        let cols = PianoOnnxNotes.classes
        let rows = (0..<count).reduce(0) { $0 + Self.keptRows(segment: $1, of: count).count }
        var onset: [Float] = [], offset: [Float] = [], frame: [Float] = [], velocity: [Float] = []
        onset.reserveCapacity(rows * cols)
        offset.reserveCapacity(rows * cols)
        frame.reserveCapacity(rows * cols)
        velocity.reserveCapacity(rows * cols)
        for index in 0..<count {
            try Task.checkCancellation()
            // ONNX Runtime hands its results back autoreleased, and this loop never suspends, so without a pool every
            // segment's output tensors stay alive until the run ends: about 2 MB a segment, 240 MB for ten minutes.
            try autoreleasepool {
                let out = try session.run(segment: Self.segment(index, of: samples))
                Self.appendKept(out.onset, segment: index, of: count, cols: cols, to: &onset)
                Self.appendKept(out.offset, segment: index, of: count, cols: cols, to: &offset)
                Self.appendKept(out.frame, segment: index, of: count, cols: cols, to: &frame)
                Self.appendKept(out.velocity, segment: index, of: count, cols: cols, to: &velocity)
            }
            progress(Double(index + 1) / Double(count))
        }
        func matrix(_ data: [Float]) -> Matrix { Matrix(rows: data.count / cols, cols: cols, data: data) }
        return Self.notes(onset: matrix(onset), offset: matrix(offset), frame: matrix(frame), velocity: matrix(velocity),
                          duration: Double(samples.count) / Self.sampleRate)
    }

    /// Same event stream as the sidecar, so the session treats every engine alike. `samples` are mono 16 kHz.
    func stream(samples: [Float]) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached {
                do {
                    let device = EngineDevice(index: 0, name: "ONNX Runtime (CPU)", backend: "ONNX", integrated: nil, memoryTotal: nil)
                    continuation.yield(.ready(device: device, chunks: Self.segmentCount(sampleCount: samples.count)))
                    // Segments are reported as they finish; the notes follow once the whole recording has been merged,
                    // because the post-processing looks across segment borders.
                    let notes = try self.notes(samples: samples) { p in
                        continuation.yield(.update(progress: p * 0.95, finalizedThrough: 0, notes: []))
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
