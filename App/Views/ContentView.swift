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
    let saveCoordinator: MIDISaveCoordinator

    @State private var screen: AudioScreenModel
    @State private var selection: LibrarySelection?
    @State private var showInspector = false
    @State private var showWelcome = false
    @State private var showShortcuts = false
    @State private var importingMIDI = false
    @State private var sidebarRevision = 0
    @State private var midiEditor: MIDIEditorModel?
    @State private var midiFailure: (name: String, message: String)?

    init(model: DocumentModel, store: ModelStore, access: AccessCoordinator, session: TranscriptionSession,
         workingFolder: WorkingFolderStore, library: LibraryStore, imports: AudioImportStore, preferences: AppPreferences,
         saveCoordinator: MIDISaveCoordinator) {
        self.model = model
        self.store = store
        self.access = access
        self.session = session
        self.workingFolder = workingFolder
        self.library = library
        self.imports = imports
        self.preferences = preferences
        self.saveCoordinator = saveCoordinator
        saveCoordinator.onSaved = { library.refresh() }
        _screen = State(initialValue: AudioScreenModel(document: model, store: store, session: session, access: access, preferences: preferences,
                                                       destination: { workingFolder.midiFolder }, references: { imports.references },
                                                       onSaved: { library.refresh() }))
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(library: library, workingFolder: workingFolder, imports: imports,
                               selection: gatedSelection, openAudio: { model.isImporting = true }, importingMIDI: $importingMIDI)
                .id(sidebarRevision)
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
        .environment(saveCoordinator)
        .environment(preferences)
        .focusedSceneValue(\.commandTarget, commandTarget)
        .sheet(isPresented: $showShortcuts) { KeyboardShortcutsView() }
        .background(WindowGuard(coordinator: saveCoordinator, edited: saveCoordinator.hasUnsavedChanges))
        .alert(saveFailureTitle, isPresented: Binding(get: { saveCoordinator.saveFailure != nil }, set: { if !$0 { saveCoordinator.dismissFailure() } })) {
            Button("OK") { saveCoordinator.dismissFailure() }
        } message: {
            Text(saveCoordinator.saveFailure?.message ?? "")
        }
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onChange(of: workingFolder.folder, initial: true) {
            library.attach(audio: workingFolder.audioFolder, midi: workingFolder.midiFolder)
        }
        .onChange(of: model.document?.url) { _, url in selection = url.map { .audio($0) } }
        .onChange(of: selection) { _, new in
            if case .audio(let url) = new, url != model.document?.url { model.open(url) }
            if case .midi(let url) = new {
                screen.playback.stop()
                loadMIDI(url)
            } else {
                closeMIDI()
            }
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

    /// Every way of changing the selection asks first when the open MIDI file has unsaved changes.
    private var gatedSelection: Binding<LibrarySelection?> {
        Binding(get: { selection }, set: { newValue in
            guard newValue != selection else { return }
            // A declined change leaves the List showing the row that was clicked; rebuilding it makes it show the real selection again.
            saveCoordinator.confirmLeaving(then: { selection = newValue }, cancelled: { sidebarRevision += 1 })
        })
    }

    /// What the menu bar sees of this window. The closures call the same actions the buttons do.
    private var commandTarget: AppCommandTarget {
        let editor = midiEditor
        let isMIDI = isMIDISelected && editor != nil
        let isAudio = !isMIDISelected && model.document != nil
        var target = AppCommandTarget()
        target.screen = isMIDI ? .midi : isAudio ? .audio : .empty
        target.canSave = isMIDI && (editor?.document.isDirty ?? false)
        target.canExport = isAudio && !session.notes.isEmpty
        target.hasSelection = isMIDI && !(editor?.document.selection.isEmpty ?? true)
        target.canQuantize = isMIDI && (editor.map { $0.document.snap != .off && !$0.document.notes.isEmpty } ?? false)
        target.canTranscribe = isAudio && screen.canStart
        target.isTranscribing = session.isBusy || screen.isPreparing
        target.canResetSlice = isAudio
        target.canDetectKey = isAudio && !screen.isDetectingKey
        let transport = isMIDI ? editor?.playback : isAudio ? screen.playback : nil
        target.canPlay = transport != nil
        target.isPlaying = transport?.isPlaying ?? false
        target.isLooping = transport?.loops ?? false
        target.canSelectAudio = model.document != nil || !library.audio.isEmpty
        target.canSelectMIDI = !library.midi.isEmpty
        target.hasWorkingFolder = workingFolder.folder != nil
        target.tool = isMIDI ? editor?.tool : nil
        target.inspectorShown = showInspector

        target.openAudio = { model.isImporting = true }
        target.importMIDI = { importingMIDI = true }
        target.save = { saveCoordinator.saveOpenFile() }
        target.export = { screen.showExport = true }
        target.showWorkingFolder = {
            if let folder = workingFolder.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
        }
        target.deleteSelection = { editor?.document.deleteSelection() }
        target.transposeUp = { editor?.document.transpose(by: 1) }
        target.transposeDown = { editor?.document.transpose(by: -1) }
        target.quantize = { editor?.document.quantize() }
        target.transcribe = { screen.start() }
        target.cancelTranscription = { screen.cancel() }
        target.resetSlice = { model.slice.reset() }
        target.detectKey = { screen.detectKeyFromAudio() }
        target.toggleInspector = { showInspector.toggle() }
        target.zoomIn = { zoom(by: 1.25) }
        target.zoomOut = { zoom(by: 0.8) }
        target.setTool = { editor?.tool = $0 }
        target.togglePlayback = { if isMIDI { editor?.togglePlayback() } else { screen.togglePlayback() } }
        target.stop = { transport?.stop() }
        target.toggleLoop = { transport?.loops.toggle() }
        target.selectAudio = {
            if let url = model.document?.url ?? library.audio.first(where: { !$0.isMissing })?.url { gatedSelection.wrappedValue = .audio(url) }
        }
        target.selectMIDI = {
            if let url = library.midi.first?.url { gatedSelection.wrappedValue = .midi(url) }
        }
        target.showWelcome = { showWelcome = true }
        target.showShortcuts = { showShortcuts = true }
        return target
    }

    private func zoom(by factor: CGFloat) {
        if isMIDISelected, let midiEditor {
            midiEditor.pixelsPerSecond = min(400, max(30, midiEditor.pixelsPerSecond * factor))
        } else {
            screen.pixelsPerSecond = min(400, max(10, screen.pixelsPerSecond * factor))
        }
    }

    private var saveFailureTitle: String {
        "Could not save \u{201C}\(saveCoordinator.saveFailure?.name ?? "")\u{201D}"
    }

    private func openAudio(_ url: URL) {
        saveCoordinator.confirmLeaving(then: { importAndOpen(url) })
    }

    /// Copies or references the audio as the user prefers, then opens it.
    private func importAndOpen(_ url: URL) {
        do {
            let target = try imports.importAudio(from: url, mode: preferences.addAudioMode,
                                                 audioFolder: workingFolder.audioFolder)
            library.refresh()
            model.open(target)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func loadMIDI(_ url: URL) {
        closeMIDI()
        do {
            midiEditor = try MIDIEditorModel.load(url)
            saveCoordinator.editor = midiEditor
            midiFailure = nil
        } catch {
            midiFailure = (url.lastPathComponent, error.localizedDescription)
        }
    }

    private func closeMIDI() {
        midiEditor?.playback.stop()
        midiEditor?.document.closeUndo()
        midiEditor = nil
        saveCoordinator.editor = nil
        midiFailure = nil
    }

    @ViewBuilder private var detail: some View {
        if case .midi(let url) = selection {
            if let midiEditor, midiEditor.url == url {
                MIDIEditorView(editor: midiEditor).id(midiEditor.id)
            } else if let midiFailure {
                ContentUnavailableView("Could not open \u{201C}\(midiFailure.name)\u{201D}", systemImage: "exclamationmark.triangle",
                                       description: Text(midiFailure.message))
            } else {
                ProgressView()
            }
        } else if model.document == nil {
            DropZoneView(onOpen: openAudio, onChooseFile: { model.isImporting = true },
                         folderPath: workingFolder.folder.map { $0.abbreviatedPath + "/" })
        } else {
            AudioDetailView(screen: screen, onOpenAudio: openAudio)
        }
    }

    private var inspector: some View {
        Group {
            if isMIDISelected {
                if let midiEditor {
                    MIDIEditorInspectorView(editor: midiEditor)
                } else {
                    ContentUnavailableView("No MIDI File", systemImage: "pianokeys")
                }
            } else if model.document != nil {
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
        if case .midi = selection {
            guard let editor = midiEditor else { return "" }
            let count = editor.document.notes.count
            let origin = editor.provenance.map { $0.edited ? "Edited" : "From audio" } ?? "Imported"
            return "\(count) \(count == 1 ? "note" : "notes") \u{00B7} \(origin)"
        }
        guard let document = model.document else { return "" }
        return String(format: "%.1f s · %@", document.duration, sampleRateText(document.sampleRate))
    }

    private func sampleRateText(_ rate: Double) -> String {
        "\((rate / 1000).formatted(.number.precision(.fractionLength(0...2)))) kHz"
    }
}
