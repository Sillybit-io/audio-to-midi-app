import Foundation
import SwiftMIDIFile
import Testing
@testable import SillyMIDITools

struct MIDIProvenanceTests {
    private func note(_ onset: Double, _ offset: Double, _ pitch: Int) -> NoteEvent {
        NoteEvent(onset: onset, offset: offset, pitch: pitch, program: 0, isDrum: false, instrument: "acoustic_piano", velocity: 90, pitchBends: nil)
    }

    @Test func roundTripsEveryFieldIncludingAwkwardCharacters() throws {
        let provenance = MIDIProvenance(source: "file:///Volumes/Studio/Müsic/take;2=final%20.wav", modelID: "muscriptor-small", edited: true, partial: true)
        let decoded = try #require(MIDIProvenance(text: provenance.text))
        #expect(decoded == provenance)
        #expect(provenance.text.hasPrefix("smt:"))
        #expect(provenance.text.allSatisfy { $0.isASCII })
        #expect(!provenance.text.dropFirst(4).contains(" "))
    }

    @Test func absentFieldsStayAbsent() throws {
        let provenance = MIDIProvenance(modelID: "basic-pitch")
        #expect(!provenance.text.contains("source="))
        let decoded = try #require(MIDIProvenance(text: provenance.text))
        #expect(decoded.source == nil && decoded.modelID == "basic-pitch")
        #expect(!decoded.edited && !decoded.partial)
    }

    @Test func onlyTheSmtPrefixIsRecognised() {
        #expect(MIDIProvenance(text: "Transcribed with Basic Pitch") == nil)
        #expect(MIDIProvenance(text: "SMT:v=1") == nil)
        #expect(MIDIProvenance(text: "smt:") == MIDIProvenance())
    }

    @Test func unknownAndMalformedFieldsAreIgnored() throws {
        let decoded = try #require(MIDIProvenance(text: "smt:v=2;future=1;junk;model=piano-onnx;edited=yes;partial=1;source="))
        #expect(decoded.modelID == "piano-onnx")
        #expect(!decoded.edited)
        #expect(decoded.partial)
        #expect(decoded.source == nil)
    }

    @Test func survivesSavingAndReloadingAFile() throws {
        let provenance = MIDIProvenance(source: "audio-bookmark-7F3A", modelID: "muscriptor-medium", edited: true)
        var options = MIDIExportOptions()
        options.provenance = provenance
        let data = try MIDIBuilder.build(notes: [note(0, 1, 60)], options: options)

        let decoded = try MIDIImporter.decode(data)
        #expect(decoded.provenance == provenance)
        let file = try MusicalMIDI1File(data: data)
        #expect(MIDIProvenance.read(from: file) == provenance)
    }

    @Test func aFileWithoutTheEventHasNoProvenance() throws {
        let data = try MIDIBuilder.build(notes: [note(0, 1, 60)])
        let decoded = try MIDIImporter.decode(data)
        #expect(decoded.provenance == nil)
        let file = try MusicalMIDI1File(data: data)
        #expect(MIDIProvenance.read(from: file) == nil)
    }
}
