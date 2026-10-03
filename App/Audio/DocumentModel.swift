import Foundation
import Observation

@MainActor @Observable
final class DocumentModel {
    var document: AudioDocument?
    var slice = AudioSlice(duration: 0)
    var peaks: [Peak] = []
    var errorMessage: String?
    var isImporting = false

    func open(_ url: URL) {
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let doc = try AudioDocument.load(url: url)
                    return (doc, WaveformPeaks.compute(doc.samples, buckets: 1000))
                }.value
                document = result.0
                peaks = result.1
                slice = AudioSlice(duration: result.0.duration)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
