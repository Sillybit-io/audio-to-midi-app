import SwiftUI

/// A list of components in four groups with the selected component's notice beside it.
struct GroupedLicencesView: View {
    private let groups = ThirdPartyComponents.groups()
    @State private var selection: String? = "muscriptor"

    private var selected: LicenceEntry? {
        groups.flatMap(\.entries).first { $0.id == selection }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.entries) { entry in
                            VStack(alignment: .leading, spacing: Metric.sp1) {
                                Text(entry.name)
                                Text(entry.licence).font(.caption).foregroundStyle(Native.fgSecondary)
                            }
                            .tag(entry.id)
                        }
                    }
                }
            }
            .frame(width: Metric.sidebarW - Metric.sp9)
            Divider()
            if let selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metric.sp4) {
                        Text(selected.name).font(.title2.bold())
                        Text("\(selected.credit) · \(selected.licence)").font(.caption).foregroundStyle(Native.fgSecondary)
                        Text(selected.text.isEmpty ? "No notice text is bundled for this component." : selected.text)
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metric.sp6)
                }
            } else {
                ContentUnavailableView("Select a Component", systemImage: "doc.text")
            }
        }
    }
}
