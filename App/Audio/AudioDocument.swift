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

    let url: URL
    let samples: [Float]
    let sampleRate: Double

    var duration: Double { Double(samples.count) / sampleRate }
    var name: String { url.deletingPathExtension().lastPathComponent }

    /// Decodes the whole file to mono float32. Releases security-scoped access when done.
    static func load(url: URL) throws -> AudioDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw ResamplerError.formatUnavailable
        }
        try file.read(into: buffer)

        let count = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        guard let data = buffer.floatChannelData else { throw ResamplerError.formatUnavailable }
        var mono = [Float](repeating: 0, count: count)
        for c in 0..<channels {
            let channel = data[c]
            for i in 0..<count { mono[i] += channel[i] }
        }
        if channels > 1 {
            let scale = 1 / Float(channels)
            for i in 0..<count { mono[i] *= scale }
        }
        return AudioDocument(url: url, samples: mono, sampleRate: format.sampleRate)
    }
}
