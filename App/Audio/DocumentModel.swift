import Foundation
import Observation

/// What the alert says when audio can't be opened, in the handoff's wording.
struct AudioOpenFailure: Equatable, Sendable {
    var title: String
    var message: String

    /// Extensions Core Audio decodes; a file with one of these that still fails is probably damaged.
    static let decodableExtensions: Set<String> = ["wav", "wave", "mp3", "flac", "m4a", "aif", "aiff", "aifc", "caf", "aac", "mp4"]

    static func decoding(_ url: URL, fileManager: FileManager = .default) -> AudioOpenFailure {
        guard fileManager.fileExists(atPath: url.path) else {
            return AudioOpenFailure(title: "Could not open \u{201C}\(url.lastPathComponent)\u{201D}",
                                    message: "The file was moved or deleted. Choose Relink\u{2026} from its menu in the sidebar to find it again.")
        }
        guard decodableExtensions.contains(url.pathExtension.lowercased()) else {
            return AudioOpenFailure(title: "Could not open audio",
                                    message: "This file can't be decoded. OGG isn't supported. Use WAV, MP3, FLAC, M4A or AIFF.")
        }
        return AudioOpenFailure(title: "Could not open \u{201C}\(url.lastPathComponent)\u{201D}",
                                message: "The file may be damaged, or it's in a format Core Audio can't read.")
    }

    static func other(_ error: Error) -> AudioOpenFailure {
        AudioOpenFailure(title: "Could not open audio", message: error.localizedDescription)
    }
}

@MainActor @Observable
final class DocumentModel {
    var document: AudioDocument?
    var slice = AudioSlice(duration: 0)
    var peaks: [Peak] = []
    var failure: AudioOpenFailure?
    var isImporting = false
    private(set) var isLoading = false
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// Decodes `url` and shows it. A file opened while an earlier one is still decoding wins; the earlier result is dropped.
    func open(_ url: URL) {
        debugLog(.audio, "Decoding \"\(url.lastPathComponent)\" (\(url.path))")
        loading?.cancel()
        isLoading = true
        loading = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let doc = try AudioDocument.load(url: url)
                    return (doc, WaveformPeaks.compute(doc.samples, buckets: 1000))
                }.value
                guard !Task.isCancelled else {
                    debugLog(.audio, "Dropped the decode of \"\(url.lastPathComponent)\": another file was opened meanwhile.")
                    return
                }
                debugLog(.audio, String(format: "Decoded \"%@\": %.2f s at %.0f Hz, %ld samples. The app uses %@.",
                                         url.lastPathComponent, result.0.duration, result.0.sampleRate, result.0.samples.count, DebugLog.footprint()))
                document = result.0
                peaks = result.1
                slice = AudioSlice(duration: result.0.duration)
            } catch {
                guard !Task.isCancelled else { return }
                debugLog(.audio, "Couldn\u{2019}t decode \"\(url.lastPathComponent)\": \(String(reflecting: error))")
                failure = .decoding(url)
            }
            isLoading = false
        }
    }
}
