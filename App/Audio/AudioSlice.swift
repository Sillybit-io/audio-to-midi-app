import Foundation

struct AudioSlice: Equatable, Sendable {
    static let step = 0.01

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

    mutating func setStart(_ seconds: Double) {
        let upper = max(0, end - Self.step)
        start = min(max(0, Self.snap(seconds)), upper)
    }

    mutating func setEnd(_ seconds: Double) {
        let lower = min(duration, start + Self.step)
        end = max(min(duration, Self.snap(seconds)), lower)
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
