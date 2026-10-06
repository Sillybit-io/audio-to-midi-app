import Foundation
import Testing
@testable import SillyMIDITools

private let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let clipsDirectory = testsDirectory.deletingLastPathComponent().appendingPathComponent("build/percussion")
private let maksumClip = clipsDirectory.appendingPathComponent("Maksum_Ejemplo.wav")
private let saidiClip = clipsDirectory.appendingPathComponent("Saidi_Ejemplo.wav")
private let clipsAvailable = FileManager.default.fileExists(atPath: maksumClip.path) && FileManager.default.fileExists(atPath: saidiClip.path)

private let low = HandPercussionEngine.lowPitch
private let high = HandPercussionEngine.highPitch

/// A doum is a decaying low tone that falls a little; a tek is a short burst of high-passed noise with a ring around
/// 3 kHz. The noise is a fixed xorshift sequence, so every run hears the same drum.
private func drum(_ strokes: [(time: Double, isLow: Bool)], seconds: Double) -> [Float] {
    let rate = HandPercussionEngine.sampleRate
    var out = [Float](repeating: 0, count: Int(seconds * rate))
    var state: UInt32 = 2_463_534_242
    func noise() -> Float {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return Float(state) / Float(UInt32.max) * 2 - 1
    }
    for stroke in strokes {
        let start = Int(stroke.time * rate)
        var previous: Float = 0
        for i in 0..<Int(0.4 * rate) where start + i < out.count {
            let t = Double(i) / rate
            if stroke.isLow {
                let phase = 2 * Double.pi * (100 * t + 60 * 0.02 * (1 - exp(-t / 0.02)))
                out[start + i] += Float(0.7 * exp(-t / 0.09) * sin(phase))
            } else {
                let n = noise()
                let edge = n - previous
                previous = n
                out[start + i] += Float(0.35 * exp(-t / 0.03)) * edge + Float(0.25 * exp(-t / 0.05) * sin(2 * Double.pi * 3000 * t))
            }
        }
    }
    return out
}

private func evenly(_ count: Int, every spacing: Double = 0.4, low isLow: (Int) -> Bool) -> [(time: Double, isLow: Bool)] {
    var strokes: [(time: Double, isLow: Bool)] = []
    for i in 0..<count { strokes.append((time: 0.3 + Double(i) * spacing, isLow: isLow(i))) }
    return strokes
}

/// Maksum is doum, tek, tek, doum, tek; Saidi is doum, tek, doum, doum, tek. Each is played here four times.
private let maksum = [low, high, high, low, high]
private let saidi = [low, high, low, low, high]

private func pitches(of clip: URL) throws -> [Int] {
    let audio = try AudioDocument.load(url: clip)
    let samples = try Resampler.resample(audio.samples, from: audio.sampleRate, to: HandPercussionEngine.sampleRate)
    return try HandPercussionEngine().hits(samples: samples).sorted { $0.time < $1.time }.map(\.pitch)
}

struct HandPercussionTests {
    @Test func aSyntheticRhythmComesBackStrokeForStroke() throws {
        let pattern = maksum + saidi
        let strokes = evenly(pattern.count, every: 0.36) { pattern[$0] == low }
        let samples = drum(strokes, seconds: 0.3 + 0.36 * Double(strokes.count) + 0.5)
        let hits = try HandPercussionEngine().hits(samples: samples).sorted { $0.time < $1.time }
        #expect(hits.count == strokes.count)
        #expect(hits.map(\.pitch) == pattern)
        for (hit, stroke) in zip(hits, strokes) { #expect(abs(hit.time - stroke.time) < 0.03, "stroke at \(stroke.time) was heard at \(hit.time)") }
    }

    @Test func silenceAndTooShortAudioHaveNoStrokes() throws {
        #expect(try HandPercussionEngine().hits(samples: [Float](repeating: 0, count: 44_100)).isEmpty)
        #expect(try HandPercussionEngine().hits(samples: [Float](repeating: 0.5, count: 100)).isEmpty)
        #expect(try HandPercussionEngine().hits(samples: []).isEmpty)
    }

    @Test func aStrokeQuieterThanTheNoiseFloorIsIgnored() throws {
        let samples = drum([(0.3, true), (0.9, false)], seconds: 1.6).map { $0 * 0.001 }
        #expect(try HandPercussionEngine().hits(samples: samples).isEmpty)
    }

    @Test func aRecordingOfOneToneIsNotSplitInTwo() throws {
        let allLow = drum(evenly(10) { _ in true }, seconds: 4.8)
        #expect(try HandPercussionEngine().hits(samples: allLow).map(\.pitch) == [Int](repeating: low, count: 10))
        let allHigh = drum(evenly(10) { _ in false }, seconds: 4.8)
        #expect(try HandPercussionEngine().hits(samples: allHigh).map(\.pitch) == [Int](repeating: high, count: 10))
    }

    @Test func theSplitFallsBetweenTwoClearGroupsAndOtherwiseIsFixed() {
        let two: [Float] = [2.4, -0.5, -0.4, 2.3, -0.5, 2.5, -0.3, -0.2, 2.2, -0.6]
        let boundary = HandPercussionEngine.split(ratios: two)
        #expect(boundary > 0.5 && boundary < 1.5)
        #expect(HandPercussionEngine.split(ratios: [2.4, -0.5, 2.3]) == HandPercussionEngine.fallbackSplit)
        #expect(HandPercussionEngine.split(ratios: [Float](repeating: 2.5, count: 12)) == HandPercussionEngine.fallbackSplit)
        #expect(HandPercussionEngine.split(ratios: [2.0, 2.4, 2.2, 2.6, 2.1, 2.5, 2.3, 2.7]) == HandPercussionEngine.fallbackSplit)
        // One tone that varies a lot is still one tone, however wide the spread.
        #expect(HandPercussionEngine.split(ratios: [8.3, 8.7, 9.0, 9.7, 10.7, 12.3, 8.4, 8.9, 9.4, 10.3]) == HandPercussionEngine.fallbackSplit)
        #expect(HandPercussionEngine.split(ratios: [0.1, 1.3, 0.4, 0.9, 1.2, 0.2, 0.7, 1.0, 0.6, 1.1]) == HandPercussionEngine.fallbackSplit)
    }

    @Test func theMedianFilterReflectsAtTheEnds() {
        #expect(HandPercussionEngine.medianFilter([1, 5, 2, 8, 3], size: 3) == [1, 2, 5, 3, 3])
        #expect(HandPercussionEngine.medianFilter([4, 4], size: 1) == [4, 4])
        #expect(HandPercussionEngine.medianFilter([], size: 5).isEmpty)
    }

    @Test func peaksCloserThanTheMinimumGapKeepOnlyTheStrongest() {
        var flux = [Float](repeating: 0, count: 400)
        flux[100] = 1; flux[110] = 0.8; flux[200] = 0.6
        #expect(HandPercussionEngine.onsetFrames(flux: flux) == [100, 200])
        #expect(HandPercussionEngine.onsetFrames(flux: [Float](repeating: 0, count: 400)).isEmpty)
    }

    @Test func theStreamAnnouncesProgressAndFinishesWithTheStrokes() async throws {
        let strokes = evenly(5) { $0 % 2 == 0 }
        let samples = drum(strokes, seconds: 3)
        var events: [EngineEvent] = []
        for try await event in HandPercussionEngine().stream(samples: samples) { events.append(event) }
        guard case .ready = events.first else { Issue.record("no ready event"); return }
        guard case .done(let count) = events.last else { Issue.record("no done event"); return }
        #expect(count == 5)
        var finalNotes: [EngineNote] = []
        for event in events {
            if case .update(let progress, _, let notes) = event, progress == 1 { finalNotes = notes }
        }
        #expect(finalNotes.map(\.pitch) == [low, high, low, high, low])
        #expect(finalNotes.allSatisfy { $0.isDrum })
    }

    @MainActor @Test func theEntryIsBuiltInAndNeedsNothingDownloaded() throws {
        let entry = try #require(ModelCatalog.entry(id: "hand-percussion"))
        #expect(entry.engine == .handPercussion && entry.isBuiltIn && !entry.needsDownload && entry.downloadURL == nil)
        #expect(entry.access == .open && !entry.requiresAcceptance && entry.transcribes)
        #expect(entry.licenseKind == .commercialAllowed && entry.canEstimateVelocity && !entry.isDrumModel)
        let store = ModelStore(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        #expect(store.state(for: entry) == .installed)
    }

    @Test(.enabled(if: clipsAvailable)) func aRealDarbukaPlayingMaksumIsReadAsMaksum() throws {
        #expect(try pitches(of: maksumClip) == Array((0..<4).map { _ in maksum }.joined()))
    }

    @Test(.enabled(if: clipsAvailable)) func aRealDarbukaPlayingSaidiIsReadAsSaidi() throws {
        #expect(try pitches(of: saidiClip) == Array((0..<4).map { _ in saidi }.joined()))
    }
}
