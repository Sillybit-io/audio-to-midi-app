import SwiftUI

@main
struct SillyMIDIToolsApp: App {
    @State private var model = DocumentModel()
    @State private var store = ModelStore()
    @State private var access = AccessCoordinator()
    @State private var session = TranscriptionSession()
    @State private var workingFolder: WorkingFolderStore
    @State private var imports: AudioImportStore
    @State private var library: LibraryStore
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
                        workingFolder: workingFolder, library: library, imports: imports)
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
        Window("About Silly MIDI Tools", id: "about") { AboutView() }
            .windowResizability(.contentSize)
        Settings { SettingsView(coordinator: access) }
    }
}
