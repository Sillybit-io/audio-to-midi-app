import SwiftUI

/// The toolbar's one prominent action: Transcribe / Transcribe Again / Download & Transcribe / Transcribing…
/// Drawn as an explicit capsule so it keeps its accent colour when the system flattens toolbar glass.
struct TranscribeButton: View {
    let label: String
    let isBusy: Bool
    let isPrimary: Bool
    let canStart: Bool
    let action: () -> Void

    private var isEnabled: Bool { !isBusy && canStart }

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: "waveform.badge.magnifyingglass")
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Metric.sp5).padding(.vertical, Metric.sp2)
                .foregroundStyle(isPrimary ? Token.fgOnAccent : Native.fg)
                .background(isPrimary ? Token.accent : Token.surfaceSunken, in: Capsule())
                .overlay(Capsule().strokeBorder(isPrimary ? Color.clear : Token.border))
                .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(.return)
        .help("Transcribe the selected slice")
        .accessibilityLabel(label)
    }
}
