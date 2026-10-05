import SwiftUI
import UniformTypeIdentifiers

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

    private var fileName: String {
        keyInName ? ExportNaming.fileName(base: name, key: KeyDetector.rank(notes: notes).first) : name
    }

    private func makeItem(embed: Bool) -> MIDIExportItem {
        var options = MIDIExportOptions()
        options.sliceStart = slice.start
        options.sliceLength = slice.span
        options.relativeTimeline = slice.relativeTimeline
        options.title = name
        options.copyright = embed ? notice : nil
        return MIDIExportItem(notes: notes, options: options, name: fileName)
    }

    var body: some View {
        HStack {
            Label("MIDI", systemImage: "music.note")
                .padding(.horizontal, Metric.sp4).padding(.vertical, Metric.sp2)
                .background(.quaternary, in: Capsule())
                .draggable(makeItem(embed: embedNotice))
                .help("Drag into Finder or a DAW")
            Button("Export…") { showNotice = true }
        }
        .disabled(notes.isEmpty)
        .sheet(isPresented: $showNotice) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Export MIDI").font(.title3.bold())
                Text(notice.isEmpty ? "No licence notice for this model." : notice)
                Toggle("Embed this notice in the MIDI file", isOn: $embedNotice)
                Toggle("Add the detected key to the file name (\(fileName).mid)", isOn: $keyInName)
                HStack {
                    Spacer()
                    Button("Cancel") { showNotice = false }
                    Button("Export") {
                        item = makeItem(embed: embedNotice)
                        showNotice = false
                        exporting = true
                    }.buttonStyle(.borderedProminent)
                }
            }
            .padding(20).frame(width: 440)
        }
        .fileExporter(isPresented: $exporting, item: item, contentTypes: [.midi], defaultFilename: fileName) { _ in
            MIDIExportItem.clearTemporaryFiles()
        } onCancellation: {
            MIDIExportItem.clearTemporaryFiles()
        }
    }
}
