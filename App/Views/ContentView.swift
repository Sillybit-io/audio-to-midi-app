import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: DocumentModel
    let store: ModelStore
    @Bindable var access: AccessCoordinator
    let session: TranscriptionSession

    @State private var selection: LibrarySelection?
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: Metric.sidebarW - Metric.sp9, ideal: Metric.sidebarW, max: Metric.sidebarW + Metric.sp10)
        } detail: {
            detail
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .inspector(isPresented: $showInspector) {
                    inspector.inspectorColumnWidth(Metric.inspectorW)
                }
                .toolbar {
                    ToolbarItem {
                        Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                            .help(showInspector ? "Hide Inspector" : "Show Inspector")
                    }
                }
        }
        .frame(minWidth: showInspector ? Metric.windowMinW + Metric.inspectorW : Metric.windowMinW, minHeight: Metric.windowMinH)
        .onChange(of: model.document?.url) { _, url in selection = url.map { .audio($0) } }
        .sheet(item: $access.request) { request in
            LicenseSheet(coordinator: access, request: request).interactiveDismissDisabled()
        }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): model.open(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert("Could not open audio", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        if model.document == nil {
            DropZoneView(model: model)
        } else {
            AudioDetailView(model: model, store: store, access: access, session: session)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Audio") {
                if let document = model.document {
                    Label(document.name, systemImage: "waveform").tag(LibrarySelection.audio(document.url))
                } else {
                    Text("No audio files yet").foregroundStyle(Native.fgSecondary)
                }
            }
            Section("MIDI") {
                Text("No MIDI files yet").foregroundStyle(Native.fgSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Open Audio…") { model.isImporting = true }
                .padding(Metric.sp4)
        }
    }

    private var inspector: some View {
        Group {
            if let document = model.document {
                Form {
                    Section("File") {
                        LabeledContent("Name", value: document.name)
                        LabeledContent("Duration", value: String(format: "%.1f s", document.duration))
                        LabeledContent("Sample rate", value: sampleRateText(document.sampleRate))
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Audio Selected", systemImage: "waveform")
            }
        }
    }

    private var title: String {
        model.document?.name ?? "Silly MIDI Tools"
    }

    private var subtitle: String {
        guard let document = model.document else { return "" }
        return String(format: "%.1f s · %@", document.duration, sampleRateText(document.sampleRate))
    }

    private func sampleRateText(_ rate: Double) -> String {
        "\((rate / 1000).formatted(.number.precision(.fractionLength(0...2)))) kHz"
    }
}
