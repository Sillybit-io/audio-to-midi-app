import AppKit
import SwiftUI

extension NSImage {
    /// The icon Launch Services has for this bundle.
    static var appIcon: NSImage { NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }
}

struct AboutView: View {
    private static let repository = URL(string: "https://github.com/Sillybit-io/silly-midi-tools")!
    private static let maker = URL(string: "https://github.com/Sillybit-io")!

    @AppStorage("aboutTab") private var tab = "about"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.0"
    }

    var body: some View {
        TabView(selection: $tab) {
            about.tabItem { Text("About") }.tag("about")
            GroupedLicencesView().tabItem { Text("Licences") }.tag("licences")
            LicenseTextView(text: ThirdPartyComponents.onnxRuntimeNoticesText())
                .tabItem { Text("ONNX Runtime") }.tag("onnx")
        }
        .frame(width: Metric.settingsW, height: Metric.aboutH)
    }

    private var about: some View {
        VStack(spacing: Metric.sp4) {
            Image(nsImage: .appIcon)
                .resizable().frame(width: Metric.appIconLg, height: Metric.appIconLg)
                .accessibilityHidden(true)
            Text("Silly MIDI Tools").font(.title.bold())
            Text("Version \(version)").foregroundStyle(Native.fgSecondary)
            HStack(spacing: Metric.sp2) {
                Text("Made by").foregroundStyle(Native.fgSecondary)
                Link("Sillybit", destination: Self.maker)
            }
            Text("macOS 26 or later · Apple silicon").font(.caption).foregroundStyle(Native.fgSecondary)
            Text("Licensed under the Apache License 2.0.")
            Text("MuScriptor (CC BY-NC 4.0) and Drums (ADTOF) (CC BY-NC-SA 4.0) are for non-commercial use only, including the MIDI they produce. The piano model is CC BY 4.0 and needs credit. Basic Pitch, Drums (OaF) and Hand percussion are Apache-2.0. Check each model\u{2019}s licence before using its output commercially.")
                .font(.caption).foregroundStyle(Native.fgSecondary).multilineTextAlignment(.center)
                .frame(maxWidth: Metric.sheetW + Metric.sp10)
            HStack(spacing: Metric.sp6) {
                Link("Silly MIDI Tools on GitHub", destination: Self.repository)
                Button("Acknowledgements") { tab = "licences" }.buttonStyle(.link)
            }
        }
        .padding(Metric.sp8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
