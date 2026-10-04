import SwiftUI
import UniformTypeIdentifiers

struct LibrarySidebarView: View {
    let library: LibraryStore
    let workingFolder: WorkingFolderStore
    let imports: AudioImportStore
    @Binding var selection: LibrarySelection?
    let openAudio: () -> Void

    @State private var importingMIDI = false
    @State private var importFailure: (name: String, message: String)?

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
                    midiRow(entry).tag(LibrarySelection.midi(entry.url))
                }
            } header: {
                header("MIDI", folder: workingFolder.midiFolder)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: Metric.sp3) {
                Button("Open Audio…", action: openAudio)
                Button("Import MIDI…") { importingMIDI = true }
            }
            .controlSize(.small)
            .padding(Metric.sp4)
        }
        .fileImporter(isPresented: $importingMIDI, allowedContentTypes: [.midi]) { result in
            importMIDI(result)
        }
        .alert(importFailureTitle, isPresented: Binding(
            get: { importFailure != nil }, set: { if !$0 { importFailure = nil } })) {
            Button("OK") { importFailure = nil }
        } message: {
            Text(importFailure?.message ?? "")
        }
    }

    private var importFailureTitle: String {
        "Could not import \u{201C}\(importFailure?.name ?? "")\u{201D}"
    }

    private func importMIDI(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { importFailure = ("the file", error.localizedDescription) }
        case .success(let url):
            guard let folder = workingFolder.midiFolder else {
                importFailure = (url.lastPathComponent, "Choose a working folder first.")
                return
            }
            do {
                let destination = try MIDIImporter.importFile(from: url, into: folder)
                library.refresh()
                selection = .midi(destination)
            } catch {
                importFailure = (url.lastPathComponent, error.localizedDescription)
            }
        }
    }

    private func midiRow(_ entry: LibraryEntry) -> some View {
        Label {
            VStack(alignment: .leading, spacing: Metric.sp1) {
                Text(entry.name)
                Text(Self.summary(entry.midiInfo)).font(.caption).foregroundStyle(Native.fgSecondary)
            }
        } icon: {
            Image(systemName: "pianokeys").foregroundStyle(entry.midiInfo == nil ? Token.warn : Native.fgSecondary)
        }
        .help(([entry.midiInfo?.trackNames.joined(separator: ", ")].compactMap { $0 } + [entry.url.abbreviatedPath]).joined(separator: "\n"))
    }

    static func summary(_ info: MIDIFileInfo?) -> String {
        guard let info else { return "Can\u{2019}t be read" }
        return "\(info.noteCount) \(info.noteCount == 1 ? "note" : "notes") · \(info.origin.title)"
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
