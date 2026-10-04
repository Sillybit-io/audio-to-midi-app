import Foundation

protocol BookmarkStorage {
    func data(for key: String) -> Data?
    func set(_ data: Data?, for key: String)
}

protocol BookmarkCodec {
    func makeBookmark(for url: URL) throws -> Data
    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool)
}

protocol ScopedAccess {
    func start(_ url: URL) -> Bool
    func stop(_ url: URL)
}

struct UserDefaultsBookmarkStorage: BookmarkStorage {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func data(for key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func set(_ data: Data?, for key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

struct SystemBookmarkCodec: BookmarkCodec {
    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }
}

struct SystemScopedAccess: ScopedAccess {
    func start(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stop(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}
