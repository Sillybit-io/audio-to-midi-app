import AVFoundation
import Observation

/// Plays transcribed notes through AVAudioSequencer and one AVAudioUnitSampler per instrument group,
/// next to the original audio on a player node. Every group's sampler and track exist before a
/// sequence plays; a group that appears mid-playback pauses the transport briefly to be added.
@MainActor @Observable
final class PlaybackEngine {
    private struct Group {
        let sampler: AVAudioUnitSampler
        let track: AVMusicTrack
    }

    nonisolated static let soundBankURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
    /// 120 bpm: two beats per second.
    nonisolated static let beatsPerSecond = 2.0

    private(set) var isPlaying = false
    private(set) var position = 0.0
    private(set) var lastError: String?
    var duration = 0.0
    /// Playback pauses here while a transcription is still running.
    var limit: Double? { didSet { if let limit, waitingForLimit, position < limit { play() } } }
    var mix = 0.5 { didSet { applyMix() } }
    var rate: Float = 1 { didSet { sequencer.rate = rate; timePitch.rate = rate } }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let timePitch = AVAudioUnitTimePitch()
    @ObservationIgnored private let sequencer: AVAudioSequencer
    @ObservationIgnored private var groups: [String: Group] = [:]
    @ObservationIgnored private var muted: Set<String> = []
    @ObservationIgnored private var added = 0
    @ObservationIgnored private var latest: [NoteEvent] = []
    @ObservationIgnored private var syncing = false
    @ObservationIgnored private var original: AVAudioPCMBuffer?
    @ObservationIgnored private var waitingForLimit = false
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var clockStart: (position: Double, time: Date)?

    init() {
        sequencer = AVAudioSequencer(audioEngine: engine)
        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        sequencer.tempoTrack.addEvent(AVExtendedTempoEvent(tempo: 120), at: 0)
        applyMix()
    }

    // MARK: Pure helpers

    nonisolated static func beats(forSeconds seconds: Double) -> Double { seconds * beatsPerSecond }

    nonisolated static func patch(program: Int, isDrum: Bool) -> (program: UInt8, bankMSB: UInt8, bankLSB: UInt8) {
        if isDrum || program >= 128 { return (0, 0x78, 0) }
        return (UInt8(max(0, min(127, program))), 0x79, 0)
    }

    nonisolated static func groupKey(_ note: NoteEvent) -> String { note.isDrum ? "drums" : note.instrument }

    // MARK: Original audio

    func setOriginal(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty, let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { original = nil; return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        original = buffer
        engine.connect(player, to: timePitch, format: format)
    }

    private func applyMix() {
        player.volume = Float(min(1, 2 * (1 - mix)))
        for group in groups.values { group.sampler.volume = Float(min(1, 2 * mix)) }
    }

    // MARK: Notes

    func sync(notes: [NoteEvent]) {
        latest = notes
        guard !syncing else { return }
        syncing = true
        Task { @MainActor in
            while true {
                let snapshot = latest
                await apply(snapshot)
                if latest.count == snapshot.count { break }
            }
            syncing = false
        }
    }

    private func apply(_ notes: [NoteEvent]) async {
        if notes.count < added {
            for group in groups.values { group.track.clearEvents(in: AVBeatRange(start: 0, length: .greatestFiniteMagnitude)) }
            added = 0
        }
        for note in notes[added...] {
            let key = Self.groupKey(note)
            if groups[key] == nil { await createGroup(key, program: note.program, isDrum: note.isDrum) }
            guard let group = groups[key], note.offset > note.onset else { continue }
            let event = AVMIDINoteEvent(channel: note.isDrum ? 9 : 0, key: UInt32(max(0, min(127, note.pitch))),
                                        velocity: UInt32(note.velocity ?? 100), duration: Self.beats(forSeconds: note.offset - note.onset))
            group.track.addEvent(event, at: Self.beats(forSeconds: note.onset))
        }
        added = notes.count
    }

    private func createGroup(_ key: String, program: Int, isDrum: Bool) async {
        let resume = isPlaying
        if resume { pauseTransport() }
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
        let patch = Self.patch(program: program, isDrum: isDrum)
        nonisolated(unsafe) let unit = sampler
        do {
            try await Task.detached(priority: .userInitiated) {
                try unit.loadSoundBankInstrument(at: Self.soundBankURL, program: patch.program, bankMSB: patch.bankMSB, bankLSB: patch.bankLSB)
            }.value
        } catch {
            lastError = "Could not load the General MIDI sound bank: \(error.localizedDescription)"
        }
        let track = sequencer.createAndAppendTrack()
        track.destinationAudioUnit = sampler
        track.isMuted = muted.contains(key)
        groups[key] = Group(sampler: sampler, track: track)
        applyMix()
        if resume { play() }
    }

    func setMuted(_ key: String, _ isMuted: Bool) {
        if isMuted { muted.insert(key) } else { muted.remove(key) }
        groups[key]?.track.isMuted = isMuted
    }

    // MARK: Transport

    func play() {
        guard !isPlaying else { return }
        waitingForLimit = false
        if let limit, position >= limit { waitingForLimit = true; return }
        do {
            if !engine.isRunning { try engine.start() }
            sequencer.currentPositionInSeconds = position
            sequencer.rate = rate
            schedulePlayer(from: position)
            if groups.isEmpty {
                clockStart = (position, Date())
            } else {
                clockStart = nil
                sequencer.prepareToPlay()
                try sequencer.start()
            }
            player.play()
            isPlaying = true
            startTicker()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func schedulePlayer(from seconds: Double) {
        player.stop()
        guard let original else { return }
        let rate = original.format.sampleRate
        let start = AVAudioFramePosition(seconds * rate)
        guard start < AVAudioFramePosition(original.frameLength) else { return }
        let remaining = AVAudioFrameCount(AVAudioFramePosition(original.frameLength) - start)
        guard let segment = AVAudioPCMBuffer(pcmFormat: original.format, frameCapacity: remaining) else { return }
        segment.frameLength = remaining
        segment.floatChannelData![0].update(from: original.floatChannelData![0] + Int(start), count: Int(remaining))
        player.scheduleBuffer(segment, completionHandler: nil)
    }

    private var currentPosition: Double {
        if let clockStart { return clockStart.position + Date().timeIntervalSince(clockStart.time) * Double(rate) }
        return sequencer.currentPositionInSeconds
    }

    private func pauseTransport() {
        position = currentPosition
        clockStart = nil
        sequencer.stop()
        player.stop()
        isPlaying = false
        ticker?.cancel()
    }

    func pause() {
        waitingForLimit = false
        if isPlaying { pauseTransport() }
    }

    func stop() {
        pause()
        position = 0
        sequencer.currentPositionInSeconds = 0
    }

    func seek(to seconds: Double) {
        let resume = isPlaying
        if resume { pauseTransport() }
        position = max(0, seconds)
        if resume { play() }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard let self, self.isPlaying else { return }
                self.position = self.currentPosition
                if let limit = self.limit, self.position >= limit {
                    self.pauseTransport()
                    self.position = limit
                    self.waitingForLimit = true
                    return
                }
                if self.limit == nil, self.duration > 0, self.position >= self.duration { self.stop(); return }
            }
        }
    }

    // MARK: Offline rendering (tests)

    /// Renders the synthesised notes offline and returns the RMS of the output.
    func renderOffline(notes: [NoteEvent], seconds: Double) async throws -> Float {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        await apply(notes)
        try engine.start()
        sequencer.currentPositionInSeconds = 0
        if !groups.isEmpty {
            sequencer.prepareToPlay()
            try sequencer.start()
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
        var sum: Double = 0
        var count = 0
        var rendered = 0
        let total = Int(seconds * 44100)
        while rendered < total {
            let status = try engine.renderOffline(AVAudioFrameCount(min(4096, total - rendered)), to: buffer)
            guard status == .success else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                let data = buffer.floatChannelData![channel]
                for i in 0..<Int(buffer.frameLength) { sum += Double(data[i] * data[i]); count += 1 }
            }
            rendered += Int(buffer.frameLength)
        }
        sequencer.stop()
        engine.stop()
        return count > 0 ? Float((sum / Double(count)).squareRoot()) : 0
    }
}
