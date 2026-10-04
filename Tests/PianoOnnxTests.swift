import Foundation
import Testing
@testable import SillyMIDITools

private let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let fixtures = testsDirectory.appendingPathComponent("Fixtures/PianoOnnx")
private let modelURL = testsDirectory.deletingLastPathComponent().appendingPathComponent("build/models/piano_transcription.onnx")
private let modelAvailable = FileManager.default.fileExists(atPath: modelURL.path)
private let longFixture = testsDirectory.deletingLastPathComponent()
    .appendingPathComponent("Engine/muscriptor.cpp/testdata/audio/fixture_3chunks_16k.wav")

private struct Reference { var onset: Double; var offset: Double; var pitch: Int; var velocity: Int }

private func references(_ name: String) throws -> [Reference] {
    let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    return text.split(whereSeparator: \.isNewline).dropFirst().map { line in
        let c = line.split(separator: ",")
        return Reference(onset: Double(c[0])!, offset: Double(c[1])!, pitch: Int(c[2])!, velocity: Int(c[3])!)
    }
}

private func matrix(_ name: String, rows: Int) throws -> Matrix {
    let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
    return Matrix(rows: rows, cols: 88, data: data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) })
}

/// Pairs every reference note with an unused note of the same pitch whose onset is nearest; returns the pairs.
private func pair(_ want: [Reference], _ got: [(onset: Double, offset: Double, pitch: Int, velocity: Int)], within window: Double)
    -> (pairs: [(Reference, (onset: Double, offset: Double, pitch: Int, velocity: Int))], unmatched: Int) {
    var free = got
    var pairs: [(Reference, (onset: Double, offset: Double, pitch: Int, velocity: Int))] = []
    var unmatched = 0
    for w in want {
        let candidates = free.indices.filter { free[$0].pitch == w.pitch && abs(free[$0].onset - w.onset) <= window }
        if let best = candidates.min(by: { abs(free[$0].onset - w.onset) < abs(free[$1].onset - w.onset) }) {
            pairs.append((w, free.remove(at: best)))
        } else {
            unmatched += 1
        }
    }
    return (pairs, unmatched)
}

struct PianoOnnxTests {
    @Test func postProcessingMatchesReference() throws {
        let rows = 400
        let notes = PianoOnnxNotes.decode(
            onset: try matrix("piano_reg_onset_output.f32", rows: rows), offset: try matrix("piano_reg_offset_output.f32", rows: rows),
            frame: try matrix("piano_frame_output.f32", rows: rows), velocity: try matrix("piano_velocity_output.f32", rows: rows))
        let want = try references("piano_matrices_notes.csv")
        try #require(!want.isEmpty)
        #expect(notes.count == want.count)
        let result = pair(want, notes.map { ($0.onset, $0.offset, $0.pitch, $0.velocity) }, within: 1e-4)
        #expect(result.unmatched == 0)
        for (w, g) in result.pairs {
            #expect(abs(g.offset - w.offset) < 1e-4)
            #expect(g.velocity == w.velocity)
        }
    }

    private func blank(_ rows: Int) -> [Float] { [Float](repeating: 0, count: rows * 88) }

    @Test func aMonotonicPeakBecomesOneNote() {
        let rows = 100, key = 39
        var onset = blank(rows), offset = blank(rows), frame = blank(rows), velocity = blank(rows)
        for (i, v) in [0.1, 0.2, 0.5, 0.2, 0.1].enumerated() { onset[(8 + i) * 88 + key] = Float(v) }
        for (i, v) in [0.05, 0.1, 0.2, 0.3, 0.5, 0.3, 0.2, 0.1, 0.05].enumerated() { offset[(38 + i) * 88 + key] = Float(v) }
        for row in 10...40 { frame[row * 88 + key] = 0.9 }
        velocity[10 * 88 + key] = 0.5
        let notes = PianoOnnxNotes.decode(onset: Matrix(rows: rows, cols: 88, data: onset), offset: Matrix(rows: rows, cols: 88, data: offset),
                                          frame: Matrix(rows: rows, cols: 88, data: frame), velocity: Matrix(rows: rows, cols: 88, data: velocity))
        #expect(notes.count == 1)
        #expect(notes.first?.pitch == 60)
        #expect(abs((notes.first?.onset ?? 0) - 0.10) < 1e-6)
        #expect(abs((notes.first?.offset ?? 0) - 0.41) < 1e-6)
        #expect(notes.first?.velocity == 64)
    }

    @Test func aBumpyPeakIsRejected() {
        let rows = 100, key = 39
        var onset = blank(rows)
        for (i, v) in [0.1, 0.4, 0.2, 0.5, 0.1].enumerated() { onset[(8 + i) * 88 + key] = Float(v) }
        var frame = blank(rows)
        for row in 10...40 { frame[row * 88 + key] = 0.9 }
        let zero = Matrix(rows: rows, cols: 88, data: blank(rows))
        let notes = PianoOnnxNotes.decode(onset: Matrix(rows: rows, cols: 88, data: onset), offset: zero,
                                          frame: Matrix(rows: rows, cols: 88, data: frame), velocity: zero)
        #expect(notes.isEmpty)
    }

    @Test func segmentsOverlapByHalf() {
        let samples = (0..<240_000).map { Float($0) }
        let segments = PianoOnnxEngine.enframe(samples)
        #expect(segments.count == 3)
        for segment in segments { #expect(segment.count == 160_000) }
        let secondStart: Float = segments[1][0]
        let thirdStart: Float = segments[2][0]
        let lastReal: Float = segments[2][79_999]
        let firstPadding: Float = segments[2][80_000]
        #expect(secondStart == 80_000)
        #expect(thirdStart == 160_000)
        #expect(lastReal == 239_999)
        #expect(firstPadding == 0)
        #expect(PianoOnnxEngine.enframe([Float](repeating: 0, count: 160_000)).count == 1)
        #expect(PianoOnnxEngine.enframe([]).isEmpty)
    }

    @Test func framesAreMergedFromTheMiddleOfEachSegment() {
        func part(_ index: Int) -> [Float] { (0..<1001).map { Float(index * 10_000 + $0) } }
        let merged = PianoOnnxEngine.deframe([part(0), part(1), part(2)], cols: 1)
        #expect(merged.count == 2000)
        let checks: [(Int, Float)] = [(0, 0), (749, 749), (750, 10_250), (1249, 10_749), (1250, 20_250), (1999, 20_999)]
        for (index, value) in checks {
            #expect(merged[index] == value, "frame \(index)")
        }
        #expect(PianoOnnxEngine.deframe([part(0)], cols: 1).count == 1001)
        #expect(PianoOnnxEngine.deframe([part(0), part(1)], cols: 1).count == 1500)
    }

    @Test func missingModelSurfacesALoadError() {
        let engine = PianoOnnxEngine(modelURL: URL(fileURLWithPath: "/nonexistent/piano.onnx"))
        #expect(throws: PianoOnnxError.self) { try engine.notes(samples: [Float](repeating: 0, count: 16_000)) }
    }

    /// The app clips notes to the audio length, so reference notes that run on into the zero padding are clipped too.
    private func compare(_ got: [EngineNote], to name: String, duration: Double, minimumMatched: Double) throws {
        let want = try references(name)
        try #require(!want.isEmpty)
        let result = pair(want, got.map { ($0.onset, $0.offset, $0.pitch, $0.velocity ?? 0) }, within: 0.03)
        let matched = Double(want.count - result.unmatched) / Double(want.count)
        #expect(matched >= minimumMatched, "matched \(want.count - result.unmatched) of \(want.count)")
        #expect(abs(got.count - want.count) <= max(2, want.count / 10), "got \(got.count), reference \(want.count)")
        for (w, g) in result.pairs {
            let offsetGap = abs(g.offset - min(w.offset, duration))
            let expectedVelocity = min(127, max(1, w.velocity))
            let velocityGap = abs(g.velocity - expectedVelocity)
            #expect(offsetGap < 0.1)
            #expect(velocityGap <= 6)
        }
    }

    @Test(.enabled(if: modelAvailable))
    func endToEndMatchesReferenceOnASingleSegment() throws {
        let document = try AudioDocument.load(url: fixtures.appendingPathComponent("piano_synthetic.wav"))
        let notes = try PianoOnnxEngine(modelURL: modelURL).notes(samples: document.samples)
        try compare(notes, to: "piano_synthetic_notes.csv", duration: document.duration, minimumMatched: 0.9)
        for note in notes {
            #expect(note.instrument == "acoustic_piano")
            #expect((1...127).contains(note.velocity ?? 0))
        }
    }

    @Test(.enabled(if: modelAvailable && FileManager.default.fileExists(atPath: longFixture.path)))
    func endToEndMatchesReferenceAcrossSegments() throws {
        let document = try AudioDocument.load(url: longFixture)
        var reported: [Double] = []
        let notes = try PianoOnnxEngine(modelURL: modelURL).notes(samples: document.samples) { reported.append($0) }
        let third: Double = 1.0 / 3.0
        let expected: [Double] = [third, 2 * third, 1.0]
        #expect(reported.count == 3)
        for (got, want) in zip(reported, expected) { #expect(abs(got - want) < 1e-12) }
        try compare(notes, to: "piano_fixture_notes.csv", duration: document.duration, minimumMatched: 0.9)
        let limit = document.duration + 1e-9
        for note in notes { #expect(note.offset <= limit) }
    }
}
