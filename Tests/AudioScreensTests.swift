import Foundation
import Testing
@testable import SillyMIDITools

@MainActor
struct AudioScreensTests {
    private func makeScreens() -> (screens: AudioScreens, cleanup: () -> Void) {
        let (defaults, cleanup) = scratchDefaults("smt-screens")
        let directory = FileManager.default.temporaryDirectory.appending(path: "smt-screens-\(UUID().uuidString)")
        let screens = AudioScreens {
            AudioScreenModel(document: DocumentModel(), store: ModelStore(directory: directory.appending(path: "models")),
                             session: TranscriptionSession(),
                             access: AccessCoordinator(keychain: KeychainStore(service: "smt-test-\(UUID().uuidString)")),
                             preferences: AppPreferences(defaults: defaults))
        }
        return (screens, cleanup)
    }

    private func open(_ screen: AudioScreenModel, _ url: URL) {
        screen.document.document = AudioDocument(url: url, samples: [0, 0], sampleRate: 1)
    }

    private func startRun(_ screen: AudioScreenModel) {
        screen.session.start { AsyncThrowingStream { _ in } }
    }

    private let first = URL(fileURLWithPath: "/tmp/smt-first.wav")
    private let second = URL(fileURLWithPath: "/tmp/smt-second.wav")

    @Test func openingAnotherFileKeepsARunningTranscriptionGoing() throws {
        let (screens, cleanup) = makeScreens()
        defer { cleanup() }
        let running = screens.current
        open(running, first)
        startRun(running)
        #expect(running.session.isBusy)

        screens.open(second)

        #expect(screens.parked === running)
        #expect(screens.current !== running)
        #expect(running.session.isBusy)
        #expect(screens.transcribingURL == first)
        running.cancel()
    }

    @Test func aRunningFileBlocksAnotherRunUntilItEnds() throws {
        let (screens, cleanup) = makeScreens()
        defer { cleanup() }
        let running = screens.current
        open(running, first)
        startRun(running)
        screens.open(second)

        let other = screens.current
        open(other, second)
        #expect(other.otherRunInProgress())
        #expect(other.canStart == false)
        #expect(other.startBlocker != nil)

        running.cancel()
        #expect(other.otherRunInProgress() == false)
    }

    @Test func openingTheFileAgainBringsItsRunBack() throws {
        let (screens, cleanup) = makeScreens()
        defer { cleanup() }
        let running = screens.current
        open(running, first)
        startRun(running)
        screens.open(second)
        open(screens.current, second)

        screens.open(first)

        #expect(screens.current === running)
        #expect(screens.parked == nil)
        #expect(running.session.isBusy)
        running.cancel()
    }

    @Test func anIdleScreenIsReusedForTheNextFile() throws {
        let (screens, cleanup) = makeScreens()
        defer { cleanup() }
        let idle = screens.current
        open(idle, first)

        screens.open(second)

        #expect(screens.current === idle)
        #expect(screens.parked == nil)
        #expect(screens.transcribingURL == nil)
    }

    @Test func aFinishedParkedScreenWaitsForItsFileUntilAnotherRunNeedsTheSlot() async throws {
        let (screens, cleanup) = makeScreens()
        defer { cleanup() }
        let first = screens.current
        open(first, self.first)
        startRun(first)
        screens.open(second)
        open(screens.current, second)

        first.cancel()
        #expect(screens.parked === first)
        #expect(screens.transcribingURL == nil)
        #expect(screens.current.otherRunInProgress() == false)
    }

    @Test func fileKindsAreToldApart() {
        func kind(_ name: String) -> AudioDocument.Kind { AudioDocument.kind(of: URL(fileURLWithPath: "/x/\(name)")) }
        #expect(kind("take.wav") == .audio)
        #expect(kind("take.MP3") == .audio)
        #expect(kind("take.m4a") == .audio)
        #expect(kind("take.ogg") == .audio)
        #expect(kind("song.mid") == .midi)
        #expect(kind("song.midi") == .midi)
        #expect(kind("notes.txt") == .other)
        #expect(kind("picture.png") == .other)
        #expect(kind("folder") == .other)
    }
}
