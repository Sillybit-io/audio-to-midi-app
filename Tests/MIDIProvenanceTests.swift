import Foundation
import SwiftMIDIFile
import Testing
@testable import SillyMIDITools

struct MIDIProvenanceTests {
    private func note(_ onset: Double, _ offset: Double, _ pitch: Int) -> NoteEvent {
        NoteEvent(onset: onset, offset: offset, pitch: pitch, program: 0, isDrum: false, instrument: "acoustic_piano", velocity: 90, pitchBends: nil)
    }

    @Test func roundTripsEveryFieldIncludingAwkwardCharacters() throws {
        let provenance = MIDIProvenance(source: "audio:Müsic take;2=final%20.wav", sourceName: "take;2=final% Müsic",
                                        modelID: "muscriptor-small", version: 12, edited: true, partial: true)
        let decoded = try #require(MIDIProvenance(text: provenance.text))
        #expect(decoded == provenance)
        #expect(provenance.text.hasPrefix("smt:"))
        #expect(provenance.text.allSatisfy { $0.isASCII })
        #expect(!provenance.text.dropFirst(4).contains(" "))
    }

    @Test func absentFieldsStayAbsent() throws {
        let provenance = MIDIProvenance(modelID: "basic-pitch")
        #expect(!provenance.text.contains("source=") && !provenance.text.contains("name=") && !provenance.text.contains("version="))
        let decoded = try #require(MIDIProvenance(text: provenance.text))
        #expect(decoded.source == nil && decoded.modelID == "basic-pitch")
        #expect(decoded.sourceName == nil && decoded.version == nil)
        #expect(!decoded.edited && !decoded.partial)
    }

    @Test func onlyTheSmtPrefixIsRecognised() {
        #expect(MIDIProvenance(text: "Transcribed with Basic Pitch") == nil)
        #expect(MIDIProvenance(text: "SMT:v=1") == nil)
        #expect(MIDIProvenance(text: "smt:") == MIDIProvenance())
    }

    @Test func unknownAndMalformedFieldsAreIgnored() throws {
        let decoded = try #require(MIDIProvenance(text: "smt:v=2;future=1;junk;model=piano-onnx;edited=yes;partial=1;source=;version=two"))
        #expect(decoded.modelID == "piano-onnx")
        #expect(!decoded.edited)
        #expect(decoded.partial)
        #expect(decoded.source == nil)
        #expect(decoded.version == nil)
        #expect(MIDIProvenance(text: "smt:version=0")?.version == nil)
        #expect(MIDIProvenance(text: "smt:version=-3")?.version == nil)
        #expect(MIDIProvenance(text: "smt:version=4")?.version == 4)
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

    @Test func aSourceSavedAsAFileURLReadsBackAsItsFileName() throws {
        let old = MIDIProvenance(source: "file:///Users/someone/Documents/Silly%20MIDI%20Tools/Audio/My%20take.wav", modelID: "basic-pitch")
        #expect(MIDIProvenance(text: old.text)?.source == "audio:My take.wav")
        #expect(MIDIProvenance(text: MIDIProvenance(source: "reference:ABC").text)?.source == "reference:ABC")
    }

    @Test func removingPathsRewritesOnlyThePathAndKeepsEveryOtherByte() throws {
        let notes = [NoteEvent(onset: 0, offset: 1, pitch: 60, program: 0, isDrum: false, instrument: "electric_piano", velocity: 90,
                               pitchBends: [0, 3, 0]),
                     note(0.5, 2, 64)]
        var options = MIDIExportOptions()
        options.copyright = "Transcribed with Basic Pitch by Spotify (Apache-2.0)."
        options.provenance = MIDIProvenance(source: "file:///Users/someone/Music/Audio/take.wav", sourceName: "take",
                                            modelID: "basic-pitch", version: 2)
        let old = try MIDIBuilder.build(notes: notes, options: options)
        options.provenance?.source = "audio:take.wav"
        let expected = try MIDIBuilder.build(notes: notes, options: options)

        let cleaned = try #require(MIDIProvenance.removingPaths(from: old))
        #expect(cleaned == expected)
        #expect(cleaned.range(of: Data("someone".utf8)) == nil)
        #expect(MIDIProvenance.removingPaths(from: cleaned) == nil)
        #expect(MIDIProvenance.removingPaths(from: Data("not a MIDI file".utf8)) == nil)
        #expect(MIDIProvenance.removingPaths(from: old.prefix(old.count - 3)) == nil)
    }

    @Test func removingAPathKeepsFieldsThisVersionDoesNotKnow() {
        #expect(MIDIProvenance.textWithoutPath("smt:v=2;future=x%3By;source=file%3A%2F%2F%2FUsers%2Fme%2Fa.wav;model=piano-onnx")
                == "smt:v=2;future=x%3By;source=audio%3Aa.wav;model=piano-onnx")
        #expect(MIDIProvenance.textWithoutPath("smt:v=1;source=audio%3Aa.wav") == nil)
        #expect(MIDIProvenance.textWithoutPath("Transcribed with Basic Pitch") == nil)
    }

    @Test func aFileWithoutTheEventHasNoProvenance() throws {
        let data = try MIDIBuilder.build(notes: [note(0, 1, 60)])
        let decoded = try MIDIImporter.decode(data)
        #expect(decoded.provenance == nil)
        let file = try MusicalMIDI1File(data: data)
        #expect(MIDIProvenance.read(from: file) == nil)
    }
}
