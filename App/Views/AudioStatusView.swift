import SwiftUI

/// Progress while a run is going (including a first-use download), and the failed panel with Try Again.
struct AudioStatusView: View {
    let panel: AudioScreenModel.RunPanel?
    let startedAt: Date?
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        switch panel {
        case .running(let steps, let current, let fraction)?:
            running(steps, current, fraction).padding(.vertical, Metric.sp4)
        case .failed(let title, let message)?:
            failed(title, message).padding(.vertical, Metric.sp4)
        case nil:
            EmptyView()
        }
    }

    private func running(_ steps: [String], _ current: Int, _ fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: Metric.sp4) {
            HStack(spacing: Metric.sp3) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, name in
                    chip(name, state: index < current ? .done : index == current ? .active : .pending)
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

    private func failed(_ title: String, _ message: String) -> some View {
        HStack(alignment: .top, spacing: Metric.sp4) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Native.danger)
            VStack(alignment: .leading, spacing: Metric.sp1) {
                Text(title).bold()
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
