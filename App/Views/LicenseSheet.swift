import SwiftUI

struct LicenseSheet: View {
    let coordinator: AccessCoordinator
    let request: AccessRequest
    @State private var nonCommercial = false
    @State private var ownsAudio = false
    @State private var asIs = false
    @State private var token = ""
    @Environment(\.openURL) private var openURL

    private var text: String {
        let bundle = Bundle(for: ModelStoreProbe.self)
        return request.entry.licenseTexts.compactMap { t in
            bundle.url(forResource: t.resource, withExtension: t.ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n---\n\n")
    }

    private var message: String? {
        switch request.decision {
        case .allowed: nil
        case .needsToken: "Paste a Hugging Face read token to continue."
        case .invalidToken: "Hugging Face rejected this token. Paste a valid read token."
        case .needsTerms: "Your account has not accepted the model's terms yet. Open the model page, accept them, then check again."
        case .failed(let m): m
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.sp5) {
            HStack { Text(request.entry.displayName).font(.title2.bold()); LicenseBadge(entry: request.entry) }
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                .frame(height: Metric.licenceTextH).border(.separator)
            Toggle("I will use this model and its MIDI output for non-commercial purposes only.", isOn: $nonCommercial)
            Toggle("I hold the rights to the audio I transcribe.", isOn: $ownsAudio)
            Toggle("The model and its output are provided as is; Mirelo and Kyutai are not liable.", isOn: $asIs)
            if let message { Text(message).foregroundStyle(Token.warn) }
            if request.decision == .needsToken || request.decision == .invalidToken {
                HStack {
                    SecureField("Hugging Face read token", text: $token)
                    Button("Save and check") { Task { await coordinator.saveToken(token); token = "" } }
                }
            }
            HStack {
                if let url = request.entry.modelPageURL { Button("Open model page") { openURL(url) } }
                Button("Check again") { Task { await coordinator.recheck() } }
                Spacer()
                Button("Cancel") { coordinator.finish(agreed: false) }
                Button("I agree, download") { coordinator.finish(agreed: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(request.decision != .allowed || !(nonCommercial && ownsAudio && asIs))
            }
        }
        .padding(Metric.sp7).frame(width: Metric.licenceSheetW)
    }
}
