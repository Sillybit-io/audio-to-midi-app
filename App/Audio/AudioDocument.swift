import AVFoundation
import UniformTypeIdentifiers

struct AudioDocument: Sendable {
    enum Kind: Equatable {
        case audio
        case midi
        case other
    }

    /// What a file the user opened or dropped is, judged by its type, so that only audio is copied into the library.
    /// A format Core Audio can't decode (OGG) still counts as audio; the open fails with its own message.
    static func kind(of url: URL) -> Kind {
        let ext = url.pathExtension.lowercased()
        if AudioOpenFailure.decodableExtensions.contains(ext) { return .audio }
        guard let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .midi) { return .midi }
        return type.conforms(to: .audio) ? .audio : .other
    }

    /// The longest audio the app opens. The whole recording is held in memory as mono float32 (an hour at 48 kHz is
    /// about 700 MB) and the slice, the resampled copy and the playback buffer each add another.
    static let maximumDuration: Double = 60 * 60
    /// Frames decoded per read, so the file's own channel layout is never held whole.
    static let readFrames: AVAudioFrameCount = 65_536

    let url: URL
    let samples: [Float]
    let sampleRate: Double

    var duration: Double { Double(samples.count) / sampleRate }
    var name: String { url.deletingPathExtension().lastPathComponent }

    /// Decodes the whole file to mono float32, a chunk at a time. Stops with `CancellationError` when the task that
    /// runs it is cancelled. Releases security-scoped access when done.
    static func load(url: URL, maximumDuration: Double = AudioDocument.maximumDuration) throws -> AudioDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        guard duration <= maximumDuration else { throw AudioDocumentError.tooLong(seconds: duration) }
        guard file.length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: readFrames),
              let data = buffer.floatChannelData else { throw ResamplerError.formatUnavailable }

        let channels = Int(format.channelCount)
        let scale = 1 / Float(channels)
        var mono: [Float] = []
        mono.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: readFrames)
            let count = Int(buffer.frameLength)
            guard count > 0 else { break }
            let start = mono.count
            mono.append(contentsOf: UnsafeBufferPointer(start: data[0], count: count))
            guard channels > 1 else { continue }
            mono.withUnsafeMutableBufferPointer { out in
                for c in 1..<channels {
                    let channel = data[c]
                    for i in 0..<count { out[start + i] += channel[i] }
                }
                for i in 0..<count { out[start + i] *= scale }
            }
        }
        return AudioDocument(url: url, samples: mono, sampleRate: format.sampleRate)
    }
}

enum AudioDocumentError: Error, Equatable {
    case tooLong(seconds: Double)
}
