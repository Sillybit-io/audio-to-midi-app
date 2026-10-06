import SwiftUI
import UniformTypeIdentifiers

struct LibrarySidebarView: View {
    let library: LibraryStore
    let workingFolder: WorkingFolderStore
    let imports: AudioImportStore
    @Binding var selection: LibrarySelection?
    let openAudio: () -> Void
    @Binding var importingMIDI: Bool
    /// The audio file whose model download just failed; its row says so until the next try.
    var failedDownload: URL?
    /// The audio file being transcribed right now; its row says so, whichever file is open.
    var transcribing: URL?

    @State private var failure: (title: String, message: String)?

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
        .alert(failure?.title ?? "", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") { failure = nil }
        } message: {
            Text(failure?.message ?? "")
        }
    }

    private func importMIDI(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            if (error as? CocoaError)?.code != .userCancelled { failure = ("Could not import the file", error.localizedDescription) }
        case .success(let url):
            guard let folder = workingFolder.midiFolder else {
                failure = ("Could not import \u{201C}\(url.lastPathComponent)\u{201D}", "Choose a working folder first.")
                return
            }
            do {
                let destination = try MIDIImporter.importFile(from: url, into: folder)
                debugLog(.midi, "Imported \"\(url.lastPathComponent)\" as \"\(destination.lastPathComponent)\".")
                library.refresh()
                selection = .midi(destination)
            } catch {
                debugLog(.midi, "Couldn\u{2019}t import \"\(url.lastPathComponent)\": \(String(reflecting: error))")
                failure = ("Could not import \u{201C}\(url.lastPathComponent)\u{201D}", error.localizedDescription)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.name)
        .accessibilityValue(Self.summary(entry.midiInfo))
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
                Text("\(name)/\(title)").font(.caption2).lineLimit(1).truncationMode(.head).help(folder?.abbreviatedPath ?? "")
            }
        }
    }

    @ViewBuilder private func audioRow(_ entry: LibraryEntry) -> some View {
        let failed = entry.url.standardizedFileURL == failedDownload?.standardizedFileURL
        let busy = entry.url.standardizedFileURL == transcribing?.standardizedFileURL
        Label {
            VStack(alignment: .leading, spacing: Metric.sp1) {
                Text(entry.name)
                if failed {
                    Text("Download failed \u{00B7} Try again").font(.caption).foregroundStyle(.secondary)
                } else if busy {
                    Text("Transcribing\u{2026}").font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: entry.isMissing || failed ? "exclamationmark.triangle" : "waveform")
                    .foregroundStyle(entry.isMissing || failed ? Token.warn : Native.fgSecondary)
            }
        }
        .help(entry.isMissing ? "File not found. Relink\u{2026} to find it again." : entry.url.abbreviatedPath)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.isMissing ? "\(entry.name), file not found" : failed ? "\(entry.name), download failed" : busy ? "\(entry.name), transcribing" : entry.name)
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
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try imports.relink(reference, to: url)
                debugLog(.library, "Relinked \"\(reference.name)\" to \(url.path).")
            } catch {
                debugLog(.library, "Couldn\u{2019}t relink \"\(reference.name)\": \(String(reflecting: error))")
                failure = ("Could not relink \u{201C}\(reference.name)\u{201D}", error.localizedDescription)
            }
            library.refresh()
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
