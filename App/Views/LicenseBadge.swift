import SwiftUI

struct LicenseBadge: View {
    let entry: ModelEntry

    var body: some View {
        let warns = entry.licenseKind == .nonCommercial
        Text(entry.licenseKind.badge)
            .font(.caption.bold())
            .foregroundStyle(warns ? Token.warn : Token.success)
            .padding(.horizontal, Metric.sp4).padding(.vertical, Metric.sp1)
            .background(warns ? Token.warnSoft : Token.success.opacity(0.15), in: Capsule())
    }
}
