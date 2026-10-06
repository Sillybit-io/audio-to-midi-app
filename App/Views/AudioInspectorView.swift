import SwiftUI

extension ModelEntry {
    /// "209 MB", "2.74 GB": the size shown next to a model that still has to be downloaded.
    var sizeText: String {
        byteSize >= 1_000_000_000
            ? String(format: "%.2f GB", Double(byteSize) / 1_000_000_000)
            : String(format: "%.0f MB", Double(byteSize) / 1_000_000)
    }
}

struct AudioInspectorView: View {
    @Bindable var screen: AudioScreenModel
    @Environment(\.openSettings) private var openSettings
    @AppStorage("settingsTab") private var settingsTab = "general"

    private static let manageTag = "manage"

    private var session: TranscriptionSession { screen.session }
    private var entry: ModelEntry? { screen.selectedEntry }

    var body: some View {
        Form {
            modelSection
            if entry?.engine == .muscriptor {
                Section {
                    InstrumentChipsView(instruments: screen.instruments, selection: $screen.chosenInstruments)
                } header: {
                    HStack { Text("Instruments"); Spacer(); Text(screen.chosenInstruments.isEmpty ? "automatic" : "\(screen.chosenInstruments.count) selected") }
                } footer: {
                    Text("Leave all off to let MuScriptor detect instruments automatically.")
                }
            }
            Section("Velocity") {
                if entry?.engine == .muscriptor {
                    Toggle(isOn: $screen.estimateVelocity) {
                        VStack(alignment: .leading, spacing: Metric.sp1) {
                            Text("Estimate note velocity from the audio")
                            Text("MuScriptor has none. Reflects relative loudness, not playing force.")
                                .font(.caption).foregroundStyle(Native.fgSecondary)
                        }
                    }
                } else {
                    Text(entry?.engine == .pianoOnnx ? "Predicted by the piano model." : "Taken from the note amplitude Basic Pitch reports.")
                        .foregroundStyle(Native.fgSecondary)
                }
            }
            SliceFieldsSection(model: screen.document)
            Section {
                KeyView(notes: session.notes, fromAudio: screen.keyFromAudio, busy: screen.isDetectingKey, detect: screen.detectKeyFromAudio)
            } header: {
                Text("Key")
            } footer: {
                Text("Ranks major, minor and five more modes in all twelve keys. Similar modes can score closely.")
            }
            if !screen.presentInstruments.isEmpty {
                Section("Instruments in Result") {
                    InstrumentLegendView(counts: screen.instrumentCounts, neutral: screen.usesNeutralColour,
                                         muted: $screen.mutedInstruments, hidden: $screen.hiddenInstruments)
                }
            }
            Section {
                MIDIDragChip(notes: session.notes, entry: entry, slice: screen.document.slice,
                             name: screen.document.document?.name ?? "transcription")
            } header: {
                Text("Export")
            } footer: {
                Text("Drag the file into Finder or your DAW, or use Export\u{2026} in the toolbar.")
            }
        }
        .formStyle(.grouped)
    }

    private var modelSection: some View {
        Section("Model") {
            Picker("Model", selection: Binding(
                get: { screen.selectedModel },
                set: { choice in
                    if choice == Self.manageTag {
                        settingsTab = "models"
                        openSettings()
                    } else {
                        screen.selectedModel = choice
                    }
                })) {
                Section("MuScriptor · multi-instrument") { ForEach(entries(.muscriptor)) { row($0) } }
                Section("Piano only") { ForEach(entries(.pianoOnnx)) { row($0) } }
                Section("Built in") { ForEach(entries(.basicPitch)) { row($0) } }
                Divider()
                Text("Manage Models…").tag(Optional(Self.manageTag))
            }
            .labelsHidden()
            if let entry {
                HStack(spacing: Metric.sp4) {
                    LicenseBadge(entry: entry)
                }
                if entry.engine == .pianoOnnx {
                    Text("Piano only. On other instruments it still reports piano notes.").font(.caption).foregroundStyle(Native.fgSecondary)
                }
            }
            if entry?.engine == .muscriptor {
                Picker("Device", selection: $screen.deviceIndex) {
                    Text("Auto").tag(Int?.none)
                    ForEach(screen.devices, id: \.index) { Text("\($0.name) (\($0.backend))").tag(Optional($0.index)) }
                }
                LabeledContent("Threads") {
                    HStack(spacing: Metric.sp3) {
                        Text("\(screen.threads)").monospacedDigit()
                        Stepper("Threads", value: $screen.threads, in: 1...32).labelsHidden()
                    }
                }
            }
            if let entry {
                Text(entry.attribution).font(.caption).foregroundStyle(Native.fgSecondary)
            }
        }
    }

    private func entries(_ engine: ModelEntry.Engine) -> [ModelEntry] {
        ModelCatalog.entries.filter { $0.engine == engine }
    }

    private func row(_ entry: ModelEntry) -> some View {
        let installed = screen.store.state(for: entry) == .installed
        return Text(installed ? entry.displayName : "\(entry.displayName) — \(entry.sizeText) download")
            .tag(Optional(entry.id))
    }
}

private struct SliceFieldsSection: View {
    @Bindable var model: DocumentModel
    @State private var startText = ""
    @State private var endText = ""
    @State private var error: String?

    private static let minimumLength = AudioSlice.minimumSpan

    var body: some View {
        Section {
            LabeledContent("Start") {
                TextField("Start", text: $startText).labelsHidden().multilineTextAlignment(.trailing)
                    .monospacedDigit().frame(width: Metric.fieldW).onSubmit(commit).accessibilityLabel("Slice start")
            }
            LabeledContent("End") {
                TextField("End", text: $endText).labelsHidden().multilineTextAlignment(.trailing)
                    .monospacedDigit().frame(width: Metric.fieldW).onSubmit(commit).accessibilityLabel("Slice end")
            }
            LabeledContent("Length", value: Self.format(model.slice.span))
        } header: {
            Text("Slice")
        } footer: {
            if let error { Text(error).foregroundStyle(Native.danger) }
        }
        .onAppear(perform: sync)
        .onChange(of: model.slice) { sync() }
    }

    private func sync() {
        startText = Self.format(model.slice.start)
        endText = Self.format(model.slice.end)
        error = nil
    }

    private func commit() {
        guard let start = Self.parse(startText), let end = Self.parse(endText) else {
            error = "Use m:ss.s or seconds, e.g. 0:04.5 or 4.5"
            return
        }
        if start < 0 || end > model.slice.duration + 0.05 {
            error = "Times must be between 0:00.0 and \(Self.format(model.slice.duration))."
        } else if end - start < Self.minimumLength {
            error = "The slice must be at least 0.5 s long."
        } else {
            model.slice.setEnd(end)
            model.slice.setStart(start)
            sync()
        }
    }

    static func format(_ seconds: Double) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let seconds = Double(parts.last!), seconds >= 0 else { return nil }
        if parts.count == 2 {
            guard let minutes = Int(parts[0]) else { return nil }
            return Double(minutes) * 60 + seconds
        }
        return seconds
    }
}
