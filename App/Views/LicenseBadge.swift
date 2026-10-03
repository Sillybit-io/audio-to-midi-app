import SwiftUI

struct LicenseBadge: View {
    let entry: ModelEntry

    var body: some View {
        Text(entry.licenseKind.badge)
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(entry.licenseKind == .nonCommercial ? Color.orange.opacity(0.25) : Color.green.opacity(0.25), in: Capsule())
    }
}
