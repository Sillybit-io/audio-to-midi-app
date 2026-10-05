import CryptoKit
import Foundation
import SwiftMIDIFile
import Testing
@testable import SillyMIDITools

private let notice = "Transcribed with Basic Pitch by Spotify (Apache-2.0)."
private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/BasicPitch")

private func note(_ onset: Double, _ offset: Double, _ pitch: Int) -> NoteEvent {
    NoteEvent(onset: onset, offset: offset, pitch: pitch, program: 0, isDrum: false, instrument: "acoustic_piano", velocity: 90, pitchBends: nil)
}

private func makeRun(_ name: String = "synthetic", model: String? = "basic-pitch") -> TranscriptionWriter.Run {
    let url = URL(fileURLWithPath: "/Audio/\(name).wav")
    return TranscriptionWriter.Run(source: url, sourceID: TranscriptionWriter.sourceIdentifier(for: url, references: []), title: name,
                                   modelID: model, notice: notice, slice: AudioSlice(duration: 3))
}

private func scratchFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "scratch-writer-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    // Directory listings return /private/var/... for a /var/... temporary directory when the app isn't sandboxed, so compare real paths.
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(url.path, &buffer) != nil else { return url }
    return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
}

private func listing(_ folder: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
}

private func sha(_ url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
}

/// A MIDI file as the app would leave it after a transcription (or after the user's edits).
@discardableResult
private func existing(_ name: String, in folder: URL, source: TranscriptionWriter.Run?, edited: Bool = false, partial: Bool = false, pitch: Int = 70) throws -> URL {
    var options = MIDIExportOptions()
    options.provenance = source.map { MIDIProvenance(source: $0.sourceID, modelID: $0.modelID, edited: edited, partial: partial) }
    let url = folder.appending(path: name)
    try MIDIBuilder.build(notes: [note(0, 1, pitch)], options: options).write(to: url)
    return url
}

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
struct TranscriptionWriterTests {
    private let writer = TranscriptionWriter()

    @Test func aCompletedRunIsSavedWithItsSourceModelAndLicenceNotice() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        writer.finish(.done(2), notes: [note(0, 1, 60), note(1, 2, 64)], run: run, folder: folder)

        let url = folder.appending(path: "synthetic.mid")
        #expect(writer.status == .saved(url, partial: false))
        let info = try #require(MIDIImporter.info(at: url))
        #expect(info.noteCount == 2 && info.origin == .fromAudio)
        #expect(info.provenance == MIDIProvenance(source: run.sourceID, modelID: "basic-pitch", edited: false, partial: false))

        let file = try MusicalMIDI1File(data: Data(contentsOf: url))
        let copyrights = file.tracks[0].events.compactMap { event -> String? in
            if case .text(let text) = event.event, text.textType == .copyright { text.text } else { nil }
        }
        #expect(copyrights == [notice])
        #expect(try listing(folder) == ["synthetic.mid"])
    }

    @Test func rerunningReplacesTheEarlierOutputInPlace() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        writer.finish(.done(1), notes: [note(0, 1, 60)], run: run, folder: folder)
        writer.finish(.done(3), notes: [note(0, 1, 60), note(1, 2, 62), note(2, 3, 64)], run: run, folder: folder)

        #expect(try listing(folder) == ["synthetic.mid"])
        #expect(MIDIImporter.info(at: folder.appending(path: "synthetic.mid"))?.noteCount == 3)
    }

    @Test func aFileWithHandEditsIsNeverReplaced() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        let edited = try existing("synthetic.mid", in: folder, source: run, edited: true)
        let before = try sha(edited)

        writer.finish(.done(2), notes: [note(0, 1, 60), note(1, 2, 64)], run: run, folder: folder)
        let second = folder.appending(path: "synthetic 2.mid")
        #expect(writer.status == .saved(second, partial: false))
        #expect(try sha(edited) == before)
        let provenance = try #require(MIDIImporter.info(at: second)?.provenance)
        #expect(!provenance.edited && !provenance.partial && provenance.source == run.sourceID)

        writer.finish(.done(3), notes: [note(0, 1, 60), note(1, 2, 62), note(2, 3, 64)], run: run, folder: folder)
        #expect(try listing(folder) == ["synthetic 2.mid", "synthetic.mid"])
        #expect(MIDIImporter.info(at: second)?.noteCount == 3)
        #expect(try sha(edited) == before)
    }

    @Test func filesThatAreNotThisSourcesOutputKeepTheirNames() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        let imported = try existing("synthetic.mid", in: folder, source: nil)
        let other = try existing("synthetic 2.mid", in: folder, source: makeRun("elsewhere"))
        let unreadable = folder.appending(path: "synthetic 3.mid")
        try Data("not midi".utf8).write(to: unreadable)
        let hashes = try [imported, other, unreadable].map(sha)

        writer.finish(.done(1), notes: [note(0, 1, 60)], run: run, folder: folder)
        #expect(writer.status == .saved(folder.appending(path: "synthetic 4.mid"), partial: false))
        #expect(try [imported, other, unreadable].map(sha) == hashes)
    }

    @Test func aCancelledRunSavesItsPartialNotes() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        let url = folder.appending(path: "synthetic.mid")

        writer.finish(.cancelled, notes: [note(0, 1, 60)], run: run, folder: folder)
        #expect(writer.status == .saved(url, partial: true))
        #expect(MIDIImporter.info(at: url)?.provenance?.partial == true)

        writer.finish(.cancelled, notes: [note(0, 1, 60), note(1, 2, 62)], run: run, folder: folder)
        #expect(MIDIImporter.info(at: url)?.noteCount == 2)
        #expect(try listing(folder) == ["synthetic.mid"])

        writer.finish(.done(3), notes: [note(0, 1, 60), note(1, 2, 62), note(2, 3, 64)], run: run, folder: folder)
        #expect(MIDIImporter.info(at: url)?.provenance?.partial == false)
        #expect(MIDIImporter.info(at: url)?.noteCount == 3)
        #expect(try listing(folder) == ["synthetic.mid"])
    }

    @Test func cancellingARerunNeverErasesAnEarlierCompleteResult() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        writer.finish(.done(2), notes: [note(0, 1, 60), note(1, 2, 64)], run: run, folder: folder)
        let url = folder.appending(path: "synthetic.mid")
        let before = try sha(url)

        writer.finish(.cancelled, notes: [note(0, 1, 72)], run: run, folder: folder)
        #expect(writer.status == .keptPrevious(url))
        #expect(try sha(url) == before)
        #expect(try listing(folder) == ["synthetic.mid"])

        writer.finish(.cancelled, notes: [], run: run, folder: folder)
        #expect(writer.status == .empty)
        #expect(try sha(url) == before)
    }

    @Test func aCancelledRunBesideAnEditedFileGetsItsOwnPartialFile() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        let edited = try existing("synthetic.mid", in: folder, source: run, edited: true)
        let before = try sha(edited)

        writer.finish(.cancelled, notes: [note(0, 1, 60)], run: run, folder: folder)
        let partial = folder.appending(path: "synthetic 2.mid")
        #expect(writer.status == .saved(partial, partial: true))
        #expect(MIDIImporter.info(at: partial)?.provenance?.partial == true)
        #expect(try sha(edited) == before)
    }

    @Test func emptyResultsAndNonTerminalStatesWriteNothing() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        writer.finish(.done(0), notes: [], run: run, folder: folder)
        #expect(writer.status == .empty)
        #expect(try listing(folder).isEmpty)

        writer.reset()
        for state in [TranscriptionSession.State.idle, .loading(0.5), .running, .refining, .failed("The engine hit an internal error.")] {
            writer.finish(state, notes: [note(0, 1, 60)], run: run, folder: folder)
        }
        #expect(writer.status == .idle)
        #expect(try listing(folder).isEmpty)
    }

    @Test func aFailedWriteKeepsThePreviousResultAndCanBeRetried() throws {
        let folder = try scratchFolder()
        let run = makeRun()
        writer.finish(.done(1), notes: [note(0, 1, 60)], run: run, folder: folder)
        let url = folder.appending(path: "synthetic.mid")
        let before = try sha(url)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        writer.finish(.done(2), notes: [note(0, 1, 60), note(1, 2, 64)], run: run, folder: folder)
        guard case .failed(let message) = writer.status else {
            Issue.record("expected a failure, got \(writer.status)")
            return
        }
        #expect(message.contains("synthetic.mid") && message.contains("isn\u{2019}t writable"))
        #expect(try sha(url) == before)
        #expect(try listing(folder) == ["synthetic.mid"])

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        writer.retry(folder: folder)
        #expect(writer.status == .saved(url, partial: false))
        #expect(MIDIImporter.info(at: url)?.noteCount == 2)
    }

    @Test func aFailedWriteLeavesNoEmptyFileBehind() throws {
        let folder = try scratchFolder()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        writer.finish(.done(1), notes: [note(0, 1, 60)], run: makeRun(), folder: folder)
        if case .failed = writer.status {} else { Issue.record("expected a failure, got \(writer.status)") }
        #expect(try listing(folder).isEmpty)
    }

    @Test func noWorkingFolderIsReportedAndTheSaveCanBeRetried() throws {
        let run = makeRun()
        writer.finish(.done(1), notes: [note(0, 1, 60)], run: run, folder: nil)
        #expect(writer.status == .failed("Choose a working folder first."))

        let folder = try scratchFolder()
        writer.retry(folder: folder)
        #expect(writer.status == .saved(folder.appending(path: "synthetic.mid"), partial: false))
    }

    @Test func aReferencedAudioFileIsIdentifiedByItsBookmarkNotItsPath() {
        let url = URL(fileURLWithPath: "/Elsewhere/take.wav")
        let reference = AudioReference(name: "take.wav", lastPath: url.path, bookmark: Data())
        #expect(TranscriptionWriter.sourceIdentifier(for: url, references: [reference]) == "reference:\(reference.id.uuidString)")
        #expect(TranscriptionWriter.sourceIdentifier(for: url, references: []) == url.absoluteString)
    }

    @Test func transcribingTheFixtureSavesALinkedFileAndTellsTheLibrary() async throws {
        let folder = try scratchFolder()
        let wav = fixtures.appendingPathComponent("synthetic.wav")
        let document = DocumentModel()
        document.open(wav)
        for _ in 0..<200 where document.document == nil { try await Task.sleep(for: .milliseconds(50)) }
        #expect(document.document != nil)

        let (defaults, cleanup) = scratchDefaults("smt-writer")
        defer { cleanup() }
        let refreshed = Counter()
        let session = TranscriptionSession()
        let screen = AudioScreenModel(document: document, store: ModelStore(directory: folder.appending(path: "models")), session: session,
                                      access: AccessCoordinator(keychain: KeychainStore(service: "smt-test-\(UUID().uuidString)")),
                                      preferences: AppPreferences(defaults: defaults), destination: { folder },
                                      onSaved: { refreshed.value += 1 })
        screen.selectedModel = "basic-pitch"
        screen.start()
        for _ in 0..<1200 where screen.writer.status == .idle { try await Task.sleep(for: .milliseconds(50)) }

        let url = folder.appending(path: "synthetic.mid")
        #expect(screen.writer.status == .saved(url, partial: false))
        #expect(session.state == .done(session.notes.count))
        let info = try #require(MIDIImporter.info(at: url))
        #expect(info.noteCount > 0 && info.origin == .fromAudio)
        #expect(info.provenance?.source == wav.standardizedFileURL.absoluteString)
        #expect(info.provenance?.modelID == "basic-pitch")
        #expect(refreshed.value == 1)
        #expect(try listing(folder).filter { $0.hasSuffix(".mid") } == ["synthetic.mid"])
    }
}
