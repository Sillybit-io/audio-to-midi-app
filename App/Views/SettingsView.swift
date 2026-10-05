import SwiftUI

struct SettingsView: View {
    let coordinator: AccessCoordinator
    let store: ModelStore
    let workingFolder: WorkingFolderStore
    let preferences: AppPreferences

    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            SettingsGeneralView(workingFolder: workingFolder, preferences: preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            SettingsModelsView(store: store)
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag("models")
            HuggingFaceSettingsView(coordinator: coordinator)
                .tabItem { Label("Hugging Face", systemImage: "key") }
                .tag("huggingface")
        }
        .frame(width: Metric.settingsW)
        .frame(minHeight: Metric.settingsMinH)
        .preferredColorScheme(preferences.appearance.colorScheme)
    }
}

struct HuggingFaceSettingsView: View {
    let coordinator: AccessCoordinator
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                if coordinator.tokenPresent {
                    Text(coordinator.accountName.map { "Signed in as \($0)" } ?? "Token saved")
                    Button("Remove token", role: .destructive) { coordinator.removeToken() }
                } else {
                    SecureField("Read token", text: $token)
                    Button("Save and check") { Task { await coordinator.saveToken(token); token = "" } }
                }
            } header: {
                Text("Hugging Face")
            } footer: {
                Text("Needed only for MuScriptor. The token is kept in your Keychain.")
            }
        }
        .formStyle(.grouped)
        .task { await coordinator.refreshAccount() }
    }
}
