import AppKit
import SwiftUI

/// Vetoes Quit while the open MIDI file has unsaved changes, and answers once the prompt is resolved.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: MIDISaveCoordinator?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        debugLog(.app, "Quit requested\(coordinator?.hasUnsavedChanges == true ? "; the open MIDI file has unsaved changes" : "").")
        guard let coordinator, coordinator.hasUnsavedChanges else { return .terminateNow }
        coordinator.confirmLeaving(then: { sender.reply(toApplicationShouldTerminate: true) },
                                   cancelled: { sender.reply(toApplicationShouldTerminate: false) })
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        DebugLog.shared.end()
    }
}

/// Stands in front of SwiftUI's own window delegate: closing is vetoed while there are unsaved changes, and every
/// other delegate message goes on to the original delegate.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
    private let coordinator: MIDISaveCoordinator
    private weak var original: NSWindowDelegate?

    init(coordinator: MIDISaveCoordinator, original: NSWindowDelegate?) {
        self.coordinator = coordinator
        self.original = original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        debugLog(.app, "Window close requested.")
        guard coordinator.hasUnsavedChanges else { return original?.windowShouldClose?(sender) ?? true }
        let coordinator = coordinator
        coordinator.confirmLeaving(then: { [weak sender] in
            coordinator.editor = nil
            sender?.close()
        })
        return false
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || original?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        original?.responds(to: aSelector) == true ? original : nil
    }
}

/// Installs the close guard on the window it sits in and keeps the close button's unsaved-changes dot current.
struct WindowGuard: NSViewRepresentable {
    let coordinator: MIDISaveCoordinator
    /// Passed in so SwiftUI calls `updateNSView` whenever the document turns dirty or clean.
    let edited: Bool

    final class Holder {
        var delegate: WindowCloseGuard?
    }

    func makeCoordinator() -> Holder { Holder() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let holder = context.coordinator
        DispatchQueue.main.async { install(view.window, holder) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        install(view.window, context.coordinator)
        if let window = view.window { coordinator.sync(window: window) }
    }

    private func install(_ window: NSWindow?, _ holder: Holder) {
        guard let window, !(window.delegate is WindowCloseGuard) else { return }
        let guardDelegate = WindowCloseGuard(coordinator: coordinator, original: window.delegate)
        holder.delegate = guardDelegate
        window.delegate = guardDelegate
        coordinator.sync(window: window)
    }
}

@main
struct SillyMIDIToolsApp: App {
    @State private var store = ModelStore()
    @State private var access = AccessCoordinator()
    @State private var workingFolder: WorkingFolderStore
    @State private var imports: AudioImportStore
    @State private var library: LibraryStore
    @State private var preferences: AppPreferences
    @State private var saveCoordinator = MIDISaveCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let folder = WorkingFolderStore()
        folder.resolveAtLaunch()
        let preferences = AppPreferences()
        DebugLogSetup.connect(preferences: preferences, folder: folder)
        #if DEBUG
        SimulatedCrash.fromLaunchArguments()
        #endif
        _preferences = State(initialValue: preferences)
        let importStore = AudioImportStore()
        _workingFolder = State(initialValue: folder)
        _imports = State(initialValue: importStore)
        _library = State(initialValue: LibraryStore(imports: importStore))
    }

    var body: some Scene {
        Window("Silly MIDI Tools", id: "main") {
            ContentView(store: store, access: access,
                        workingFolder: workingFolder, library: library, imports: imports, preferences: preferences,
                        saveCoordinator: saveCoordinator)
                .onAppear { appDelegate.coordinator = saveCoordinator }
                .onAppear { MIDIExportItem.clearTemporaryFiles() }
                .onAppear { store.policy = HuggingFaceAccessPolicy(coordinator: access) }
        }
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            AppCommands()
            #if DEBUG
            SimulateCrashCommands()
            #endif
        }
        Window("About Silly MIDI Tools", id: "about") { AboutView().preferredColorScheme(preferences.appearance.colorScheme) }
            .windowResizability(.contentSize)
        Settings { SettingsView(coordinator: access, store: store, workingFolder: workingFolder, preferences: preferences) }
    }
}
