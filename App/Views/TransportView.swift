import SwiftUI

struct TransportView: View {
    let playback: PlaybackEngine
    let instruments: [String]
    let prepare: () -> Void
    @State private var muted: Set<String> = []

    var body: some View {
        HStack(spacing: 12) {
            Button(playback.isPlaying ? "Pause" : "Play") {
                if playback.isPlaying { playback.pause() } else { prepare(); playback.play() }
            }
            Button("Stop") { playback.stop() }
            Text(String(format: "%.1f s", playback.position)).monospacedDigit().foregroundStyle(.secondary)
            HStack { Text("Original").font(.caption); Slider(value: Binding(get: { playback.mix }, set: { playback.mix = $0 })); Text("Notes").font(.caption) }
                .frame(width: 220)
            HStack { Text("Speed").font(.caption); Slider(value: Binding(get: { Double(playback.rate) }, set: { playback.rate = Float($0) }), in: 0.5...2) }
                .frame(width: 150)
            ForEach(instruments, id: \.self) { name in
                Toggle("Mute \(name.replacingOccurrences(of: "_", with: " "))", isOn: Binding(
                    get: { muted.contains(name) },
                    set: { if $0 { muted.insert(name) } else { muted.remove(name) }; playback.setMuted(name, $0) }))
                    .toggleStyle(.button).controlSize(.small)
            }
            if let error = playback.lastError { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }
}
