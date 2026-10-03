import Foundation

struct Peak: Equatable, Sendable {
    var min: Float
    var max: Float
}

enum WaveformPeaks {
    static func compute(_ samples: [Float], buckets: Int) -> [Peak] {
        guard buckets > 0 else { return [] }
        guard !samples.isEmpty else { return Array(repeating: Peak(min: 0, max: 0), count: buckets) }
        return (0..<buckets).map { i in
            let from = i * samples.count / buckets
            let to = Swift.max(from + 1, (i + 1) * samples.count / buckets)
            var lo = Float.greatestFiniteMagnitude
            var hi = -Float.greatestFiniteMagnitude
            for s in samples[from..<Swift.min(to, samples.count)] {
                lo = Swift.min(lo, s)
                hi = Swift.max(hi, s)
            }
            return Peak(min: lo, max: hi)
        }
    }
}
