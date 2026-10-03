import SwiftUI

struct SettingsView: View {
    let coordinator: AccessCoordinator
    @State private var token = ""

    var body: some View {
        Form {
            Section("Hugging Face") {
                if coordinator.tokenPresent {
                    Text(coordinator.accountName.map { "Signed in as \($0)" } ?? "Token saved")
                    Button("Remove token", role: .destructive) { coordinator.removeToken() }
                } else {
                    SecureField("Read token", text: $token)
                    Button("Save and check") { Task { await coordinator.saveToken(token); token = "" } }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .task { await coordinator.refreshAccount() }
    }
}
