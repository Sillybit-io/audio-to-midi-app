import Foundation
import Testing
@testable import SillyMIDITools

@MainActor @Suite(.serialized)
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

    private func sine(rate: Double, seconds: Double) -> [Float] {
        (0..<Int(rate * seconds)).map { 0.5 * Float(sin(2 * .pi * 440 * Double($0) / rate)) }
    }

    /// The original audio can have any sample rate; the engine must play it whatever the output device runs at.
    @Test(arguments: [8000.0, 16000.0, 22050.0, 44100.0, 48000.0, 96000.0])
    func originalAudioPlaysAtAnySampleRate(rate: Double) async throws {
        let playback = PlaybackEngine()
        playback.setOriginal(samples: sine(rate: rate, seconds: 1.5), sampleRate: rate)
        let rms = try await playback.renderOffline(notes: [], seconds: 1)
        #expect(rms > 0.2 && rms < 0.5, "rms \(rms) at \(rate) Hz")
    }

    @Test func notesStillSoundWithAnOriginalLoaded() async throws {
        let playback = PlaybackEngine()
        playback.setOriginal(samples: sine(rate: 48000, seconds: 1.5), sampleRate: 48000)
        playback.mix = 1
        let note = NoteEvent(onset: 0, offset: 0.8, pitch: 60, program: 0, isDrum: false, instrument: "acoustic_piano", velocity: 100, pitchBends: nil)
        let rms = try await playback.renderOffline(notes: [note], seconds: 1)
        #expect(rms > 0.001 && rms < 0.2, "rms \(rms)")
    }

    @Test func loadingTheSameFormatTwiceKeepsTheGraphWorking() async throws {
        let playback = PlaybackEngine()
        playback.setOriginal(samples: sine(rate: 44100, seconds: 1.5), sampleRate: 44100)
        playback.setOriginal(samples: sine(rate: 44100, seconds: 1.5), sampleRate: 44100)
        playback.setOriginal(samples: sine(rate: 48000, seconds: 1.5), sampleRate: 48000)
        let rms = try await playback.renderOffline(notes: [], seconds: 1)
        #expect(rms > 0.2 && rms < 0.5, "rms \(rms)")
    }
}
