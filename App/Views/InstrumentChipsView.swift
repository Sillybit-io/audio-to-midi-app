import SwiftUI

struct InstrumentChipsView: View {
    let instruments: [EngineInstrument]
    @Binding var selection: Set<String>

    private static let families: [(String, [String])] = [
        ("Keys", ["piano", "organ", "chromatic"]), ("Guitars", ["guitar"]), ("Bass", ["bass"]),
        ("Drums", ["drums", "timpani"]), ("Strings", ["violin", "viola", "cello", "contrabass", "harp", "string"]),
        ("Winds", ["sax", "oboe", "horn_e", "english", "bassoon", "clarinet", "flute"]),
        ("Brass", ["trumpet", "trombone", "tuba", "french", "brass"]), ("Synth", ["synth"]), ("Voice", ["voice", "orchestra"]),
    ]

    private func family(_ name: String) -> String {
        Self.families.first { _, keys in keys.contains { name.contains($0) } }?.0 ?? "Other"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(selection.isEmpty ? "Instruments: automatic" : "Instruments: \(selection.count) selected").font(.caption).foregroundStyle(.secondary)
            ForEach(grouped, id: \.0) { title, items in
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.caption.bold()).frame(width: 60, alignment: .leading)
                    FlowRow(items: items.map(\.name)) { name in
                        Toggle(name.replacingOccurrences(of: "_", with: " "), isOn: Binding(
                            get: { selection.contains(name) },
                            set: { if $0 { selection.insert(name) } else { selection.remove(name) } }))
                            .toggleStyle(.button).controlSize(.small)
                    }
                }
            }
        }
    }

    private var grouped: [(String, [EngineInstrument])] {
        let dict = Dictionary(grouping: instruments) { family($0.name) }
        let order = Self.families.map(\.0) + ["Other"]
        return order.compactMap { key in dict[key].map { (key, $0) } }
    }
}

private struct FlowRow<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack { ForEach(items, id: \.self) { content($0) } }
        }
    }
}
