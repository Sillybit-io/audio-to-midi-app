import SwiftUI

struct InstrumentChipsView: View {
    let instruments: [EngineInstrument]
    @Binding var selection: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.sp4) {
            ForEach(grouped, id: \.family.id) { family, items in
                VStack(alignment: .leading, spacing: Metric.sp2) {
                    HStack(spacing: Metric.sp3) {
                        Circle().fill(InstrumentColor.color(forFamily: family.id)).frame(width: Metric.sp4, height: Metric.sp4)
                        Text(family.title).font(.caption.bold())
                    }
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

    private var grouped: [(family: (id: String, title: String, keys: [String]), items: [EngineInstrument])] {
        let dict = Dictionary(grouping: instruments) { InstrumentFamily.id(for: $0.name) }
        let other: (id: String, title: String, keys: [String]) = ("all", "Other", [])
        return (InstrumentFamily.all + [other]).compactMap { family in dict[family.id].map { (family, $0) } }
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
