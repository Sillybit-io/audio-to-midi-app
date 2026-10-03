import Foundation

enum EngineProcessError: LocalizedError, Equatable {
    case stoppedUnexpectedly(Int32)
    case badOutput(String)

    var errorDescription: String? {
        switch self {
        case .stoppedUnexpectedly: "The transcription engine stopped unexpectedly."
        case .badOutput(let line): "The transcription engine sent something unreadable: \(line)"
        }
    }
}

/// Launches the sidecar and turns its stdout lines into events.
struct EngineProcess: Sendable {
    let executable: URL
    var environment: [String: String] = [:]

    private func makeProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 } }
        return process
    }

    private func firstEvent(_ arguments: [String]) async throws -> EngineEvent {
        try await Task.detached {
            let process = makeProcess(arguments)
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = try out.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
            do { return try EngineEvent.decode(line: line) } catch { throw EngineProcessError.badOutput(line) }
        }.value
    }

    func devices() async throws -> [EngineDevice] {
        if case .devices(_, let list) = try await firstEvent(["devices"]) { return list }
        return []
    }

    func instruments() async throws -> [EngineInstrument] {
        if case .instruments(let list) = try await firstEvent(["instruments"]) { return list }
        return []
    }

    /// Streams events for one run. Cancelling the consuming task sends the engine a stdin line,
    /// then terminates it after five seconds. The temporary audio file is removed on every exit path.
    func transcribe(model: URL, samples: [Float], device: String, threads: Int, instruments: [String]) -> AsyncThrowingStream<EngineEvent, Error> {
        AsyncThrowingStream { continuation in
            let run = RunHandle()
            let task = Task.detached {
                let audio = FileManager.default.temporaryDirectory.appendingPathComponent("smt-\(UUID().uuidString).f32")
                defer { try? FileManager.default.removeItem(at: audio) }
                do {
                    try samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: audio)
                    var args = ["transcribe", "--model", model.path, "--audio", audio.path, "--device", device, "--threads", String(threads)]
                    if !instruments.isEmpty { args += ["--instruments", instruments.joined(separator: ",")] }
                    let process = makeProcess(args)
                    let out = Pipe()
                    let input = Pipe()
                    process.standardOutput = out
                    process.standardInput = input
                    process.standardError = FileHandle.nullDevice
                    run.attach(process, input: input.fileHandleForWriting)
                    try process.run()
                    var sawError = false
                    for try await line in out.fileHandleForReading.bytes.lines {
                        let event: EngineEvent
                        do { event = try EngineEvent.decode(line: line) } catch { throw EngineProcessError.badOutput(line) }
                        if case .error = event { sawError = true }
                        continuation.yield(event)
                    }
                    process.waitUntilExit()
                    if process.terminationStatus != 0 && !sawError {
                        throw EngineProcessError.stoppedUnexpectedly(process.terminationStatus)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                if case .cancelled = termination { run.cancel() }
                _ = task
            }
        }
    }
}

private final class RunHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?

    func attach(_ process: Process, input: FileHandle) {
        lock.withLock { self.process = process; self.input = input }
    }

    func cancel() {
        let (process, input) = lock.withLock { (self.process, self.input) }
        try? input?.write(contentsOf: Data("\n".utf8))
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process?.isRunning == true { process?.terminate() }
        }
    }
}
