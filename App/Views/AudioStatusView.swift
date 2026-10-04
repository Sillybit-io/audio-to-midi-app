import SwiftUI

/// Progress while a run is going, and the failed panel with Try Again. Nothing shows in the other states.
struct AudioStatusView: View {
    let session: TranscriptionSession
    let startedAt: Date?
    let estimatesVelocity: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        switch session.state {
        case .loading, .running, .refining:
            running.padding(.vertical, Metric.sp4)
        case .failed(let message):
            failed(message).padding(.vertical, Metric.sp4)
        default:
            EmptyView()
        }
    }

    private var steps: [String] {
        ["Load model", "Transcribe"] + (estimatesVelocity ? ["Estimate velocity"] : [])
    }

    private var currentStep: Int {
        switch session.state {
        case .loading: 0
        case .running: 1
        case .refining: 2
        default: 0
        }
    }

    private var fraction: Double? {
        switch session.state {
        case .loading(let p): p
        case .running: session.progress
        default: nil
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: Metric.sp4) {
            HStack(spacing: Metric.sp3) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, name in
                    chip(name, state: index < currentStep ? .done : index == currentStep ? .active : .pending)
                }
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(".", modifiers: .command)
            }
            HStack(spacing: Metric.sp4) {
                if let fraction {
                    ProgressView(value: fraction)
                    Text("\(Int((fraction * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                if let startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text("\(max(0, Int(context.date.timeIntervalSince(startedAt)))) s elapsed")
                            .font(.caption.monospacedDigit()).foregroundStyle(Native.fgSecondary)
                    }
                }
            }
        }
        .padding(Metric.sp5)
        .background(Token.surfaceRaised, in: RoundedRectangle(cornerRadius: Metric.rRow))
        .overlay(RoundedRectangle(cornerRadius: Metric.rRow).strokeBorder(Token.border))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcription progress")
    }

    private func failed(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Metric.sp4) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Native.danger)
            VStack(alignment: .leading, spacing: Metric.sp1) {
                Text("Transcription failed").bold()
                Text(message).font(.caption).foregroundStyle(Native.fgSecondary)
            }
            Spacer()
            Button("Try Again", action: onRetry)
        }
        .padding(Metric.sp5)
        .background(Token.surfaceRaised, in: RoundedRectangle(cornerRadius: Metric.rRow))
        .overlay(RoundedRectangle(cornerRadius: Metric.rRow).strokeBorder(Native.danger))
        .accessibilityElement(children: .contain)
    }

    private enum ChipState { case done, active, pending }

    private func chip(_ name: String, state: ChipState) -> some View {
        HStack(spacing: Metric.sp2) {
            if state == .done { Image(systemName: "checkmark").font(.caption2.bold()) }
            Text(name).font(.caption)
        }
        .foregroundStyle(state == .active ? Token.accentText : state == .done ? Native.success : Native.fgSecondary)
        .padding(.horizontal, Metric.sp4).padding(.vertical, Metric.sp1)
        .background(state == .active ? Token.accentSoft : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(state == .pending ? Token.border : Color.clear))
    }
}
