import SwiftUI
import UniformTypeIdentifiers

struct LibrarySidebarView: View {
    let library: LibraryStore
    let workingFolder: WorkingFolderStore
    let imports: AudioImportStore
    @Binding var selection: LibrarySelection?
    let openAudio: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                if library.audio.isEmpty {
                    Text("No audio yet").foregroundStyle(Native.fgSecondary)
                }
                ForEach(library.audio) { entry in
                    audioRow(entry).tag(LibrarySelection.audio(entry.url))
                }
            } header: {
                header("Audio", folder: workingFolder.audioFolder)
            }
            Section {
                if library.midi.isEmpty {
                    Text("Transcriptions appear here").foregroundStyle(Native.fgSecondary)
                }
                ForEach(library.midi) { entry in
                    Label(entry.name, systemImage: "pianokeys").tag(LibrarySelection.midi(entry.url))
                }
            } header: {
                header("MIDI", folder: workingFolder.midiFolder)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Open Audio…", action: openAudio).padding(Metric.sp4)
        }
    }

    private func header(_ title: String, folder: URL?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let name = workingFolder.folder?.lastPathComponent {
                Text(name).font(.caption2).lineLimit(1).truncationMode(.middle).help(folder?.abbreviatedPath ?? "")
            }
        }
    }

    @ViewBuilder private func audioRow(_ entry: LibraryEntry) -> some View {
        Label {
            Text(entry.name)
        } icon: {
            Image(systemName: entry.isMissing ? "exclamationmark.triangle" : "waveform")
                .foregroundStyle(entry.isMissing ? Token.warn : Native.fgSecondary)
        }
        .help(entry.isMissing ? "File not found. Relink\u{2026} to find it again." : entry.url.abbreviatedPath)
        .contextMenu {
            if !entry.isMissing {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
            }
            if let id = entry.referenceID, let reference = imports.references.first(where: { $0.id == id }) {
                Button("Relink\u{2026}") { relink(reference) }
                Button("Remove from Library") {
                    imports.remove(reference)
                    library.refresh()
                }
            }
        }
    }

    private func relink(_ reference: AudioReference) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseDirectories = false
        panel.message = "Choose the file for \u{201C}\(reference.name)\u{201D}."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? imports.relink(reference, to: url)
        library.refresh()
    }
}
