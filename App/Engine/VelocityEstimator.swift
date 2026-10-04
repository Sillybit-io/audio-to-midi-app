import Foundation

/// Estimates MIDI velocities from the audio for notes that carry none (MuScriptor does not predict them).
///
/// Pitched notes: onset energy at the note's fundamental and first harmonics, measured over a short
/// Hann-windowed slice starting at the onset. Drums: RMS of the first 40 ms. Energies are converted to dB
/// and mapped to 40...120 around each instrument's median, spanning at least 12 dB so a steady performance
/// is not stretched into false dynamics.
enum VelocityEstimator {
    static let windowSeconds = 0.128
    static let drumSeconds = 0.04
    static let harmonics = 4
    static let centreVelocity = 80.0
    static let halfRangeVelocity = 40.0
    static let minimumHalfSpanDB = 6.0
    static let minimumGroupSize = 4

    static func estimate(notes: [NoteEvent], samples: [Float], sampleRate: Double) -> [NoteEvent] {
        let energies = notes.map { energyDB($0, samples: samples, sampleRate: sampleRate) }
        let pooled = Stats(energies.compactMap { $0 })

        var byGroup: [String: [Double]] = [:]
        for (note, energy) in zip(notes, energies) {
            if let energy { byGroup[group(note), default: []].append(energy) }
        }
        let stats = byGroup.mapValues { values in values.count >= minimumGroupSize ? Stats(values) : pooled }

        return zip(notes, energies).map { note, energy in
            guard note.velocity == nil else { return note }
            var out = note
            let s = stats[group(note)] ?? pooled
            if let energy, let s {
                let unit = max(-1, min(1, (energy - s.median) / s.halfSpan))
                out.velocity = max(1, min(127, Int((centreVelocity + halfRangeVelocity * unit).rounded())))
            } else {
                out.velocity = Int(centreVelocity)
            }
            return out
        }
    }

    private static func group(_ note: NoteEvent) -> String { note.isDrum ? "drums" : note.instrument }

    private struct Stats {
        let median: Double
        let halfSpan: Double

        init?(_ values: [Double]) {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            func percentile(_ p: Double) -> Double { sorted[Int((Double(sorted.count - 1) * p).rounded())] }
            median = percentile(0.5)
            halfSpan = max((percentile(0.95) - percentile(0.05)) / 2, VelocityEstimator.minimumHalfSpanDB)
        }
    }

    /// Onset loudness in dB, or nil when the note lies outside the audio.
    static func energyDB(_ note: NoteEvent, samples: [Float], sampleRate: Double) -> Double? {
        let start = Int((note.onset * sampleRate).rounded())
        guard start >= 0, start < samples.count else { return nil }
        if note.isDrum {
            let length = min(Int(drumSeconds * sampleRate), samples.count - start)
            guard length >= 16 else { return nil }
            var sum = 0.0
            for i in 0..<length { sum += Double(samples[start + i]) * Double(samples[start + i]) }
            return 10 * log10(sum / Double(length) + 1e-12)
        }
        let wanted = min(Int(windowSeconds * sampleRate), max(Int((note.offset - note.onset) * sampleRate), 256))
        let length = min(wanted, samples.count - start)
        guard length >= 64 else { return nil }

        var window = [Double](repeating: 0, count: length)
        var gain = 0.0
        for i in 0..<length {
            let w = 0.5 - 0.5 * cos(2 * .pi * Double(i) / Double(length - 1))
            window[i] = Double(samples[start + i]) * w
            gain += w
        }

        let fundamental = 440 * pow(2, Double(note.pitch - 69) / 12)
        var power = 0.0
        for h in 1...harmonics {
            let f = fundamental * Double(h)
            if f >= 0.45 * sampleRate { break }
            var best = 0.0
            for cents in [-50.0, -25, 0, 25, 50] {
                best = max(best, tonePower(window, frequency: f * pow(2, cents / 1200), sampleRate: sampleRate))
            }
            power += best / Double(h)
        }
        return 10 * log10(power / (gain * gain) + 1e-12)
    }

    /// |sum x[n] e^{-j w n}|^2 by an oscillator recurrence.
    private static func tonePower(_ x: [Double], frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * .pi * frequency / sampleRate
        let c = cos(omega), s = sin(omega)
        var cn = 1.0, sn = 0.0
        var re = 0.0, im = 0.0
        for v in x {
            re += v * cn
            im += v * sn
            let next = cn * c - sn * s
            sn = sn * c + cn * s
            cn = next
        }
        return re * re + im * im
    }
}
