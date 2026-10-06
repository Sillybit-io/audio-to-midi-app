import Foundation
import Testing
@testable import SillyMIDITools

private let fake = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/fake-engine.sh")

private func collect(_ stream: AsyncThrowingStream<EngineEvent, Error>) async -> (events: [EngineEvent], error: Error?) {
    var events: [EngineEvent] = []
    do { for try await e in stream { events.append(e) } } catch { return (events, error) }
    return (events, nil)
}

@Suite(.serialized)
struct EngineProcessTests {
    private func stream(_ engine: EngineProcess) -> AsyncThrowingStream<EngineEvent, Error> {
        engine.transcribe(model: URL(fileURLWithPath: "/tmp/none.gguf"), samples: [0, 0, 0], device: "cpu", threads: 1, instruments: [])
    }

    @Test func theEnginesErrorOutputGoesToTheDebugLog() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "smt-log-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let log = DebugLog()
        log.configure(enabled: true, folder: folder)
        let engine = EngineProcess(executable: fake, environment: ["FAKE_STDERR": "ggml: falling back to CPU"], log: log)

        _ = try await engine.devices()

        let file = try #require(log.currentFile)
        var text = ""
        for _ in 0..<50 {
            text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("ggml") { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(text.contains(#/\] engine +engine: ggml: falling back to CPU/#))
    }

    @Test func writingToAnEngineThatHasExitedFailsInsteadOfEndingTheApp() throws {
        let pipe = EngineProcess.makeInputPipe()
        try pipe.fileHandleForReading.close()
        #expect(throws: (any Error).self) { try pipe.fileHandleForWriting.write(contentsOf: Data("\n".utf8)) }
    }

    @Test func listsDevicesAndInstruments() async throws {
        let engine = EngineProcess(executable: fake)
        #expect(try await engine.devices().first?.backend == "CPU")
        #expect(try await engine.instruments().count == 2)
    }

    @Test func eventsArriveInOrder() async {
        let result = await collect(stream(EngineProcess(executable: fake)))
        #expect(result.error == nil)
        #expect(result.events.first == .load(progress: 0.5))
        #expect(result.events.last == .done(noteCount: 3))
        #expect(result.events.filter { if case .update = $0 { true } else { false } }.count == 3)
    }

    @Test func crashKeepsEarlierNotesAndSurfacesError() async {
        let result = await collect(stream(EngineProcess(executable: fake, environment: ["FAKE_MODE": "crash"])))
        #expect(result.error as? EngineProcessError != nil)
        #expect(result.events.filter { if case .update = $0 { true } else { false } }.count == 2)
    }

    @Test func cancelReachesTheEngineWithinFiveSeconds() async throws {
        let mark = FileManager.default.temporaryDirectory.appendingPathComponent("mark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: mark) }
        let engine = EngineProcess(executable: fake, environment: ["FAKE_MARK": mark.path])
        let s = stream(engine)
        let task = Task { for try await _ in s {} }
        try await Task.sleep(for: .seconds(1))
        task.cancel()
        _ = await task.result
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: mark.path), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(FileManager.default.fileExists(atPath: mark.path))
    }

    @Test func temporaryAudioIsRemoved() async {
        let before = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).filter { $0.hasPrefix("smt-") }.count) ?? 0
        _ = await collect(stream(EngineProcess(executable: fake)))
        let after = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory()).filter { $0.hasPrefix("smt-") }.count) ?? 0
        #expect(after <= before)
    }
}
