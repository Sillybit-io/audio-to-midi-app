import Foundation
import Testing
@testable import SillyMIDITools

private func entry(_ id: String) -> ModelEntry { ModelCatalog.entries.first { $0.id == id }! }

private let ran = AudioScreenModel.RunRecord(modelID: "basic-pitch", modelName: "Basic Pitch", start: 2, end: 12.5,
                                             instruments: [], estimatesVelocity: true, took: 4)

@MainActor
struct HandoffStringsTests {
    @Test func theFooterSummaryUsesTheHandoffWording() {
        typealias S = AudioScreenModel
        #expect(S.summary(state: .idle, noteCount: 0, instrumentCount: 0, ran: nil, changed: false) == "No notes yet")
        #expect(S.summary(state: .running, noteCount: 3, instrumentCount: 1, ran: ran, changed: false)
            == "Transcribing 2.0\u{2013}12.5 s with Basic Pitch\u{2026}")
        #expect(S.summary(state: .done(48), noteCount: 48, instrumentCount: 1, ran: ran, changed: false)
            == "Done \u{2014} 48 notes \u{00B7} 1 instrument \u{00B7} 2.0\u{2013}12.5 s \u{00B7} Basic Pitch \u{00B7} 4 s")
        #expect(S.summary(state: .cancelled, noteCount: 9, instrumentCount: 2, ran: ran, changed: true)
            == "Cancelled \u{2014} partial notes kept \u{00B7} 2 instruments \u{00B7} 2.0\u{2013}12.5 s \u{00B7} Basic Pitch \u{00B7} 4 s \u{00B7} Changed \u{2014} transcribe again to apply")
    }

    @Test func downloadStepTitleCountsInTheSizesUnit() {
        #expect(AudioScreenModel.downloadTitle(entry("muscriptor-small"), fraction: 0.2).hasPrefix("Downloading MuScriptor Small \u{00B7} "))
        #expect(AudioScreenModel.downloadTitle(entry("piano-onnx"), fraction: 0).hasSuffix(" \u{00B7} 0 of 154 MB"))
        #expect(AudioScreenModel.downloadTitle(entry("piano-onnx"), fraction: 2).contains(" of 154 MB"))
    }

    @Test func theEditorSubtitleAndFooterMatchThePrototype() {
        #expect(ContentView.editorSubtitle(notes: 24, tracks: 1, dirty: false) == "24 notes \u{00B7} 1 track \u{00B7} 120 BPM 4/4")
        #expect(ContentView.editorSubtitle(notes: 1, tracks: 3, dirty: true) == "1 note \u{00B7} 3 tracks \u{00B7} 120 BPM 4/4 \u{00B7} Edited")

        let notes = [EditorNote(id: 1, track: "piano", pitch: 60, start: 1.25, duration: 0.5, velocity: 90),
                     EditorNote(id: 2, track: "piano", pitch: 64, start: 2, duration: 0.5, velocity: 90)]
        let name: (String) -> String = { $0 == "piano" ? "Piano" : $0 }
        #expect(MIDIEditorView.summary(notes: notes, selection: [], trackName: name, skipped: 0)
            == "2 notes \u{00B7} drag empty space to select, \u{2325}\u{2190} \u{2325}\u{2192} to step through notes, D to draw, E to erase")
        #expect(MIDIEditorView.summary(notes: notes, selection: [1], trackName: name, skipped: 0) == "C4 \u{00B7} Piano \u{00B7} 1.25 s \u{2014} 1 of 2 selected")
        #expect(MIDIEditorView.summary(notes: notes, selection: [1, 2], trackName: name, skipped: 0) == "2 of 2 notes selected")
        #expect(MIDIEditorView.summary(notes: notes, selection: [], trackName: name, skipped: 3).hasSuffix(" \u{00B7} 3 outside C1\u{2013}B6 skipped"))
    }

    @Test func audioThatCantBeOpenedGetsTheHandoffAlert() {
        let ogg = AudioOpenFailure.decoding(URL(fileURLWithPath: "/tmp/take.ogg"))
        #expect(ogg.title == "Could not open audio")
        #expect(ogg.message == "This file can't be decoded. OGG isn't supported. Use WAV, MP3, FLAC, M4A or AIFF.")
        let wav = AudioOpenFailure.decoding(URL(fileURLWithPath: "/tmp/Take 3.WAV"))
        #expect(wav.title == "Could not open \u{201C}Take 3.WAV\u{201D}")
        #expect(wav.message == "The file may be damaged, or it's in a format Core Audio can't read.")
    }

    @Test func layoutSizesComeFromTheTokens() {
        #expect(Metric.mixSliderW == 220)
        #expect(Metric.aboutH == 460 && Metric.settingsMinH == 520)
        #expect(Metric.licenceSheetW == 560 && Metric.licenceTextH == 200)
        #expect(Metric.sliderW == 80 && Metric.readoutW == 40)
    }
}
