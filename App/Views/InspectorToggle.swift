import SwiftUI

/// Shows or hides the inspector. It is the last item of each screen's toolbar, at the trailing edge next to the pane it
/// controls, and shares its setting with the View menu through `inspectorShown`.
struct InspectorToggle: View {
    @AppStorage("inspectorShown") private var shown = true

    var body: some View {
        Button { shown.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
            .help(shown ? "Hide Inspector" : "Show Inspector")
            .accessibilityValue(shown ? "Shown" : "Hidden")
    }
}
