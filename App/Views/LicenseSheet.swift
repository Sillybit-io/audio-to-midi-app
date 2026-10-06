import SwiftUI

struct LicenseSheet: View {
    let coordinator: AccessCoordinator
    let request: AccessRequest
    @State private var ticked: Set<Int> = []
    @State private var token = ""
    @Environment(\.openURL) private var openURL

    /// The sheet is handed the request when it opens; the coordinator holds the one that changes as checks finish.
    private var current: AccessRequest { coordinator.request ?? request }
    private var agreed: Bool { ticked.count == request.entry.statements.count }
    private var checksHuggingFace: Bool { request.entry.access == .huggingFaceGated }

    private var text: String {
        let bundle = Bundle(for: ModelStoreProbe.self)
        return request.entry.licenseTexts.compactMap { t in
            bundle.url(forResource: t.resource, withExtension: t.ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }.joined(separator: "\n\n---\n\n")
    }

    private var message: String? {
        switch current.decision {
        case .allowed: nil
        case .needsToken: "Paste a Hugging Face read token to continue."
        case .invalidToken: "Hugging Face rejected this token. Paste a valid read token."
        case .needsTerms: "Your account has not accepted the model's terms yet. Open the model page, accept them, then check again."
        case .failed(let m): m
        }
    }

    private func save() {
        let value = token
        token = ""
        Task { await coordinator.saveToken(value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metric.sp5) {
            HStack { Text(request.entry.displayName).font(.title2.bold()); LicenseBadge(entry: request.entry) }
            ScrollView { Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                .frame(height: Metric.licenceTextH).border(.separator)
            ForEach(Array(request.entry.statements.enumerated()), id: \.offset) { index, statement in
                Toggle(statement, isOn: Binding(
                    get: { ticked.contains(index) },
                    set: { if $0 { ticked.insert(index) } else { ticked.remove(index) } }))
            }
            if let message { Text(message).foregroundStyle(Token.warn) }
            if let error = coordinator.tokenError, current.decision != .invalidToken { Text(error).foregroundStyle(Token.warn) }
            if checksHuggingFace, current.decision == .needsToken || current.decision == .invalidToken {
                HStack {
                    SecureField("Hugging Face read token", text: $token)
                        .disabled(coordinator.isCheckingToken)
                        .onSubmit(save)
                    Button("Save and check", action: save)
                        .disabled(coordinator.isCheckingToken || token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if coordinator.isCheckingToken {
                HStack(spacing: Metric.sp3) {
                    ProgressView().controlSize(.small)
                    Text("Checking with Hugging Face\u{2026}").foregroundStyle(Native.fgSecondary)
                }
            } else if checksHuggingFace, current.decision == .allowed {
                Label(coordinator.accountName.map { "Signed in as \($0). This account can download the model." }
                      ?? "This account can download the model.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Token.accentText)
            }
            HStack {
                if let url = current.entry.modelPageURL { Button("Open model page") { openURL(url) } }
                if checksHuggingFace {
                    Button("Check again") { Task { await coordinator.recheck() } }
                        .disabled(coordinator.isCheckingToken)
                }
                Spacer()
                Button("Cancel") { coordinator.finish(agreed: false) }
                Button("I agree, download") { coordinator.finish(agreed: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(current.decision != .allowed || !agreed || coordinator.isCheckingToken)
            }
            if current.decision == .allowed, !agreed {
                Text("Tick the statements above to enable the download.").font(.caption).foregroundStyle(Native.fgSecondary)
            }
        }
        .padding(Metric.sp7).frame(width: Metric.licenceSheetW)
    }
}
