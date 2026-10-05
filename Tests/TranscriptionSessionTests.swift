import Foundation
import Testing
@testable import SillyMIDITools

@MainActor
struct TranscriptionSessionTests {
    private nonisolated static func note(_ p: Int) -> EngineNote {
        EngineNote(onset: 0, offset: 1, pitch: p, program: 0, isDrum: false, instrument: "acoustic_piano")
    }

    private func settle(_ session: TranscriptionSession) async {
        for _ in 0..<100 where session.isBusy { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func movesThroughStatesAndCollectsNotes() async {
        let session = TranscriptionSession()
        session.start {
            AsyncThrowingStream { c in
                c.yield(.load(progress: 0.3))
                c.yield(.ready(device: EngineDevice(index: 0, name: "CPU", backend: "CPU", integrated: nil, memoryTotal: nil), chunks: 2))
                c.yield(.update(progress: 0.5, finalizedThrough: 5, notes: [Self.note(60)]))
                c.yield(.update(progress: 1, finalizedThrough: 10, notes: [Self.note(62)]))
                c.yield(.done(noteCount: 2))
                c.finish()
            }
        }
        await settle(session)
        #expect(session.state == .done(2))
        #expect(session.notes.map(\.pitch) == [60, 62])
        #expect(session.deviceName == "CPU")
    }

    @Test func refineRunsAfterDoneAndKeepsTheCount() async {
        let session = TranscriptionSession()
        session.start(refine: { notes in notes.map { var n = $0; n.velocity = 99; return n } }) {
            AsyncThrowingStream { c in
                c.yield(.update(progress: 1, finalizedThrough: 5, notes: [Self.note(60)]))
                c.yield(.done(noteCount: 1))
                c.finish()
            }
        }
        await settle(session)
        #expect(session.state == .done(1))
        #expect(session.notes.first?.velocity == 99)
    }

    @Test func etaFromTwoUpdates() {
        let eta = TranscriptionSession.eta(previous: (0.25, 100), progress: 0.5, time: 110)
        #expect(eta == 20)
        #expect(TranscriptionSession.eta(previous: nil, progress: 0.5, time: 110) == nil)
    }

    @Test func engineCancelledErrorEndsCancelled() async {
        let session = TranscriptionSession()
        session.start {
            AsyncThrowingStream { c in
                c.yield(.error(code: "Cancelled", message: "x"))
                c.finish()
            }
        }
        await settle(session)
        #expect(session.state == .cancelled)
    }

    @Test func crashKeepsNotesAndFails() async {
        let session = TranscriptionSession()
        session.start {
            AsyncThrowingStream { c in
                c.yield(.update(progress: 0.2, finalizedThrough: 5, notes: [Self.note(60)]))
                c.finish(throwing: EngineProcessError.stoppedUnexpectedly(9))
            }
        }
        await settle(session)
        guard case .failed = session.state else { Issue.record("expected failed"); return }
        #expect(session.notes.count == 1)
    }

    @Test func cancelKeepsPartialNotes() async {
        let session = TranscriptionSession()
        session.start {
            AsyncThrowingStream { c in
                c.yield(.update(progress: 0.2, finalizedThrough: 5, notes: [Self.note(60)]))
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
        session.cancel()
        #expect(session.state == .cancelled)
        #expect(session.notes.count == 1)
    }

    @Test func clearForgetsTheResultForTheNextFile() async {
        let session = TranscriptionSession()
        session.start { AsyncThrowingStream { c in
            c.yield(.update(progress: 1, finalizedThrough: 3, notes: [Self.note(60)]))
            c.yield(.done(noteCount: 1))
            c.finish()
        } }
        await settle(session)
        #expect(session.state == .done(1))
        session.clear()
        #expect(session.state == .idle && session.notes.isEmpty && session.progress == 0 && session.finalizedThrough == 0)

        session.start { AsyncThrowingStream { c in c.yield(.update(progress: 0.2, finalizedThrough: 1, notes: [Self.note(62)])) } }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(session.isBusy)
        session.clear()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(session.state == .idle && session.notes.isEmpty)
    }

    @Test func secondStartWhileBusyIsIgnored() async {
        let session = TranscriptionSession()
        session.start { AsyncThrowingStream { _ in } }
        session.start { AsyncThrowingStream { c in c.yield(.done(noteCount: 9)); c.finish() } }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(session.isBusy)
        session.cancel()
    }
}
