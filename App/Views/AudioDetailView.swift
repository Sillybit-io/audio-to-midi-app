import SwiftUI

/// State shared by the Audio screen and its inspector.
@MainActor @Observable
final class AudioScreenModel {
    let document: DocumentModel
    let store: ModelStore
    let session: TranscriptionSession
    let playback = PlaybackEngine()

    var selectedModel: ModelEntry.ID? = "basic-pitch"
    var deviceIndex: Int?
    var threads = max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    var chosenInstruments: Set<String> = []
    var hiddenInstruments: Set<String> = []
    var estimateVelocity = true
    var pixelsPerSecond: CGFloat = Metric.ppsDefault
    private(set) var devices: [EngineDevice] = []
    private(set) var instruments: [EngineInstrument] = []
    private(set) var engine: EngineProcess?
    private(set) var engineProblem: String?
    private(set) var startedAt: Date?

    init(document: DocumentModel, store: ModelStore, session: TranscriptionSession) {
        self.document = document
        self.store = store
        self.session = session
    }

    var selectedEntry: ModelEntry? {
        ModelCatalog.entries.first { $0.id == selectedModel }
    }

    var presentInstruments: [String] {
        Array(Set(session.notes.map(\.instrument))).sorted()
    }

    var canStart: Bool {
        guard document.document != nil, !session.isBusy, let entry = selectedEntry,
              store.state(for: entry) == .installed else { return false }
        return entry.engine != .muscriptor || engine != nil
    }

    var transcribeLabel: String {
        if session.isBusy { return "Transcribing…" }
        guard let entry = selectedEntry else { return "Transcribe" }
        if store.state(for: entry) != .installed { return "Download & Transcribe" }
        switch session.state {
        case .done, .cancelled: return "Transcribe Again"
        default: return "Transcribe"
        }
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

    func cancel() { session.cancel() }

    func start() {
        guard canStart, let audio = document.document, let entry = selectedEntry else { return }
        let samples = document.slice.cut(audio.samples, sampleRate: audio.sampleRate)
        let rate = audio.sampleRate
        let device = deviceIndex.map(String.init) ?? "auto"
        let names = chosenInstruments.sorted()
        let count = threads
        startedAt = Date()
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

    private var model: DocumentModel { screen.document }
    private var session: TranscriptionSession { screen.session }
    private var playback: PlaybackEngine { screen.playback }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = screen.engineProblem {
                Text(problem).foregroundStyle(Native.danger).padding(Metric.sp4)
            }
            WaveformSliceView(model: model)
            AudioStatusView(session: session, startedAt: screen.startedAt,
                            estimatesVelocity: screen.estimateVelocity && screen.selectedEntry?.engine == .muscriptor,
                            onCancel: screen.cancel, onRetry: screen.start)
                .padding(.horizontal, Metric.sp6)
            PianoRollView(notes: session.notes, duration: model.slice.span, finalizedThrough: session.finalizedThrough,
                          playhead: playback.position, hidden: screen.hiddenInstruments,
                          pixelsPerSecond: $screen.pixelsPerSecond,
                          showsEmptyState: session.notes.isEmpty && session.state == .idle)
            Divider()
            AudioFooterView(screen: screen)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onOpenAudio(url)
            return true
        }
        .task { await screen.loadEngineInfo() }
        .onChange(of: session.notes.count) { playback.sync(notes: session.notes) }
        .onChange(of: session.finalizedThrough) { playback.limit = session.isBusy ? session.finalizedThrough : nil }
        .onChange(of: session.state) { playback.limit = session.isBusy ? session.finalizedThrough : nil }
        .onChange(of: model.slice) { playback.duration = model.slice.span }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    if playback.isPlaying { playback.pause() } else { screen.prepareOriginal(); playback.play() }
                } label: {
                    Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(playback.isPlaying ? "Pause" : "Play")
                Button { playback.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .help("Stop")
                Text(String(format: "%.1f s", playback.position))
                    .monospacedDigit().foregroundStyle(Native.fgSecondary)
                    .accessibilityLabel("Playback position")
            }
            ToolbarItem {
                TranscribeButton(label: screen.transcribeLabel, isBusy: session.isBusy, isPrimary: !isRepeat,
                                 canStart: screen.canStart, action: screen.start)
            }
            ToolbarItem {
                ExportView(notes: session.notes, entry: screen.selectedEntry,
                           slice: model.slice, name: model.document?.name ?? "transcription")
            }
        }
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
            Text(summary).font(.caption).foregroundStyle(Native.fgSecondary).lineLimit(1)
            if let message = playback.lastError { Text(message).font(.caption).foregroundStyle(Native.danger) }
        }
    }

    private var mixControl: some View {
        HStack(spacing: Metric.sp3) {
            Text("Original").font(.caption)
            Slider(value: Binding(get: { playback.mix }, set: { playback.mix = $0 }))
                .frame(width: 90).accessibilityLabel("Original and notes mix")
            Text("Notes").font(.caption)
        }
    }

    private var speedControl: some View {
        HStack(spacing: Metric.sp3) {
            Text("Speed").font(.caption)
            Slider(value: Binding(get: { Double(playback.rate) }, set: { playback.rate = Float($0) }), in: 0.5...2)
                .frame(width: 80).accessibilityLabel("Playback speed")
            Text(String(format: "%.2f×", playback.rate)).font(.caption.monospacedDigit()).frame(width: 40, alignment: .leading)
        }
    }

    private var zoomControl: some View {
        HStack(spacing: Metric.sp3) {
            Image(systemName: "minus").font(.caption)
            Slider(value: Binding(get: { Double(screen.pixelsPerSecond) }, set: { screen.pixelsPerSecond = CGFloat($0) }), in: 10...400)
                .frame(width: 80).accessibilityLabel("Zoom")
            Image(systemName: "plus").font(.caption)
        }
    }

    private var summary: String {
        let count = screen.session.notes.count
        switch screen.session.state {
        case .idle: return count == 0 ? "No notes yet" : "\(count) notes"
        case .loading, .running, .refining: return "Transcribing… \(count) notes so far"
        case .done(let total): return "Done — \(total) notes"
        case .cancelled: return "Cancelled — partial notes kept · \(count) notes"
        case .failed: return "Transcription failed"
        }
    }
}
