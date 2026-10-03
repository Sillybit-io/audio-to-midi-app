import Foundation

enum GateDecision: Equatable, Sendable {
    case allowed
    case needsToken
    case invalidToken
    case needsTerms(URL?)
    case failed(String)
}

struct ModelAccessGate: Sendable {
    let client: any HuggingFaceClient
    let token: @Sendable () -> String?

    func evaluate(_ entry: ModelEntry) async -> GateDecision {
        guard entry.gated, let repo = entry.authorsRepo else { return .allowed }
        guard let token = token(), !token.isEmpty else { return .needsToken }
        do {
            let who = try await client.whoami(token: token)
            if who.status == 401 { return .invalidToken }
            guard who.status == 200 else { return .failed("Hugging Face answered with status \(who.status).") }
            switch try await client.authCheck(repo: repo, token: token) {
            case 200: return .allowed
            case 401, 403: return .needsTerms(entry.modelPageURL)
            case let other: return .failed("Hugging Face answered with status \(other).")
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
