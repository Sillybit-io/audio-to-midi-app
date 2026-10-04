import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: DocumentModel
    let store: ModelStore
    @Bindable var access: AccessCoordinator
    let session: TranscriptionSession
    let workingFolder: WorkingFolderStore
    let library: LibraryStore
    let imports: AudioImportStore
    let preferences: AppPreferences

    @AppStorage("addAudioMode") private var addAudioMode = AddAudioMode.copy.rawValue
    @State private var screen: AudioScreenModel
    @State private var selection: LibrarySelection?
    @State private var showInspector = false
    @State private var showWelcome = false

    init(model: DocumentModel, store: ModelStore, access: AccessCoordinator, session: TranscriptionSession,
         workingFolder: WorkingFolderStore, library: LibraryStore, imports: AudioImportStore, preferences: AppPreferences) {
        self.model = model
        self.store = store
        self.access = access
        self.session = session
        self.workingFolder = workingFolder
        self.library = library
        self.imports = imports
        self.preferences = preferences
        _screen = State(initialValue: AudioScreenModel(document: model, store: store, session: session, access: access, preferences: preferences))
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(library: library, workingFolder: workingFolder, imports: imports,
                               selection: $selection, openAudio: { model.isImporting = true })
                .navigationSplitViewColumnWidth(min: Metric.sidebarW - Metric.sp9, ideal: Metric.sidebarW, max: Metric.sidebarW + Metric.sp10)
        } detail: {
            // A plain trailing pane rather than `.inspector`: with Reduce Transparency on, macOS 26.5 draws the
            // system inspector without its controls or default-coloured text.
            HStack(spacing: 0) {
                detail.frame(maxWidth: .infinity)
                if showInspector {
                    Divider()
                    inspector.frame(width: Metric.inspectorW).background(Token.bg)
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem {
                    Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                        .help(showInspector ? "Hide Inspector" : "Show Inspector")
                }
            }
        }
        .frame(minWidth: Metric.windowMinW, minHeight: Metric.windowMinH)
        .onChange(of: workingFolder.folder, initial: true) {
            library.attach(audio: workingFolder.audioFolder, midi: workingFolder.midiFolder)
        }
        .onChange(of: model.document?.url) { _, url in selection = url.map { .audio($0) } }
        .onChange(of: selection) { _, new in
            if case .audio(let url) = new, url != model.document?.url { model.open(url) }
        }
        .sheet(isPresented: Binding(get: { !workingFolder.isResolved || showWelcome }, set: { showWelcome = $0 })) {
            WelcomeView(workingFolder: workingFolder) { showWelcome = false }
                .interactiveDismissDisabled(!workingFolder.isResolved)
        }
        .sheet(item: $access.request) { request in
            LicenseSheet(coordinator: access, request: request).interactiveDismissDisabled()
        }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): openAudio(url)
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

    /// Copies or references the audio as the user prefers, then opens it.
    private func openAudio(_ url: URL) {
        do {
            let target = try imports.importAudio(from: url, mode: AddAudioMode(rawValue: addAudioMode) ?? .copy,
                                                 audioFolder: workingFolder.audioFolder)
            library.refresh()
            model.open(target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder private var detail: some View {
        if case .midi(let url) = selection {
            ContentUnavailableView(url.deletingPathExtension().lastPathComponent, systemImage: "pianokeys",
                                   description: Text("The MIDI editor isn\u{2019}t available yet."))
        } else if model.document == nil {
            DropZoneView(onOpen: openAudio, onChooseFile: { model.isImporting = true },
                         folderPath: workingFolder.folder.map { $0.abbreviatedPath + "/" })
        } else {
            AudioDetailView(screen: screen, onOpenAudio: openAudio)
        }
    }

    private var inspector: some View {
        Group {
            if model.document != nil, !isMIDISelected {
                AudioInspectorView(screen: screen)
            } else {
                ContentUnavailableView("No Audio Selected", systemImage: "waveform")
            }
        }
    }

    private var isMIDISelected: Bool {
        if case .midi = selection { true } else { false }
    }

    private var title: String {
        if case .midi(let url) = selection { return url.deletingPathExtension().lastPathComponent }
        return model.document?.name ?? "Silly MIDI Tools"
    }

    private var subtitle: String {
        if case .midi = selection { return "" }
        guard let document = model.document else { return "" }
        return String(format: "%.1f s · %@", document.duration, sampleRateText(document.sampleRate))
    }

    private func sampleRateText(_ rate: Double) -> String {
        "\((rate / 1000).formatted(.number.precision(.fractionLength(0...2)))) kHz"
    }
}
