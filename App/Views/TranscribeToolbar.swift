import SwiftUI

/// A toolbar action drawn as an explicit capsule, so it keeps its accent colour when the system flattens toolbar glass
/// (Reduce Transparency). It is prominent only when there is something new to do.
struct CapsuleActionLabel: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let isEnabled: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Metric.sp6).padding(.vertical, Metric.sp3)
            .foregroundStyle(isPrimary ? Token.fgOnAccent : Native.fg)
            .background(isPrimary ? Token.accent : Token.surfaceSunken, in: Capsule())
            .overlay(Capsule().strokeBorder(isPrimary ? Color.clear : Token.border))
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// The toolbar's one prominent action: Transcribe / Transcribe Again / Download & Transcribe / Transcribing…
struct TranscribeButton: View {
    let label: String
    let isBusy: Bool
    let isPrimary: Bool
    let canStart: Bool
    var hint = "Transcribe the selected slice"
    let action: () -> Void

    private var isEnabled: Bool { !isBusy && canStart }

    var body: some View {
        Button(action: action) {
            CapsuleActionLabel(title: label, systemImage: "waveform.badge.magnifyingglass", isPrimary: isPrimary, isEnabled: isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .keyboardShortcut(.return)
        .help(hint)
        .accessibilityLabel(label)
    }
}
