import Foundation

enum LibrarySelection: Hashable {
    case audio(URL)
    case midi(URL)

    var url: URL {
        switch self {
        case .audio(let url), .midi(let url): url
        }
    }

    var title: String { url.deletingPathExtension().lastPathComponent }

    /// `audio "take.wav"`, for the debug log.
    var logDescription: String {
        switch self {
        case .audio(let url): "audio \u{201C}\(url.lastPathComponent)\u{201D}"
        case .midi(let url): "MIDI \u{201C}\(url.lastPathComponent)\u{201D}"
        }
    }
}
