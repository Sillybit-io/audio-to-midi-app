import SwiftUI

@main
struct SillyMIDIToolsApp: App {
    @State private var model = DocumentModel()

    var body: some Scene {
        Window("Silly MIDI Tools", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 640, minHeight: 420)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Audio…") { model.isImporting = true }
                    .keyboardShortcut("o")
            }
        }
    }
}
