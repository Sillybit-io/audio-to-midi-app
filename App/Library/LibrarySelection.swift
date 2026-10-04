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
}
