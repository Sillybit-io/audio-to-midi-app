import Foundation
import Testing
@testable import SillyMIDITools

struct VelocityEstimatorTests {
    private let rate = 16000.0

    private func tone(_ pitch: Int, amplitude: Float, seconds: Double) -> [Float] {
        let f = 440 * pow(2, Double(pitch - 69) / 12)
        return (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * .pi * f * Double($0) / rate)) }
    }

    private func note(_ onset: Double, _ offset: Double, _ pitch: Int = 60, drum: Bool = false, velocity: Int? = nil) -> NoteEvent {
        NoteEvent(onset: onset, offset: offset, pitch: pitch, program: drum ? 128 : 0, isDrum: drum,
                  instrument: drum ? "drums" : "acoustic_piano", velocity: velocity, pitchBends: nil)
    }

    private func place(_ audio: inout [Float], _ segment: [Float], at seconds: Double) {
        let start = Int(seconds * rate)
        for (i, v) in segment.enumerated() where start + i < audio.count { audio[start + i] += v }
    }

    @Test func louderNotesGetHigherVelocities() {
        var audio = [Float](repeating: 0, count: Int(8 * rate))
        let amplitudes: [Float] = [0.05, 0.1, 0.2, 0.4, 0.8]
        var notes: [NoteEvent] = []
        for (i, a) in amplitudes.enumerated() {
            let t = Double(i) * 1.5
            place(&audio, tone(60, amplitude: a, seconds: 1), at: t)
            notes.append(note(t, t + 1))
        }
        let velocities = VelocityEstimator.estimate(notes: notes, samples: audio, sampleRate: rate).map { $0.velocity! }
        #expect(velocities == velocities.sorted())
        #expect(Set(velocities).count == velocities.count)
        #expect(velocities.first! < 60 && velocities.last! > 100)
        #expect(velocities.allSatisfy { (1...127).contains($0) })
    }

    @Test func steadyPlayingIsNotStretchedIntoDynamics() {
        var audio = [Float](repeating: 0, count: Int(6 * rate))
        var notes: [NoteEvent] = []
        for i in 0..<5 {
            let t = Double(i)
            place(&audio, tone(64, amplitude: 0.3, seconds: 0.8), at: t)
            notes.append(note(t, t + 0.8, 64))
        }
        let velocities = VelocityEstimator.estimate(notes: notes, samples: audio, sampleRate: rate).map { $0.velocity! }
        #expect(velocities.allSatisfy { abs($0 - 80) <= 2 })
    }

    @Test func unrelatedLoudPitchesDoNotMaskTheNote() {
        var audio = [Float](repeating: 0, count: Int(5 * rate))
        place(&audio, tone(60, amplitude: 0.1, seconds: 1), at: 0)
        place(&audio, tone(66, amplitude: 0.9, seconds: 1), at: 0)
        place(&audio, tone(60, amplitude: 0.5, seconds: 1), at: 2)
        place(&audio, tone(60, amplitude: 0.5, seconds: 1), at: 3.5)
        let notes = [note(0, 1, 60), note(2, 3, 60), note(3.5, 4.5, 60), note(0, 1, 66)]
        let out = VelocityEstimator.estimate(notes: notes, samples: audio, sampleRate: rate)
        #expect(out[0].velocity! < out[1].velocity!)
    }

    @Test func drumHitsFollowTheirLoudness() {
        var audio = [Float](repeating: 0, count: Int(4 * rate))
        let amps: [Float] = [0.1, 0.3, 0.9]
        var notes: [NoteEvent] = []
        for (i, a) in amps.enumerated() {
            let t = Double(i)
            place(&audio, (0..<640).map { _ in a * Float.random(in: -1...1) }, at: t)
            notes.append(note(t, t + 0.1, 38, drum: true))
        }
        let v = VelocityEstimator.estimate(notes: notes, samples: audio, sampleRate: rate).map { $0.velocity! }
        #expect(v == v.sorted() && v[0] < v[2])
    }

    @Test func existingVelocitiesAreKeptAndSilenceIsMid() {
        let audio = [Float](repeating: 0, count: Int(3 * rate))
        let out = VelocityEstimator.estimate(notes: [note(0, 1, 60, velocity: 33), note(1, 2, 62)], samples: audio, sampleRate: rate)
        #expect(out[0].velocity == 33)
        #expect(out[1].velocity == 80)
    }

    @Test func notesBeyondTheAudioGetTheMidVelocity() {
        let out = VelocityEstimator.estimate(notes: [note(10, 11)], samples: [Float](repeating: 0, count: 1000), sampleRate: rate)
        #expect(out[0].velocity == 80)
    }
}
