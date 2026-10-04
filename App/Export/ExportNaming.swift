import Foundation

enum ExportNaming {
    /// "Song" and a detected key give "Song - Eb minor"; without a key the name stays as it is.
    static func fileName(base: String, key: KeyMatch?) -> String {
        guard let key else { return base }
        return "\(base) - \(key.fileLabel)"
    }
}
