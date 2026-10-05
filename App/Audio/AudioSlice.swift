import Foundation

struct AudioSlice: Equatable, Sendable {
    static let step = 0.01
    /// The shortest slice the handles, the keys and the waveform gestures allow.
    static let minimumSpan = 0.5

    private(set) var start: Double
    private(set) var end: Double
    let duration: Double
    var relativeTimeline = true

    init(duration: Double) {
        self.duration = duration
        start = 0
        end = duration
    }

    var span: Double { end - start }

    static func snap(_ seconds: Double) -> Double {
        (seconds / step).rounded() * step
    }

    /// The minimum span, or the whole audio when it is shorter than that.
    private var shortest: Double { min(Self.minimumSpan, duration) }

    mutating func setStart(_ seconds: Double) {
        let upper = max(0, end - shortest)
        start = min(max(0, Self.snap(seconds)), upper)
    }

    mutating func setEnd(_ seconds: Double) {
        let lower = min(duration, start + shortest)
        end = max(min(duration, Self.snap(seconds)), lower)
    }

    func contains(_ seconds: Double) -> Bool {
        seconds >= start && seconds <= end
    }

    /// A new slice between two times given in either order, made at least the minimum long.
    mutating func select(from a: Double, to b: Double) {
        var low = min(max(0, min(a, b)), duration)
        var high = min(max(0, max(a, b)), duration)
        if high - low < shortest {
            high = min(duration, low + shortest)
            low = max(0, high - shortest)
        }
        start = Self.snap(low)
        end = Self.snap(high)
    }

    /// Moves the whole slice, keeping its length, and stops it at the ends of the audio.
    mutating func shift(by delta: Double) {
        let length = span
        let moved = min(max(0, Self.snap(start + delta)), max(0, duration - length))
        start = moved
        end = min(duration, moved + length)
    }

    mutating func reset() {
        start = 0
        end = duration
    }

    func cut(_ samples: [Float], sampleRate: Double) -> [Float] {
        let from = min(samples.count, max(0, Int((start * sampleRate).rounded())))
        let to = min(samples.count, max(from, Int((end * sampleRate).rounded())))
        return Array(samples[from..<to])
    }
}
