import SwiftUI

enum InstrumentColor {
    static func color(for name: String) -> Color {
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }
        return Color(hue: Double(hash) / 360, saturation: 0.65, brightness: 0.9)
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
                    HStack(spacing: 4) {
                        Circle().fill(InstrumentColor.color(for: name)).frame(width: 8, height: 8)
                        Text(name.replacingOccurrences(of: "_", with: " "))
                    }
                }
                .toggleStyle(.checkbox).font(.caption)
            }
        }
    }
}
