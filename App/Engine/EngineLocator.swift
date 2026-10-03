import Foundation

enum EngineLocatorError: LocalizedError, Equatable {
    case missing

    var errorDescription: String? {
        "Engine missing: the sillymidi-engine helper is not inside the app bundle."
    }
}

enum EngineLocator {
    static let helperName = "sillymidi-engine"

    static func locate(in bundle: Bundle = .main) throws -> URL {
        guard let url = bundle.url(forAuxiliaryExecutable: helperName),
              FileManager.default.isExecutableFile(atPath: url.path)
        else {
            throw EngineLocatorError.missing
        }
        return url
    }
}
