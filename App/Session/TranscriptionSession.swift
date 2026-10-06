import Foundation
import Observation

@MainActor @Observable
final class TranscriptionSession {
    enum State: Equatable {
        case idle
        case loading(Double)
        case running
        case refining
        case done(Int)
        case failed(String)
        case cancelled

        /// The state without its progress, for the debug log.
        var stage: String {
            switch self {
            case .idle: "idle"
            case .loading: "loading the model"
            case .running: "transcribing"
            case .refining: "estimating velocity"
            case .done(let count): "done, \(count) notes"
            case .failed(let message): "failed: \(message)"
            case .cancelled: "cancelled"
            }
        }
    }

    private(set) var state: State = .idle {
        didSet {
            guard DebugLog.shared.isEnabled, oldValue.stage != state.stage else { return }
            debugLog(.transcription, "\"\(label)\": \(state.stage) (\(notes.count) notes so far, the app uses \(DebugLog.footprint()))")
        }
    }
    /// The file being transcribed, for the debug log.
    @ObservationIgnored var label = ""
    private(set) var notes: [NoteEvent] = []
    private(set) var finalizedThrough = 0.0
    private(set) var progress = 0.0
    private(set) var eta: TimeInterval?
    private(set) var deviceName: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var last: (progress: Double, time: TimeInterval)?
    @ObservationIgnored private var doneCount: Int?
    @ObservationIgnored private var refine: (@Sendable ([NoteEvent]) async -> [NoteEvent])?
    @ObservationIgnored var now: @Sendable () -> TimeInterval = { Date.timeIntervalSinceReferenceDate }

    var isBusy: Bool {
        switch state {
        case .loading, .running, .refining: true
        default: false
        }
    }

    /// Seconds remaining, from the progress made between the last two updates.
    nonisolated static func eta(previous: (progress: Double, time: TimeInterval)?, progress: Double, time: TimeInterval) -> TimeInterval? {
        guard let previous, progress > previous.progress, time > previous.time else { return nil }
        return (1 - progress) * (time - previous.time) / (progress - previous.progress)
    }

    nonisolated static func message(forCode code: String) -> String {
        switch code {
        case "FileNotFound": "The model file was not found. Download it again from the model list."
        case "InvalidCheckpoint": "The model file is damaged or not a MuScriptor model."
        case "UnsupportedArch", "UnsupportedCheckpointVersion": "This model version is not supported by the engine."
        case "OutOfMemory": "The model needs more memory than is available. Try a smaller model."
        case "DeviceUnavailable": "The chosen device is not available. Try CPU or Auto."
        case "ContextOverflow": "The audio was too dense to transcribe in one pass."
        case "InvalidArgument": "The engine rejected its settings."
        default: "The engine hit an internal error."
        }
    }

    /// `refine`, when given, post-processes the finished notes (for example velocity estimation).
    func start(refine: (@Sendable ([NoteEvent]) async -> [NoteEvent])? = nil,
               _ make: @escaping @Sendable () async throws -> AsyncThrowingStream<EngineEvent, Error>) {
        guard !isBusy else { return }
        self.refine = refine
        doneCount = nil
        notes = []
        finalizedThrough = 0
        progress = 0
        eta = nil
        last = nil
        state = .loading(0)
        task = Task { [weak self] in
            do {
                let stream = try await make()
                for try await event in stream { self?.handle(event) }
                await self?.finishRun()
            } catch is CancellationError {
            } catch {
                debugLog(.transcription, "The run stopped with an error: \(String(reflecting: error))")
                self?.fail(error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard isBusy else { return }
        task?.cancel()
        state = .cancelled
    }

    /// Forgets the last result, for when a different audio file is opened. A run still going is stopped.
    func clear() {
        task?.cancel()
        task = nil
        doneCount = nil
        notes = []
        finalizedThrough = 0
        progress = 0
        eta = nil
        last = nil
        state = .idle
    }

    private func finishRun() async {
        guard isBusy else { return }
        guard let count = doneCount else {
            state = .failed(EngineProcessError.stoppedUnexpectedly(0).localizedDescription)
            return
        }
        if let refine {
            state = .refining
            let refined = await refine(notes)
            guard state == .refining else { return }
            notes = refined
        }
        state = .done(count)
    }

    private func fail(_ message: String) {
        if isBusy { state = .failed(message) }
    }

    private func handle(_ event: EngineEvent) {
        guard isBusy else { return }
        switch event {
        case .load(let p): state = .loading(p)
        case .ready(let device, _):
            deviceName = device.name
            state = .running
        case .update(let p, let through, let new):
            let t = now()
            eta = Self.eta(previous: last, progress: p, time: t)
            last = (p, t)
            progress = p
            finalizedThrough = through
            notes += new.map {
                NoteEvent(onset: $0.onset, offset: $0.offset, pitch: $0.pitch, program: $0.program,
                          isDrum: $0.isDrum, instrument: $0.instrument, velocity: $0.velocity, pitchBends: $0.pitchBends)
            }
        case .done(let count):
            progress = 1
            eta = nil
            doneCount = count
        case .error(let code, _):
            state = code == "Cancelled" ? .cancelled : .failed(Self.message(forCode: code))
        case .devices, .instruments: break
        }
    }
}
