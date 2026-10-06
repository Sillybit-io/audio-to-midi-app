import SwiftUI
import UniformTypeIdentifiers

/// Builds the file the toolbar's Export… button saves and the inspector's chip drags out.
enum MIDIExport {
    static func item(notes: [NoteEvent], entry: ModelEntry?, slice: AudioSlice, name: String,
                     embedNotice: Bool = true, keyInName: Bool = true) -> MIDIExportItem {
        var options = MIDIExportOptions()
        options.sliceStart = slice.start
        options.sliceLength = slice.span
        options.relativeTimeline = slice.relativeTimeline
        options.title = name
        options.copyright = embedNotice ? (entry?.exportNotice ?? "") : nil
        return MIDIExportItem(notes: notes, options: options, name: fileName(notes: notes, name: name, keyInName: keyInName))
    }

    static func fileName(notes: [NoteEvent], name: String, keyInName: Bool = true) -> String {
        keyInName ? ExportNaming.fileName(base: name, key: KeyDetector.rank(notes: notes).first) : name
    }
}

struct ExportView: View {
    let notes: [NoteEvent]
    let entry: ModelEntry?
    let slice: AudioSlice
    let name: String

    @Binding var showNotice: Bool
    @State private var embedNotice = true
    @State private var keyInName = true
    @State private var exporting = false
    @State private var item: MIDIExportItem?

    private var notice: String { entry?.exportNotice ?? "" }

    private var fileName: String { MIDIExport.fileName(notes: notes, name: name, keyInName: keyInName) }

    var body: some View {
        Button("Export…") { showNotice = true }
            .accessibilityLabel("Export MIDI\u{2026}")
            .disabled(notes.isEmpty)
            .sheet(isPresented: $showNotice) {
                VStack(alignment: .leading, spacing: Metric.sp5) {
                    Text("Export MIDI").font(.title3.bold())
                    Text(notice.isEmpty ? "No licence notice for this model." : notice)
                    Toggle("Embed this notice in the MIDI file", isOn: $embedNotice)
                    Toggle("Add the detected key to the file name (\(fileName).mid)", isOn: $keyInName)
                    HStack {
                        Spacer()
                        Button("Cancel") { showNotice = false }
                        Button("Export") {
                            item = MIDIExport.item(notes: notes, entry: entry, slice: slice, name: name,
                                                   embedNotice: embedNotice, keyInName: keyInName)
                            showNotice = false
                            exporting = true
                        }.buttonStyle(.borderedProminent)
                    }
                }
                .padding(Metric.sp7).frame(width: Metric.sheetW)
            }
            .fileExporter(isPresented: $exporting, item: item, contentTypes: [.midi], defaultFilename: "\(fileName).mid") { result in
                switch result {
                case .success(let url): debugLog(.export, "Exported to \(url.path).")
                case .failure(let error): debugLog(.export, "Export failed: \(String(reflecting: error))")
                }
                MIDIExportItem.clearTemporaryFiles()
            } onCancellation: {
                debugLog(.export, "Export cancelled.")
                MIDIExportItem.clearTemporaryFiles()
            }
    }
}

/// The MIDI file as an object to drag into Finder or a DAW. It sits in the inspector, with its name and a hint,
/// because an icon alone in the toolbar didn't say what it was.
struct MIDIDragChip: View {
    let notes: [NoteEvent]
    let entry: ModelEntry?
    let slice: AudioSlice
    let name: String

    var body: some View {
        let file = notes.isEmpty ? name : MIDIExport.fileName(notes: notes, name: name)
        let chip = Label("\(file).mid", systemImage: "music.note")
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, Metric.sp5).padding(.vertical, Metric.sp3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Token.surfaceSunken, in: Capsule())
            .overlay(Capsule().strokeBorder(Token.border))
        if notes.isEmpty {
            chip.opacity(0.5).help("Transcribe something first")
        } else {
            chip.draggable(MIDIExport.item(notes: notes, entry: entry, slice: slice, name: name))
                .help("Drag this MIDI file into Finder or a DAW")
                .accessibilityLabel("MIDI file \(file), drag into Finder or a DAW")
        }
    }
}
