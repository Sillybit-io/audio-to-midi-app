import SwiftUI

enum InstrumentFamily {
    static let all: [(id: String, title: String, keys: [String])] = [
        ("keys", "Keys", ["piano", "organ", "chromatic"]), ("guitars", "Guitars", ["guitar"]), ("bass", "Bass", ["bass"]),
        ("drums", "Drums", ["drums", "timpani"]), ("strings", "Strings", ["violin", "viola", "cello", "contrabass", "harp", "string"]),
        ("winds", "Winds", ["sax", "oboe", "horn_e", "english", "bassoon", "clarinet", "flute"]),
        ("brass", "Brass", ["trumpet", "trombone", "tuba", "french", "brass"]), ("synth", "Synth", ["synth"]),
        ("voice", "Voice", ["voice", "orchestra"]),
    ]

    /// An exact class name wins ("bassoon" is a wind, not a bass); otherwise the first family whose key it contains.
    static func id(for instrument: String) -> String {
        all.first { $0.keys.contains(instrument) }?.id
            ?? all.first { $0.keys.contains { instrument.contains($0) } }?.id ?? "all"
    }
}

extension InstrumentColor {
    static func color(for instrument: String) -> Color {
        color(forFamily: InstrumentFamily.id(for: instrument))
    }
}

struct InstrumentLegendView: View {
    let instruments: [String]
    @Binding var hidden: Set<String>

    var body: some View {
        HStack {
            ForEach(instruments, id: \.self) { name in
                Toggle(isOn: Binding(get: { !hidden.contains(name) },
                                     set: { if $0 { hidden.remove(name) } else { hidden.insert(name) } })) {
                    HStack(spacing: Metric.sp2) {
                        Circle().fill(InstrumentColor.color(for: name)).frame(width: Metric.sp4, height: Metric.sp4)
                        Text(name.replacingOccurrences(of: "_", with: " "))
                    }
                }
                .toggleStyle(.checkbox).font(.caption)
            }
        }
    }
}
