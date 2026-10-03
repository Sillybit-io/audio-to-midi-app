import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: DocumentModel
    let store: ModelStore
    @Bindable var access: AccessCoordinator
    let session: TranscriptionSession

    @State private var showModels = false
    @State private var selectedModel: ModelEntry.ID?
    @State private var deviceIndex: Int?
    @State private var threads = max(1, ProcessInfo.processInfo.performanceCoreCount)
    @State private var devices: [EngineDevice] = []
    @State private var instruments: [EngineInstrument] = []
    @State private var chosenInstruments: Set<String> = []
    @State private var hiddenInstruments: Set<String> = []
    @State private var engine: EngineProcess?
    @State private var engineProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            if let engineProblem {
                Text(engineProblem).foregroundStyle(.red).padding(8)
            }
            if model.document == nil {
                DropZoneView(model: model)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    WaveformSliceView(model: model)
                    TranscribeToolbar(store: store, session: session, devices: devices, modelID: $selectedModel,
                                      deviceIndex: $deviceIndex, threads: $threads, canStart: canStart, onStart: start)
                        .padding(.horizontal)
                    InstrumentChipsView(instruments: instruments, selection: $chosenInstruments).padding(.horizontal)
                    InstrumentLegendView(instruments: presentInstruments, hidden: $hiddenInstruments).padding(.horizontal)
                    PianoRollView(notes: session.notes, duration: model.slice.span, finalizedThrough: session.finalizedThrough,
                                  hidden: hiddenInstruments)
                        .frame(minHeight: 180)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    model.open(url)
                    return true
                }
            }
        }
        .task { await loadEngineInfo() }
        .toolbar { Button("Models") { showModels = true } }
        .sheet(isPresented: $showModels) {
            VStack { ModelPickerView(store: store, selection: $selectedModel); Button("Done") { showModels = false }.padding() }
                .frame(width: 640, height: 360)
        }
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

    private var presentInstruments: [String] {
        Array(Set(session.notes.map(\.instrument))).sorted()
    }

    private var canStart: Bool {
        engine != nil && model.document != nil && selectedModel != nil && !session.isBusy
    }

    private func loadEngineInfo() async {
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

    private func start() {
        guard let engine, let document = model.document,
              let entry = ModelCatalog.entries.first(where: { $0.id == selectedModel }),
              let modelURL = store.installedURL(for: entry) else { return }
        let samples = model.slice.cut(document.samples, sampleRate: document.sampleRate)
        let rate = document.sampleRate
        let device = deviceIndex.map(String.init) ?? "auto"
        let names = chosenInstruments.sorted()
        let count = threads
        session.start {
            let resampled = try await Task.detached { try Resampler.resample(samples, from: rate, to: 16000) }.value
            return engine.transcribe(model: modelURL, samples: resampled, device: device, threads: count, instruments: names)
        }
    }
}

private extension ProcessInfo {
    var performanceCoreCount: Int { max(1, activeProcessorCount / 2) }
}
