import AVFoundation
import Foundation
import Testing
@testable import SillyMIDITools

struct AudioIngestTests {
    private func sine(rate: Double, seconds: Double) -> [Float] {
        (0..<Int(rate * seconds)).map { Float(sin(2 * .pi * 440 * Double($0) / rate)) }
    }

    @Test(arguments: [16000.0, 22050.0])
    func resampleLength(target: Double) throws {
        let out = try Resampler.resample(sine(rate: 44100, seconds: 1), from: 44100, to: target)
        #expect(abs(Double(out.count) - target) <= 1)
    }

    @Test func sliceClamping() {
        var slice = AudioSlice(duration: 10)
        slice.setStart(4)
        slice.setEnd(2)
        #expect(abs(slice.end - 4.5) < 1e-9)
        slice.setStart(20)
        #expect(abs(slice.start - 4.0) < 1e-9)
        slice.setEnd(99)
        #expect(slice.end == 10)
    }

    @Test func sliceCutsSamples() {
        var slice = AudioSlice(duration: 2)
        slice.setStart(0.5)
        slice.setEnd(1.5)
        let cut = slice.cut(sine(rate: 1000, seconds: 2), sampleRate: 1000)
        #expect(cut.count == 1000)
    }

    @Test func peaksBucketCount() {
        let peaks = WaveformPeaks.compute(sine(rate: 16000, seconds: 2), buckets: 500)
        #expect(peaks.count == 500)
        #expect(peaks.allSatisfy { $0.min <= $0.max })
    }

    @Test func decodesGeneratedWav() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let frames = AVAudioFrameCount(88200)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 { for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = 0.5 } }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let doc = try AudioDocument.load(url: url)
        #expect(abs(doc.duration - 2.0) < 0.01)
        #expect(abs(doc.samples[100] - 0.5) < 1e-4)
    }

    /// Writes a stereo file whose left channel counts up and whose right channel holds `right`.
    private func writeStereo(frames: Int, right: Float) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ingest-\(UUID().uuidString).wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames {
            buffer.floatChannelData![0][i] = Float(i) / Float(frames)
            buffer.floatChannelData![1][i] = right
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @Test func channelsAreMixedAcrossDecodeChunks() throws {
        let frames = Int(AudioDocument.readFrames) * 2 + 1234
        let url = try writeStereo(frames: frames, right: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try AudioDocument.load(url: url)
        #expect(doc.samples.count == frames)
        let chunk = Int(AudioDocument.readFrames)
        for i in [0, chunk - 1, chunk, 2 * chunk, frames - 1] {
            #expect(abs(doc.samples[i] - (Float(i) / Float(frames) + 0.25) / 2) < 1e-6, "sample \(i)")
        }
    }

    @Test func audioLongerThanTheLimitIsRefusedBeforeDecoding() throws {
        let url = try writeStereo(frames: 88200, right: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: AudioDocumentError.tooLong(seconds: 2)) { try AudioDocument.load(url: url, maximumDuration: 1.5) }
        #expect(try AudioDocument.load(url: url, maximumDuration: 2).samples.count == 88200)
        #expect(AudioDocument.maximumDuration == 3600)
    }
}
