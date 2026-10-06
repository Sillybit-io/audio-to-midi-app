import SwiftUI

/// Play/Pause, Stop, the position as time and bar.beat, and Loop. The Audio screen and the MIDI editor share it,
/// and the Controls menu drives the same `PlaybackEngine`, so the buttons and the menu can't disagree.
struct TransportView: View {
    @Bindable var playback: PlaybackEngine
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Metric.sp3) {
            Button(action: toggle) {
                Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(playback.isPlaying ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            Button { playback.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .help("Stop")
                .accessibilityLabel("Stop")
            Toggle(isOn: $playback.loops) { Label("Loop", systemImage: "repeat") }
                .toggleStyle(.button)
                .help("Loop (L)")
                .accessibilityLabel("Loop")
                .accessibilityValue(playback.loops ? "On" : "Off")
            // The hidden text is the widest the readout gets for this audio: it never clips, never moves the toolbar
            // while playing, and leaves no spare room after short audio.
            ZStack(alignment: .leading) {
                Text(Self.readout(playback.duration)).hidden().accessibilityHidden(true)
                Text(Self.readout(playback.position))
            }
            .font(.body.monospacedDigit()).foregroundStyle(Native.fgSecondary).lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
                .accessibilityValue("\(PlaybackEngine.timeText(seconds: playback.position)), bar \(PlaybackEngine.barBeat(seconds: playback.position).bar) beat \(PlaybackEngine.barBeat(seconds: playback.position).beat)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transport")
    }

    private static func readout(_ seconds: Double) -> String {
        "\(PlaybackEngine.timeText(seconds: seconds)) \u{00B7} \(PlaybackEngine.barBeatText(seconds: seconds))"
    }
}
