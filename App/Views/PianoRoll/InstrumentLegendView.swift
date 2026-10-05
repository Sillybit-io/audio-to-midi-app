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

/// One row per instrument in a result: swatch, name, note count, mute and hide.
/// Muting silences playback only; hiding also takes the notes out of the roll.
struct InstrumentLegendView: View {
    let counts: [(name: String, count: Int)]
    var neutral = false
    @Binding var muted: Set<String>
    @Binding var hidden: Set<String>

    var body: some View {
        ForEach(counts, id: \.name) { item in
            let name = item.name.replacingOccurrences(of: "_", with: " ")
            HStack(spacing: Metric.sp3) {
                Circle().fill(neutral ? InstrumentColor.color(forFamily: "all") : InstrumentColor.color(for: item.name))
                    .frame(width: Metric.sp4, height: Metric.sp4)
                    .accessibilityHidden(true)
                Text(name).lineLimit(1)
                Spacer(minLength: Metric.sp2)
                Text("\(item.count)").font(.caption.monospacedDigit()).foregroundStyle(Native.fgSecondary)
                    .accessibilityLabel("\(item.count) notes")
                Toggle("M", isOn: member(item.name, of: $muted))
                    .toggleStyle(.button).controlSize(.small).help("Mute \(name)").accessibilityLabel("Mute \(name)")
                Toggle(isOn: member(item.name, of: $hidden)) {
                    Image(systemName: hidden.contains(item.name) ? "eye.slash" : "eye")
                }
                .toggleStyle(.button).controlSize(.small).help("Hide \(name)").accessibilityLabel("Hide \(name)")
            }
        }
    }

    private func member(_ name: String, of set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(name) },
                set: { if $0 { set.wrappedValue.insert(name) } else { set.wrappedValue.remove(name) } })
    }
}
