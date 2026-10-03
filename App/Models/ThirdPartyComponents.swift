import Foundation

enum ThirdPartyComponents {
    /// Must equal the level-two headings of THIRD_PARTY_NOTICES.md, in order.
    static let names = [
        "MuScriptor weights", "GGUF conversion", "muscriptor.cpp", "ggml", "pffft", "Basic Pitch",
        "swift-midi-file", "Jon Worthy and the Bends excerpt", "Apple General MIDI soundbank",
    ]

    static func noticesText(bundle: Bundle = Bundle(for: ModelStoreProbe.self)) -> String {
        bundle.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    static func headings(in text: String) -> [String] {
        var inFence = false
        var found: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") { inFence.toggle() }
            if !inFence, line.hasPrefix("## ") { found.append(String(line.dropFirst(3))) }
        }
        return found
    }
}
