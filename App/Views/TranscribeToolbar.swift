import SwiftUI

struct TranscribeToolbar: View {
    let store: ModelStore
    let session: TranscriptionSession
    let devices: [EngineDevice]
    @Binding var modelID: ModelEntry.ID?
    @Binding var deviceIndex: Int?
    @Binding var threads: Int
    let canStart: Bool
    let onStart: () -> Void

    private var usable: [ModelEntry] {
        ModelCatalog.entries.filter { $0.engine == .muscriptor && store.state(for: $0) == .installed }
    }

    var body: some View {
        HStack {
            Picker("Model", selection: $modelID) {
                Text("Choose a model").tag(ModelEntry.ID?.none)
                ForEach(usable) { Text($0.displayName).tag(Optional($0.id)) }
            }.frame(maxWidth: 220)
            if let entry = ModelCatalog.entries.first(where: { $0.id == modelID }) { LicenseBadge(entry: entry) }
            Picker("Device", selection: $deviceIndex) {
                Text("Auto").tag(Int?.none)
                ForEach(devices, id: \.index) { Text("\($0.name) (\($0.backend))").tag(Optional($0.index)) }
            }.frame(maxWidth: 220)
            Stepper("Threads \(threads)", value: $threads, in: 1...32)
            Spacer()
            statusView
            if session.isBusy {
                Button("Cancel") { session.cancel() }
            } else {
                Button("Transcribe", action: onStart).disabled(!canStart).keyboardShortcut(.return)
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch session.state {
        case .loading(let p):
            ProgressView(value: p) { Text("Loading model") }.frame(width: 160)
        case .running:
            ProgressView(value: session.progress) {
                Text(session.eta.map { "About \(Int($0.rounded())) s left" } ?? "Transcribing")
            }.frame(width: 160)
        case .done(let n): Text("Done — \(n) notes")
        case .failed(let m): Text(m).foregroundStyle(.red).lineLimit(2)
        case .cancelled: Text("Cancelled — partial notes kept")
        case .idle: EmptyView()
        }
    }
}
