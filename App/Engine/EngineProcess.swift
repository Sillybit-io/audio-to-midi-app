import Foundation
import Synchronization

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
    /// Records the engine's starts, exits and error output.
    var log: DebugLog = .shared

    private func makeProcess(_ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty { process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 } }
        return process
    }

    /// The engine's error output goes to the debug log line by line while it is on, and is dropped otherwise.
    private func errorOutput() -> Any {
        guard log.isEnabled else { return FileHandle.nullDevice }
        let pipe = Pipe()
        let lines = LineSplitter { [log] line in log.log(.engine, "engine: \(line)") }
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                lines.finish()
            } else {
                lines.add(data)
            }
        }
        return pipe
    }

    /// A pipe for the engine's stdin. Writing to it after the engine has exited fails, instead of raising SIGPIPE,
    /// which would end the app without a crash report.
    static func makeInputPipe() -> Pipe {
        let pipe = Pipe()
        _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        return pipe
    }

    static func describeExit(_ process: Process) -> String {
        process.terminationReason == .uncaughtSignal ? "was killed by signal \(process.terminationStatus)" : "exited with status \(process.terminationStatus)"
    }

    private func firstEvent(_ arguments: [String]) async throws -> EngineEvent {
        try await Task.detached {
            let process = makeProcess(arguments)
            let out = Pipe()
            process.standardOutput = out
            process.standardError = errorOutput()
            try process.run()
            let data = try out.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            if process.terminationStatus != 0 { log.log(.engine, "The engine's \(arguments.joined(separator: " ")) \(Self.describeExit(process)).") }
            let line = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
            do {
                return try EngineEvent.decode(line: line)
            } catch {
                log.log(.engine, "The engine's \(arguments.joined(separator: " ")) answered something unreadable: \(line.prefix(300))")
                throw EngineProcessError.badOutput(line)
            }
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
            let log = log
            let run = RunHandle(log: log)
            let task = Task.detached {
                let audio = FileManager.default.temporaryDirectory.appendingPathComponent("smt-\(UUID().uuidString).f32")
                defer { try? FileManager.default.removeItem(at: audio) }
                do {
                    try samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: audio)
                    var args = ["transcribe", "--model", model.path, "--audio", audio.path, "--device", device, "--threads", String(threads)]
                    if !instruments.isEmpty { args += ["--instruments", instruments.joined(separator: ",")] }
                    let process = makeProcess(args)
                    let out = Pipe()
                    let input = Self.makeInputPipe()
                    process.standardOutput = out
                    process.standardInput = input
                    process.standardError = errorOutput()
                    run.attach(process, input: input.fileHandleForWriting)
                    try process.run()
                    log.log(.engine, "Engine started, pid \(process.processIdentifier): \(args.joined(separator: " "))")
                    var sawError = false
                    for try await line in out.fileHandleForReading.bytes.lines {
                        let event: EngineEvent
                        do { event = try EngineEvent.decode(line: line) } catch { throw EngineProcessError.badOutput(line) }
                        if case .error = event { sawError = true }
                        continuation.yield(event)
                    }
                    process.waitUntilExit()
                    log.log(.engine, "Engine \(Self.describeExit(process)).")
                    if process.terminationStatus != 0 && !sawError {
                        throw EngineProcessError.stoppedUnexpectedly(process.terminationStatus)
                    }
                    continuation.finish()
                } catch {
                    log.log(.engine, "Engine run ended with an error: \(String(reflecting: error))")
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
    private let log: DebugLog
    private var process: Process?
    private var input: FileHandle?

    init(log: DebugLog) {
        self.log = log
    }

    func attach(_ process: Process, input: FileHandle) {
        lock.withLock { self.process = process; self.input = input }
    }

    func cancel() {
        let (process, input) = lock.withLock { (self.process, self.input) }
        do {
            try input?.write(contentsOf: Data("\n".utf8))
            log.log(.engine, "Asked the engine to stop.")
        } catch {
            log.log(.engine, "Couldn\u{2019}t ask the engine to stop (it had probably exited): \(error.localizedDescription)")
        }
        let log = log
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            if process?.isRunning == true {
                log.log(.engine, "The engine didn\u{2019}t stop within 5 s; terminating it.")
                process?.terminate()
            }
        }
    }
}

/// Turns chunks of process output into whole lines.
private final class LineSplitter: Sendable {
    private let buffer = Mutex(Data())
    private let emit: @Sendable (String) -> Void

    init(_ emit: @escaping @Sendable (String) -> Void) {
        self.emit = emit
    }

    func add(_ data: Data) {
        let lines = buffer.withLock { buffer in
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return lines
        }
        lines.forEach(emit)
    }

    func finish() {
        let rest = buffer.withLock { buffer in
            defer { buffer = Data() }
            return buffer
        }
        if !rest.isEmpty { emit(String(decoding: rest, as: UTF8.self)) }
    }
}
