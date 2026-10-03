import SwiftUI

struct ModelPickerView: View {
    let store: ModelStore
    @Binding var selection: ModelEntry.ID?

    var body: some View {
        List(ModelCatalog.entries, selection: $selection) { entry in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack { Text(entry.displayName).font(.headline); LicenseBadge(entry: entry) }
                    Text(detail(entry)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                trailing(entry)
            }
            .tag(entry.id)
        }
    }

    private func detail(_ entry: ModelEntry) -> String {
        guard entry.needsDownload else { return "Bundled, runs on this Mac · \(entry.attribution)" }
        let size = ByteCountFormatter.string(fromByteCount: entry.byteSize, countStyle: .file)
        let memory = ByteCountFormatter.string(fromByteCount: entry.memoryEstimate, countStyle: .memory)
        return "\(size) download · about \(memory) in memory · \(entry.attribution)"
    }

    @ViewBuilder private func trailing(_ entry: ModelEntry) -> some View {
        switch store.state(for: entry) {
        case .notInstalled:
            Button("Download") { Task { await store.install(entry) } }
        case .downloading(let value):
            ProgressView(value: value).frame(width: 100)
        case .verifying:
            Text("Verifying…").foregroundStyle(.secondary)
        case .installed:
            if entry.needsDownload {
                Text("Installed").foregroundStyle(.secondary)
                Button("Reveal") { store.reveal(entry) }
                Button("Delete", role: .destructive) { store.delete(entry) }
            } else {
                Text("Ready").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2)
            Button("Retry") { Task { await store.install(entry) } }
        }
    }
}
