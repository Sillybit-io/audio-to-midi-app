import SwiftUI

@main
struct SillyMIDIToolsApp: App {
    @State private var model = DocumentModel()
    @State private var store = ModelStore()
    @State private var access = AccessCoordinator()
    @State private var session = TranscriptionSession()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Silly MIDI Tools", id: "main") {
            ContentView(model: model, store: store, access: access, session: session)
                .frame(minWidth: 640, minHeight: 420)
                .onAppear { MIDIExportItem.clearTemporaryFiles() }
                .onAppear { store.policy = HuggingFaceAccessPolicy(coordinator: access) }
        }
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
