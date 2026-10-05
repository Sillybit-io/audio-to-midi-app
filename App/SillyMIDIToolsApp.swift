import AppKit
import SwiftUI

/// Vetoes Quit while the open MIDI file has unsaved changes, and answers once the prompt is resolved.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: MIDISaveCoordinator?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coordinator, coordinator.hasUnsavedChanges else { return .terminateNow }
        coordinator.confirmLeaving(then: { sender.reply(toApplicationShouldTerminate: true) },
                                   cancelled: { sender.reply(toApplicationShouldTerminate: false) })
        return .terminateLater
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
    @State private var model = DocumentModel()
    @State private var store = ModelStore()
    @State private var access = AccessCoordinator()
    @State private var session = TranscriptionSession()
    @State private var workingFolder: WorkingFolderStore
    @State private var imports: AudioImportStore
    @State private var library: LibraryStore
    @State private var preferences = AppPreferences()
    @State private var saveCoordinator = MIDISaveCoordinator()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        let folder = WorkingFolderStore()
        folder.resolveAtLaunch()
        let importStore = AudioImportStore()
        _workingFolder = State(initialValue: folder)
        _imports = State(initialValue: importStore)
        _library = State(initialValue: LibraryStore(imports: importStore))
    }

    var body: some Scene {
        Window("Silly MIDI Tools", id: "main") {
            ContentView(model: model, store: store, access: access, session: session,
                        workingFolder: workingFolder, library: library, imports: imports, preferences: preferences,
                        saveCoordinator: saveCoordinator)
                .onAppear { appDelegate.coordinator = saveCoordinator }
                .onAppear { MIDIExportItem.clearTemporaryFiles() }
                .onAppear { store.policy = HuggingFaceAccessPolicy(coordinator: access) }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Silly MIDI Tools") { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Audio…") { model.isImporting = true }
                    .keyboardShortcut("o")
            }
        }
        Window("About Silly MIDI Tools", id: "about") { AboutView().preferredColorScheme(preferences.appearance.colorScheme) }
            .windowResizability(.contentSize)
        Settings { SettingsView(coordinator: access, store: store, workingFolder: workingFolder, preferences: preferences) }
    }
}
