import Foundation
import Testing
@testable import SillyMIDITools

private let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let fixtures = testsDirectory.appendingPathComponent("Fixtures/DrumsOnnx")
private let modelsDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("build/models")
private let adtofModel = modelsDirectory.appendingPathComponent("adtof_frame_rnn.onnx")
private let oafModel = modelsDirectory.appendingPathComponent("oaf_drums.onnx")
private let adtofAvailable = FileManager.default.fileExists(atPath: adtofModel.path)
private let oafAvailable = FileManager.default.fileExists(atPath: oafModel.path)

private func floats(_ name: String, cols: Int) throws -> Matrix {
    let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
    let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    return Matrix(rows: values.count / cols, cols: cols, data: values)
}

private func references(_ name: String) throws -> [DrumHit] {
    let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    return text.split(whereSeparator: \.isNewline).dropFirst().map { line in
        let c = line.split(separator: ",")
        return DrumHit(time: Double(c[0])!, pitch: Int(c[1])!, velocity: c.count > 2 ? Int(c[2])! : nil)
    }
}

/// Pairs every wanted hit with an unused hit of the same pitch within `window` seconds; returns how many found none.
private func unmatched(_ want: [DrumHit], _ got: [DrumHit], within window: Double) -> Int {
    var free = got
    var missing = 0
    for w in want {
        let candidates = free.indices.filter { free[$0].pitch == w.pitch && abs(free[$0].time - w.time) <= window }
        if let best = candidates.min(by: { abs(free[$0].time - w.time) < abs(free[$1].time - w.time) }) {
            free.remove(at: best)
        } else {
            missing += 1
        }
    }
    return missing
}

struct DrumDecoderTests {
    @Test func adtofDecoderMatchesMadmomOnTheFixture() throws {
        let hits = DrumNotes.decodeADTOF(try floats("adtof_decoder_activations.f32", cols: 5))
        let want = try references("adtof_decoder_hits.csv")
        try #require(want.count > 100)
        #expect(hits.count == want.count)
        #expect(unmatched(want, hits, within: 1e-9) == 0)
        #expect(hits.allSatisfy { $0.velocity == nil })
    }

    @Test func oafDecoderMatchesTheReferenceOnTheFixture() throws {
        let hits = DrumNotes.decodeOaF(onset: try floats("oaf_decoder_onset.f32", cols: 8),
                                       velocity: try floats("oaf_decoder_velocity.f32", cols: 8))
        let want = try references("oaf_decoder_hits.csv")
        try #require(want.count > 100)
        #expect(hits.count == want.count)
        for (got, expected) in zip(hits, want) {
            #expect(got.pitch == expected.pitch)
            #expect(abs(got.time - expected.time) < 1e-9)
            #expect(got.velocity == expected.velocity)
        }
    }

    @Test func aLonePeakIsOneHitAndPeaksTwoFramesApartAreCombined() {
        var x = [Float](repeating: 0, count: 100)
        x[20] = 0.8
        x[50] = 0.7; x[52] = 0.9
        x[70] = 0.7; x[73] = 0.9
        #expect(DrumNotes.peakFrames(x, threshold: 0.3) == [20, 50, 70, 73])
    }

    @Test func aPeakMustClearTheMovingAverageAndTheThreshold() {
        // madmom zero-pads the moving average, so a held level peaks at the very start; the interior never does.
        let sustained = [Float](repeating: 0.5, count: 60)
        #expect(DrumNotes.peakFrames(sustained, threshold: 0.22).allSatisfy { $0 < 6 })
        var quiet = [Float](repeating: 0.1, count: 60)
        quiet[30] = 0.2
        #expect(DrumNotes.peakFrames(quiet, threshold: 0.22).isEmpty)
        #expect(DrumNotes.peakFrames([], threshold: 0.2).isEmpty)
    }

    @Test func aPlateauOfEqualFramesIsOneHit() {
        var x = [Float](repeating: 0, count: 50)
        x[20] = 0.9; x[21] = 0.9
        #expect(DrumNotes.peakFrames(x, threshold: 0.3) == [20])
    }

    @Test func adtofReportsEveryClassOnItsOwnPitch() {
        var data = [Float](repeating: 0, count: 5 * 40)
        for column in 0..<5 { data[(10 + column * 5) * 5 + column] = 0.95 }
        let hits = DrumNotes.decodeADTOF(Matrix(rows: 40, cols: 5, data: data))
        #expect(hits.map(\.pitch) == [36, 38, 47, 42, 49])
        #expect(hits.map(\.time) == [0.10, 0.15, 0.20, 0.25, 0.30])
        #expect(DrumNotes.decodeADTOF(Matrix(rows: 4, cols: 3, data: [Float](repeating: 1, count: 12))).isEmpty)
    }

    @Test func oafMergesARunToItsStrongestFrameAndClipsTheVelocity() {
        var onset = [Float](repeating: 0, count: 8 * 30)
        var velocity = [Float](repeating: 0, count: 8 * 30)
        for (row, p) in [(5, 0.6), (6, 0.9), (7, 0.7)] { onset[row * 8 + 1] = Float(p) }
        velocity[6 * 8 + 1] = 1.4
        onset[20 * 8 + 3] = 0.5 // not above the threshold
        onset[25 * 8 + 6] = 0.8
        velocity[25 * 8 + 6] = -0.3
        let hits = DrumNotes.decodeOaF(onset: Matrix(rows: 30, cols: 8, data: onset), velocity: Matrix(rows: 30, cols: 8, data: velocity))
        #expect(hits == [DrumHit(time: 0.06, pitch: 38, velocity: 127), DrumHit(time: 0.25, pitch: 49, velocity: 1)])
    }
}

struct DrumEngineTests {
    @Test func aShortRecordingIsOneChunk() {
        #expect(DrumOnnxEngine.chunks(sampleCount: 0).isEmpty)
        #expect(DrumOnnxEngine.chunks(sampleCount: 44_100) == [DrumOnnxEngine.Chunk(input: 0..<44_100, skip: 0, keep: nil)])
        let edge = DrumOnnxEngine.coreSamples + DrumOnnxEngine.contextSamples
        #expect(DrumOnnxEngine.chunks(sampleCount: edge).count == 1)
        #expect(DrumOnnxEngine.chunks(sampleCount: edge + 1).count == 2)
    }

    @Test func chunksStartOnTheGlobalFrameGridAndAnswersJoinWithoutGapsOrRepeats() {
        let count = DrumOnnxEngine.coreSamples * 2 + 12_345
        let plan = DrumOnnxEngine.chunks(sampleCount: count)
        #expect(plan.count == 3)
        for chunk in plan { #expect(chunk.input.lowerBound % DrumOnnxEngine.hop == 0) }
        // Each fake answer holds the global frame number of every row, as the real model's frames would line up.
        let parts = plan.map { chunk -> Matrix in
            let rows = (chunk.input.count + DrumOnnxEngine.hop - 1) / DrumOnnxEngine.hop
            let first = chunk.input.lowerBound / DrumOnnxEngine.hop
            return Matrix(rows: rows, cols: 1, data: (0..<rows).map { Float(first + $0) })
        }
        let joined = DrumOnnxEngine.assemble(parts, chunks: plan)
        let expectedRows = (count + DrumOnnxEngine.hop - 1) / DrumOnnxEngine.hop
        #expect(joined.rows == expectedRows)
        #expect(joined.data == (0..<expectedRows).map(Float.init))
    }

    @Test func hitsBecomeShortDrumNotesClippedToTheAudio() {
        let hits = [DrumHit(time: 1.0, pitch: 38, velocity: 90), DrumHit(time: 1.95, pitch: 36, velocity: nil),
                    DrumHit(time: 2.5, pitch: 42, velocity: 70)]
        let notes = DrumOnnxEngine.notes(from: hits, duration: 2.0)
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.isDrum && $0.instrument == "drums" })
        #expect(abs(notes[0].offset - 1.1) < 1e-9)
        #expect(abs(notes[1].offset - 2.0) < 1e-9)
        #expect(notes[0].velocity == 90 && notes[1].velocity == nil)
    }

    @Test func aMissingModelSurfacesALoadError() {
        let engine = DrumOnnxEngine(modelURL: URL(fileURLWithPath: "/nonexistent/drums.onnx"), spec: .adtof)
        #expect(throws: DrumOnnxError.self) { try engine.notes(samples: [Float](repeating: 0, count: 44_100)) }
    }

    @Test func bothModelsAreCataloguedAsDrumModelsWithTheirOwnAccess() throws {
        let adtof = try #require(ModelCatalog.entry(id: "drums-adtof"))
        let oaf = try #require(ModelCatalog.entry(id: "drums-oaf"))
        #expect(adtof.isDrumModel && oaf.isDrumModel)
        #expect(adtof.access == .terms && adtof.licenseKind == .nonCommercial && adtof.canEstimateVelocity)
        #expect(oaf.access == .open && oaf.licenseKind == .commercialAllowed && !oaf.canEstimateVelocity)
        #expect(adtof.requiresAcceptance && !oaf.requiresAcceptance)
        #expect(adtof.needsDownload && oaf.needsDownload)
    }
}

struct DrumOnnxEndToEndTests {
    private func clip() throws -> AudioDocument {
        try AudioDocument.load(url: fixtures.appendingPathComponent("drums_synthetic.wav"))
    }

    private func maxDifference(_ a: Matrix, _ b: Matrix) -> Float {
        zip(a.data, b.data).map { abs($0 - $1) }.max() ?? .infinity
    }

    @Test(.enabled(if: adtofAvailable))
    func adtofActivationsMatchTheAuthorsPipeline() throws {
        let document = try clip()
        try #require(document.sampleRate == 44_100)
        let session = try DrumOnnxSession(modelURL: adtofModel, spec: .adtof, threads: 0)
        let got = try session.run(samples: document.samples)[0]
        let want = try floats("adtof_clip_activations.f32", cols: 5)
        #expect(got.rows == want.rows)
        #expect(maxDifference(got, want) < 1e-3)
    }

    @Test(.enabled(if: adtofAvailable))
    func adtofHitsMatchTheReferenceOnTheClip() throws {
        let hits = try DrumOnnxEngine(modelURL: adtofModel, spec: .adtof).hits(samples: try clip().samples)
        let want = try references("adtof_clip_hits.csv")
        try #require(!want.isEmpty)
        #expect(abs(hits.count - want.count) <= 1)
        #expect(unmatched(want, hits, within: 0.02) <= 1)
    }

    @Test(.enabled(if: adtofAvailable))
    func adtofStitchesChunksOnALongRecording() throws {
        let one = try clip().samples
        let copies = 14 // 56 s, past the single-chunk limit
        let long = (0..<copies).flatMap { _ in one }
        try #require(DrumOnnxEngine.chunks(sampleCount: long.count).count == 2)
        var reported: [Double] = []
        let hits = try DrumOnnxEngine(modelURL: adtofModel, spec: .adtof).hits(samples: long) { reported.append($0) }
        #expect(reported == [0.5, 1.0])
        let period = Double(one.count) / DrumOnnxEngine.sampleRate
        let want = try references("adtof_clip_hits.csv")
        let expected = (0..<copies).flatMap { copy in want.map { DrumHit(time: $0.time + Double(copy) * period, pitch: $0.pitch, velocity: nil) } }
        #expect(Double(unmatched(expected, hits, within: 0.03)) / Double(expected.count) < 0.15)
        #expect(hits.map(\.time).sorted() == hits.map(\.time))
    }

    @Test(.enabled(if: oafAvailable))
    func oafOutputsMatchTheOriginalGraph() throws {
        let document = try clip()
        let session = try DrumOnnxSession(modelURL: oafModel, spec: .oaf, threads: 0)
        let got = try session.run(samples: document.samples)
        #expect(maxDifference(got[0], try floats("oaf_clip_onset.f32", cols: 8)) < 1e-3)
        #expect(maxDifference(got[1], try floats("oaf_clip_velocity.f32", cols: 8)) < 1e-2)
    }

    @Test(.enabled(if: oafAvailable))
    func oafHitsMatchTheReferenceOnTheClip() throws {
        let hits = try DrumOnnxEngine(modelURL: oafModel, spec: .oaf).hits(samples: try clip().samples)
        let want = try references("oaf_clip_hits.csv")
        #expect(hits.count == want.count)
        #expect(unmatched(want, hits, within: 0.011) == 0)
        for hit in hits { #expect((1...127).contains(hit.velocity ?? 0)) }
    }

    @Test(.enabled(if: oafAvailable))
    func aVeryShortClipStillRuns() throws {
        let notes = try DrumOnnxEngine(modelURL: oafModel, spec: .oaf).notes(samples: [Float](repeating: 0, count: 500))
        #expect(notes.isEmpty)
    }
}
