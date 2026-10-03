import Foundation
import Testing
@testable import SillyMIDITools

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/BasicPitch")

private struct RefNote { var start: Double; var end: Double; var pitch: Int; var amplitude: Double; var bends: [Int] }

private func referenceNotes(_ name: String) throws -> [RefNote] {
    let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    return text.split(whereSeparator: \.isNewline).dropFirst().map { line in
        let c = line.split(separator: ",", omittingEmptySubsequences: false)
        return RefNote(start: Double(c[0])!, end: Double(c[1])!, pitch: Int(c[2])!, amplitude: Double(c[3])!,
                       bends: c[4].split(separator: ";").map { Int($0)! })
    }.sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
}

private func matrix(_ name: String, rows: Int, cols: Int) throws -> Matrix {
    let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
    let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    return Matrix(rows: rows, cols: cols, data: floats)
}

struct BasicPitchTests {
    @Test func windowingMatchesReference() {
        let windows = BasicPitchEngine.windows(for: [Float](repeating: 0, count: 220_500))
        #expect(windows.count == 7)
        #expect(windows.allSatisfy { $0.count == 43844 })
        #expect(BasicPitchEngine.framesKept(originalLength: 220_500, windowCount: 7) == 865)
        #expect(BasicPitchEngine.framesKept(originalLength: 66_150, windowCount: 2) == 259)
    }

    @Test func frameTimesApplyTheWindowOffset() {
        let times = BasicPitchNotes.frameTimes(count: 173)
        #expect(times[0] == 0)
        #expect(abs(times[172] - (172 * 256 / 22050.0 - 0.010326)) < 1e-4)
    }

    @Test func postProcessingMatchesReference() throws {
        let rows = 259
        let notes = try matrix("synthetic_note.f32", rows: rows, cols: 88)
        let onsets = try matrix("synthetic_onset.f32", rows: rows, cols: 88)
        let contour = try matrix("synthetic_contour.f32", rows: rows, cols: 264)
        let got = BasicPitchNotes.decode(note: notes, onset: onsets, contour: contour)
            .sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        let want = try referenceNotes("synthetic_notes.csv")
        try #require(got.count == want.count)
        for (g, w) in zip(got, want) {
            #expect(g.pitch == w.pitch)
            #expect(abs(g.start - w.start) < 1e-6)
            #expect(abs(g.end - w.end) < 1e-6)
            #expect(abs(g.amplitude - w.amplitude) < 0.001)
            #expect(g.bends == w.bends)
        }
    }

    @Test func overlappingNotesLoseTheirBends() {
        let a = BasicPitchNote(start: 0, end: 2, pitch: 60, amplitude: 0.5, bends: [1])
        let b = BasicPitchNote(start: 1, end: 3, pitch: 64, amplitude: 0.5, bends: [1])
        let c = BasicPitchNote(start: 5, end: 6, pitch: 67, amplitude: 0.5, bends: [1])
        let out = BasicPitchNotes.dropOverlappingBends([c, b, a])
        #expect(out.map(\.bends) == [nil, nil, [1]])
    }

    @Test func endToEndMatchesReference() throws {
        let doc = try AudioDocument.load(url: fixtures.appendingPathComponent("synthetic.wav"))
        let got = try BasicPitchEngine().notes(samples: doc.samples).sorted { ($0.start, $0.pitch) < ($1.start, $1.pitch) }
        let want = try referenceNotes("synthetic_notes.csv")
        try #require(got.count == want.count)
        for (g, w) in zip(got, want) {
            #expect(g.pitch == w.pitch)
            #expect(abs(g.start - w.start) <= 0.012)
            #expect(abs(g.end - w.end) <= 0.012)
            #expect(abs(g.velocity - Int((127 * w.amplitude).rounded(.toNearestOrEven))) <= 2)
        }
    }

    @Test func shortClipIsPaddedAndDoesNotCrash() throws {
        let clip = (0..<22_050).map { Float(sin(2 * .pi * 440 * Double($0) / 22_050)) * 0.5 }
        let notes = try BasicPitchEngine().notes(samples: clip)
        #expect(notes.allSatisfy { $0.end >= $0.start })
    }

    @Test func missingModelSurfacesALoadError() {
        let engine = BasicPitchEngine(modelURL: URL(fileURLWithPath: "/nonexistent.mlmodelc"))
        #expect(throws: BasicPitchError.self) { try engine.load() }
    }
}
