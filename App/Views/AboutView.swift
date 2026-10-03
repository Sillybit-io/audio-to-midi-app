import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        TabView {
            VStack(spacing: 8) {
                Text("Silly MIDI Tools").font(.title.bold())
                Text("Version \(version)").foregroundStyle(.secondary)
                Text("Licensed under the Apache License 2.0.")
                Text("MuScriptor models are non-commercial use only; Basic Pitch allows commercial use.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .tabItem { Text("About") }
            ScrollView {
                Text(ThirdPartyComponents.noticesText()).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).padding()
            }
            .tabItem { Text("Licences") }
        }
        .frame(width: 640, height: 460)
    }
}
