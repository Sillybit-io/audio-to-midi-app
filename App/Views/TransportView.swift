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
            Button { playback.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .help("Stop")
            Toggle(isOn: $playback.loops) { Label("Loop", systemImage: "repeat") }
                .toggleStyle(.button)
                .help("Loop (L)")
                .accessibilityValue(playback.loops ? "On" : "Off")
            Text("\(PlaybackEngine.timeText(seconds: playback.position)) \u{00B7} \(PlaybackEngine.barBeatText(seconds: playback.position))")
                .font(.body.monospacedDigit()).foregroundStyle(Native.fgSecondary)
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(PlaybackEngine.timeText(seconds: playback.position)), bar \(PlaybackEngine.barBeat(seconds: playback.position).bar) beat \(PlaybackEngine.barBeat(seconds: playback.position).beat)")
        }
    }
}
