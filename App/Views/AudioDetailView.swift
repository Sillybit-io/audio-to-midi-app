import SwiftUI

/// State shared by the Audio screen and its inspector.
@MainActor @Observable
final class AudioScreenModel {
    /// What the status panel shows above the roll.
    enum RunPanel: Equatable {
        case running(title: String, steps: [String], current: Int, fraction: Double?)
        case failed(title: String, message: String)
    }

    /// What the last run used, for the result summary and to notice that the settings changed since.
    struct RunRecord: Equatable {
        var modelID: String
        var modelName: String
        var start: Double
        var end: Double
        var instruments: Set<String>
        var estimatesVelocity: Bool
        /// Whole seconds from pressing Transcribe to the end, download included.
        var took: Int?
    }

    let document: DocumentModel
    let store: ModelStore
    let session: TranscriptionSession
    let access: AccessCoordinator
    let firstUse: FirstUseTranscription
    let writer = TranscriptionWriter()
    let playback = PlaybackEngine()

    var selectedModel: ModelEntry.ID? {
        didSet { downloadFailure = nil }
    }
    var deviceIndex: Int?
    var threads = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    var chosenInstruments: Set<String> = []
    var hiddenInstruments: Set<String> = []
    /// Muting affects playback only; hiding takes notes out of the roll and playback.
    var mutedInstruments: Set<String> = []
    var estimateVelocity = true
    var pixelsPerSecond: CGFloat = Metric.ppsDefault
    var showExport = false
    private(set) var keyFromAudio: [KeyMatch] = []
    private(set) var isDetectingKey = false
    private(set) var devices: [EngineDevice] = []
    private(set) var instruments: [EngineInstrument] = []
    private(set) var engine: EngineProcess?
    private(set) var engineProblem: String?
    private(set) var startedAt: Date?
    private(set) var downloadFailure: (entry: ModelEntry, message: String)?
    /// The failed panel was dismissed; it stays hidden until the next run.
    private(set) var failureDismissed = false
    private(set) var ran: RunRecord?
    @ObservationIgnored private var includesDownload: ModelEntry?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    /// The run in flight; it is consumed by the first terminal state, so a run is saved once.
    @ObservationIgnored private var run: TranscriptionWriter.Run?
    @ObservationIgnored private let destination: () -> URL?
    @ObservationIgnored private let references: () -> [AudioReference]
    @ObservationIgnored private let onSaved: () -> Void

    /// `destination` is the MIDI folder to save results in; `onSaved` lets the library pick the new file up.
    init(document: DocumentModel, store: ModelStore, session: TranscriptionSession, access: AccessCoordinator,
         preferences: AppPreferences, settle: Duration = .milliseconds(400), destination: @escaping () -> URL? = { nil },
         references: @escaping () -> [AudioReference] = { [] }, onSaved: @escaping () -> Void = {}) {
        self.document = document
        self.store = store
        self.session = session
        self.access = access
        self.destination = destination
        self.references = references
        self.onSaved = onSaved
        firstUse = FirstUseTranscription(installer: store, settle: settle)
        selectedModel = preferences.defaultModelID
        observeSession()
    }

    /// Watches the session for the end of a run. This lives on the model, not on a view, so a run that finishes
    /// while another screen is showing is still saved.
    private func observeSession() {
        withObservationTracking {
            _ = session.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sessionStateChanged()
                self?.observeSession()
            }
        }
    }

    func sessionStateChanged() {
        switch session.state {
        case .done, .cancelled, .failed:
            if ran?.took == nil, let startedAt { ran?.took = Int(Date().timeIntervalSince(startedAt).rounded()) }
        case .idle, .loading, .running, .refining:
            break
        }
        guard let run else { return }
        switch session.state {
        case .done, .cancelled:
            self.run = nil
            writer.finish(session.state, notes: session.notes, run: run, folder: destination())
            if case .saved = writer.status { onSaved() }
        case .failed:
            self.run = nil
        case .idle, .loading, .running, .refining:
            break
        }
    }

    func retrySave() {
        writer.retry(folder: destination())
        if case .saved = writer.status { onSaved() }
    }

    var selectedEntry: ModelEntry? {
        ModelCatalog.entries.first { $0.id == selectedModel }
    }

    var presentInstruments: [String] {
        Array(Set(session.notes.map(\.instrument))).sorted()
    }

    /// Each instrument in the result with its note count, in name order.
    var instrumentCounts: [(name: String, count: Int)] {
        Dictionary(grouping: session.notes, by: \.instrument).map { ($0.key, $0.value.count) }.sorted { $0.name < $1.name }
    }

    /// Playback groups to switch off for muted or hidden instruments. No note is changed.
    var silencedGroups: Set<String> {
        let off = mutedInstruments.union(hiddenInstruments)
        return Set(session.notes.filter { off.contains($0.instrument) }.map(PlaybackEngine.groupKey))
    }

    /// Basic Pitch reports one undifferentiated track, which the handoff draws in the neutral colour.
    var usesNeutralColour: Bool { (ran?.modelID ?? selectedModel) == AppPreferences.fallbackModelID }

    /// The model, slice, instruments or velocity setting differ from the run that produced the notes on screen.
    var settingsChanged: Bool {
        guard let ran else { return false }
        if ran.modelID != selectedModel || ran.start != document.slice.start || ran.end != document.slice.end { return true }
        guard selectedEntry?.engine == .muscriptor else { return false }
        return ran.instruments != chosenInstruments || ran.estimatesVelocity != estimateVelocity
    }

    var summary: String {
        Self.summary(state: session.state, noteCount: session.notes.count, instrumentCount: Set(session.notes.map(\.instrument)).count,
                     ran: ran, changed: settingsChanged)
    }

    /// The footer's run summary, in the handoff's wording.
    static func summary(state: TranscriptionSession.State, noteCount: Int, instrumentCount: Int, ran: RunRecord?, changed: Bool) -> String {
        let range = ran.map { String(format: "%.1f\u{2013}%.1f s", $0.start, $0.end) } ?? ""
        switch state {
        case .loading, .running, .refining:
            guard let ran else { return "Transcribing\u{2026}" }
            return "Transcribing \(range) with \(ran.modelName)\u{2026}"
        case .idle, .done, .cancelled, .failed:
            guard noteCount > 0, let ran else { return "No notes yet" }
            var text: String
            if case .done = state {
                text = "Done \u{2014} \(noteCount) notes \u{00B7} "
            } else {
                text = "Cancelled \u{2014} partial notes kept \u{00B7} "
            }
            text += "\(instrumentCount) \(instrumentCount == 1 ? "instrument" : "instruments") \u{00B7} \(range) \u{00B7} \(ran.modelName)"
            if let took = ran.took { text += " \u{00B7} \(took) s" }
            if changed { text += " \u{00B7} Changed \u{2014} transcribe again to apply" }
            return text
        }
    }

    var isPreparing: Bool { prepareTask != nil }

    var canStart: Bool {
        guard document.document != nil, !session.isBusy, !isPreparing, let entry = selectedEntry else { return false }
        guard store.state(for: entry) == .installed || entry.downloadURL != nil else { return false }
        return entry.engine != .muscriptor || engine != nil
    }

    var transcribeLabel: String {
        if session.isBusy || isPreparing { return "Transcribing…" }
        guard let entry = selectedEntry else { return "Transcribe" }
        if store.state(for: entry) != .installed { return "Download & Transcribe" }
        switch session.state {
        case .done, .cancelled: return "Transcribe Again"
        default: return "Transcribe"
        }
    }

    var runPanel: RunPanel? {
        if let failure = downloadFailure {
            return .failed(title: "Couldn\u{2019}t download \(failure.entry.displayName)", message: failure.message)
        }
        var steps: [String] = []
        var offset = 0
        if let entry = includesDownload {
            steps = ["Download \(entry.sizeText)", "Verify SHA-256"]
            offset = 2
        }
        steps += ["Load model", "Transcribe"]
        if estimateVelocity, selectedEntry?.engine == .muscriptor { steps.append("Estimate velocity") }
        if isPreparing, let entry = includesDownload {
            switch store.state(for: entry) {
            case .downloading(let value):
                return .running(title: Self.downloadTitle(entry, fraction: value), steps: steps, current: 0, fraction: value)
            case .verifying: return .running(title: "Verifying download (SHA-256)", steps: steps, current: 1, fraction: nil)
            default: return .running(title: Self.downloadTitle(entry, fraction: 0), steps: steps, current: 0, fraction: nil)
            }
        }
        switch session.state {
        case .loading(let value): return .running(title: "Loading model", steps: steps, current: offset, fraction: value)
        case .running:
            let title = session.progress > 0.15 ? session.eta.map { "About \(Int($0.rounded(.up))) s left" } ?? "Transcribing" : "Transcribing"
            return .running(title: title, steps: steps, current: offset + 1, fraction: session.progress)
        case .refining: return .running(title: "Estimating velocity", steps: steps, current: offset + 2, fraction: nil)
        case .failed(let message): return failureDismissed ? nil : .failed(title: "Transcription failed", message: message)
        default: return nil
        }
    }

    /// `Downloading {model} · {n} of {size}`, with n in the size's unit like the prototype (\u{201C}42 of 209 MB\u{201D}).
    static func downloadTitle(_ entry: ModelEntry, fraction: Double) -> String {
        let megabytes = Double(entry.byteSize) / 1_000_000
        return "Downloading \(entry.displayName) \u{00B7} \(Int((min(max(fraction, 0), 1) * megabytes).rounded())) of \(entry.sizeText)"
    }

    func loadEngineInfo() async {
        do {
            let process = EngineProcess(executable: try EngineLocator.locate())
            engine = process
            devices = try await process.devices()
            instruments = try await process.instruments()
            #if arch(x86_64)
            deviceIndex = devices.first { $0.backend == "CPU" }?.index
            #endif
        } catch {
            engineProblem = error.localizedDescription
        }
    }

    func audioForKey() -> (samples: [Float], rate: Double)? {
        guard let audio = document.document else { return nil }
        return (document.slice.cut(audio.samples, sampleRate: audio.sampleRate), audio.sampleRate)
    }

    func prepareOriginal() {
        guard let audio = document.document else { return }
        playback.duration = document.slice.span
        playback.setOriginal(samples: document.slice.cut(audio.samples, sampleRate: audio.sampleRate), sampleRate: audio.sampleRate)
    }

    /// Moves the playhead within the slice.
    func seek(to seconds: Double) {
        playback.duration = document.slice.span
        playback.seek(to: seconds)
    }

    func togglePlayback() {
        if playback.isPlaying {
            playback.pause()
        } else {
            prepareOriginal()
            playback.play()
        }
    }

    func clearKeyFromAudio() {
        keyFromAudio = []
    }

    /// Another audio file is open, so the notes, summary and save line on screen belonged to the last one.
    /// A run still going is cancelled first and its partial notes are saved for the file it was transcribing.
    func documentChanged() {
        if session.isBusy || prepareTask != nil {
            cancel()
            sessionStateChanged()
        }
        run = nil
        ran = nil
        startedAt = nil
        includesDownload = nil
        downloadFailure = nil
        failureDismissed = false
        hiddenInstruments = []
        mutedInstruments = []
        writer.reset()
        session.clear()
        clearKeyFromAudio()
    }

    /// Ranks the keys of the selected slice of the audio itself.
    func detectKeyFromAudio() {
        guard !isDetectingKey, let audio = audioForKey() else { return }
        isDetectingKey = true
        Task {
            let result = await Task.detached { KeyDetector.rank(samples: audio.samples, sampleRate: audio.rate) }.value
            keyFromAudio = result
            isDetectingKey = false
        }
    }

    /// Hides the failed panel and the library row's warning until the next run. The notes on screen stay.
    func dismissFailure() {
        downloadFailure = nil
        failureDismissed = true
    }

    /// Stops a run, a download, or a wait on the first-use alert or the licence sheet.
    func cancel() {
        prepareTask?.cancel()
        firstUse.answerConsent(false)
        if access.request != nil { access.finish(agreed: false) }
        session.cancel()
    }

    /// Transcribes the slice, first fetching the model when it isn't on the disk yet.
    func start() {
        guard canStart, let entry = selectedEntry else { return }
        downloadFailure = nil
        failureDismissed = false
        startedAt = Date()
        if store.state(for: entry) == .installed {
            includesDownload = nil
            launch(entry)
            return
        }
        includesDownload = entry
        prepareTask = Task { [weak self] in
            guard let self else { return }
            switch await firstUse.prepare(entry) {
            case .ready: launch(entry)
            case .cancelled: includesDownload = nil
            case .failed(let message):
                downloadFailure = (entry, message)
                includesDownload = nil
            }
            prepareTask = nil
        }
    }

    private func launch(_ entry: ModelEntry) {
        guard let audio = document.document else { return }
        run = TranscriptionWriter.Run(source: audio.url, sourceID: TranscriptionWriter.sourceIdentifier(for: audio.url, references: references()),
                                      title: audio.name, modelID: entry.id, notice: entry.exportNotice, slice: document.slice)
        ran = RunRecord(modelID: entry.id, modelName: entry.displayName, start: document.slice.start, end: document.slice.end,
                        instruments: chosenInstruments, estimatesVelocity: estimateVelocity, took: nil)
        writer.reset()
        let samples = document.slice.cut(audio.samples, sampleRate: audio.sampleRate)
        let rate = audio.sampleRate
        let device = deviceIndex.map(String.init) ?? "auto"
        let names = chosenInstruments.sorted()
        let count = threads
        if entry.engine == .basicPitch {
            session.start { BasicPitchEngine().stream(samples: samples, sourceRate: rate) }
            return
        }
        guard let modelURL = store.installedURL(for: entry) else { return }
        if entry.engine == .pianoOnnx {
            let piano = PianoOnnxEngine(modelURL: modelURL, threads: count)
            session.start {
                let resampled = try await Task.detached { try Resampler.resample(samples, from: rate, to: PianoOnnxEngine.sampleRate) }.value
                return piano.stream(samples: resampled)
            }
            return
        }
        let process = engine
        let audio16 = Task.detached { try Resampler.resample(samples, from: rate, to: 16000) }
        var refine: (@Sendable ([NoteEvent]) async -> [NoteEvent])?
        if estimateVelocity {
            refine = { (notes: [NoteEvent]) async -> [NoteEvent] in
                guard let audio = try? await audio16.value else { return notes }
                return await Task.detached { VelocityEstimator.estimate(notes: notes, samples: audio, sampleRate: 16000) }.value
            }
        }
        session.start(refine: refine) {
            let resampled = try await audio16.value
            guard let process else { throw EngineLocatorError.missing }
            return process.transcribe(model: modelURL, samples: resampled, device: device, threads: count, instruments: names)
        }
    }
}

struct AudioDetailView: View {
    @Bindable var screen: AudioScreenModel
    let onOpenAudio: (URL) -> Void
    /// Opens a saved transcription in the MIDI editor.
    var onEditMIDI: (URL) -> Void = { _ in }
    @Environment(AppPreferences.self) private var preferences
    @FocusState private var focused: Bool

    private var model: DocumentModel { screen.document }
    private var session: TranscriptionSession { screen.session }
    private var playback: PlaybackEngine { screen.playback }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = screen.engineProblem {
                Text(problem).foregroundStyle(Native.danger).padding(Metric.sp4)
            }
            WaveformSliceView(model: model, onSeek: screen.seek)
            AudioStatusView(panel: screen.runPanel, startedAt: screen.startedAt,
                            onCancel: screen.cancel, onRetry: screen.start, onDismiss: screen.dismissFailure)
                .padding(.horizontal, Metric.sp6)
            PianoRollView(notes: session.notes, duration: model.slice.span, finalizedThrough: session.finalizedThrough,
                          playhead: playback.position, hidden: screen.hiddenInstruments,
                          pixelsPerSecond: $screen.pixelsPerSecond, follows: preferences.followPlayhead, onSeek: screen.seek,
                          neutralColour: screen.usesNeutralColour,
                          showsEmptyState: session.notes.isEmpty && session.state == .idle && !screen.isPreparing)
                .onTapGesture { focused = true }
            Divider()
            AudioFooterView(screen: screen, onEditMIDI: onEditMIDI)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onOpenAudio(url)
            return true
        }
        .task { await screen.loadEngineInfo() }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress { press in
            guard press.modifiers.isEmpty else { return .ignored }
            if press.characters == " " {
                screen.togglePlayback()
            } else if press.characters.lowercased() == "l" {
                playback.loops.toggle()
            } else {
                return .ignored
            }
            return .handled
        }
        .alert(consentTitle, isPresented: Binding(get: { screen.firstUse.consentRequest != nil }, set: { _ in })) {
            Button("Review Licence…") { screen.firstUse.answerConsent(true) }
            Button("Cancel", role: .cancel) { screen.firstUse.answerConsent(false) }
        } message: {
            Text("The model file is downloaded once and kept on your Mac.")
        }
        .onChange(of: session.notes.count) { playback.sync(notes: session.notes) }
        .onChange(of: session.finalizedThrough) { playback.limit = session.isBusy ? session.finalizedThrough : nil }
        .onChange(of: session.state) { playback.limit = session.isBusy ? session.finalizedThrough : nil }
        .onChange(of: model.slice) { playback.duration = model.slice.span }
        .onChange(of: model.document?.url) { screen.documentChanged() }
        .onChange(of: screen.silencedGroups, initial: true) { _, groups in playback.setSilenced(groups) }
        .toolbar {
            ToolbarItem {
                TransportView(playback: playback, toggle: screen.togglePlayback)
            }
            ToolbarItem {
                TranscribeButton(label: screen.transcribeLabel, isBusy: session.isBusy, isPrimary: !isRepeat,
                                 canStart: screen.canStart, action: screen.start)
            }
            ToolbarItem {
                ExportView(notes: session.notes, entry: screen.selectedEntry,
                           slice: model.slice, name: model.document?.name ?? "transcription", showNotice: $screen.showExport)
            }
        }
    }

    private var consentTitle: String {
        guard let entry = screen.firstUse.consentRequest else { return "" }
        return "\(entry.displayName) downloads on first use (\(entry.sizeText))"
    }

    private var isRepeat: Bool {
        switch session.state {
        case .done, .cancelled: true
        default: false
        }
    }
}

struct AudioFooterView: View {
    @Bindable var screen: AudioScreenModel
    let onEditMIDI: (URL) -> Void

    private var playback: PlaybackEngine { screen.playback }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metric.sp6) {
                summaryText
                Spacer(minLength: Metric.sp4)
                mixControl
                speedControl
                zoomControl
            }
            VStack(alignment: .leading, spacing: Metric.sp3) {
                HStack { summaryText; Spacer(); zoomControl }
                HStack(spacing: Metric.sp6) { mixControl; speedControl; Spacer(minLength: 0) }
            }
            VStack(alignment: .leading, spacing: Metric.sp3) {
                summaryText
                mixControl
                speedControl
                zoomControl
            }
        }
        .padding(.horizontal, Metric.sp6).padding(.vertical, Metric.sp4)
    }

    private var summaryText: some View {
        VStack(alignment: .leading, spacing: Metric.sp1) {
            HStack(spacing: Metric.sp3) {
                Text(screen.summary).font(.caption).foregroundStyle(Native.fgSecondary).lineLimit(1)
                if let url = savedURL, !screen.session.isBusy {
                    Button("Edit MIDI") { onEditMIDI(url) }.buttonStyle(.link).font(.caption).fixedSize()
                }
            }
            saveLine
            if let message = playback.lastError { Text(message).font(.caption).foregroundStyle(Native.danger) }
        }
    }

    @ViewBuilder private var saveLine: some View {
        switch screen.writer.status {
        case .idle:
            EmptyView()
        case .saved(let url, let partial):
            Text("\(partial ? "Partial result saved" : "Saved") to MIDI/\(url.lastPathComponent)")
                .font(.caption).foregroundStyle(Native.fgSecondary).lineLimit(1)
        case .keptPrevious(let url):
            Text("Kept the earlier result in MIDI/\(url.lastPathComponent)").font(.caption).foregroundStyle(Native.fgSecondary).lineLimit(1)
        case .empty:
            Text("No notes found, so nothing was saved.").font(.caption).foregroundStyle(Native.fgSecondary).lineLimit(1)
        case .failed(let message):
            HStack(spacing: Metric.sp3) {
                Text(message).font(.caption).foregroundStyle(Native.danger).lineLimit(2)
                Button("Try Saving Again", action: screen.retrySave).controlSize(.small)
            }
        }
    }

    private var mixControl: some View {
        HStack(spacing: Metric.sp3) {
            Text("Original").font(.caption).fixedSize()
            Slider(value: Binding(get: { playback.mix }, set: { playback.mix = $0 }))
                .frame(width: Metric.mixSliderW).accessibilityLabel("Original and notes mix")
            Text("Notes").font(.caption).fixedSize()
        }
    }

    private var speedControl: some View {
        HStack(spacing: Metric.sp3) {
            Text("Speed").font(.caption).fixedSize()
            Slider(value: Binding(get: { Double(playback.rate) }, set: { playback.rate = Float($0) }), in: 0.5...2)
                .frame(width: Metric.sliderW).accessibilityLabel("Playback speed")
            Text(String(format: "%.2f×", playback.rate)).font(.caption.monospacedDigit()).frame(width: Metric.readoutW, alignment: .leading)
        }
    }

    private var zoomControl: some View {
        HStack(spacing: Metric.sp3) {
            Image(systemName: "minus").font(.caption)
            Slider(value: Binding(get: { Double(screen.pixelsPerSecond) }, set: { screen.pixelsPerSecond = CGFloat($0) }), in: Double(Metric.ppsMin)...Double(Metric.ppsMax))
                .frame(width: Metric.sliderW).accessibilityLabel("Zoom")
            Image(systemName: "plus").font(.caption)
        }
    }

    /// The file the last run was saved to (or left in place), for the Edit MIDI link.
    private var savedURL: URL? {
        switch screen.writer.status {
        case .saved(let url, _), .keptPrevious(let url): url
        case .idle, .empty, .failed: nil
        }
    }
}
