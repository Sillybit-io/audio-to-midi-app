import Foundation

/// A throwaway defaults suite. `removePersistentDomain` empties it, but the preferences daemon keeps an empty plist
/// for the suite in the app's container, so the cleanup deletes that file too.
func scratchDefaults(_ prefix: String) -> (defaults: UserDefaults, cleanup: () -> Void) {
    let name = "\(prefix)-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, {
        defaults.removePersistentDomain(forName: name)
        CFPreferencesAppSynchronize(name as CFString)
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(at: library.appending(path: "Preferences/\(name).plist"))
    })
}
