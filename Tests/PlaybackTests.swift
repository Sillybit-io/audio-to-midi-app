import Foundation
import Testing
@testable import SillyMIDITools

@MainActor
struct PlaybackTests {
    @Test func programMappingCoversAllGroups() {
        for program in 0...127 {
            let p = PlaybackEngine.patch(program: program, isDrum: false)
            #expect(Int(p.program) == program && p.bankMSB == 0x79)
        }
        let drums = PlaybackEngine.patch(program: 128, isDrum: true)
        #expect(drums.program == 0 && drums.bankMSB == 0x78)
    }

    @Test func beatConversion() {
        #expect(PlaybackEngine.beats(forSeconds: 1.5) == 3)
    }

    @Test func offlineRenderProducesSound() async throws {
        let note = NoteEvent(onset: 0, offset: 0.8, pitch: 60, program: 0, isDrum: false, instrument: "acoustic_piano", velocity: 100, pitchBends: nil)
        let rms = try await PlaybackEngine().renderOffline(notes: [note], seconds: 1)
        #expect(rms > 0.001)
    }

    @Test func offlineRenderOfNothingIsSilent() async throws {
        let rms = try await PlaybackEngine().renderOffline(notes: [], seconds: 0.5)
        #expect(rms < 0.0001)
    }
}
