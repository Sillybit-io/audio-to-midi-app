import Foundation
import Observation

struct AccessRequest: Identifiable {
    let id = UUID()
    let entry: ModelEntry
    var decision: GateDecision
}

/// Presents the licence sheet before a download and resolves the store's access policy.
@MainActor @Observable
final class AccessCoordinator {
    /// The licence sheet's request. SwiftUI clears it when it takes the sheet away, and a download that is still waiting
    /// for an answer is then released as declined rather than left waiting for good.
    var request: AccessRequest? {
        didSet { if request == nil { release(agreed: false) } }
    }
    var accountName: String?
    var tokenPresent: Bool
    /// A token is being checked with Hugging Face, so the screen can show it and hold the buttons.
    private(set) var isCheckingToken = false
    /// Why the last attempt to save a token failed, in words for the user. Cleared by the next attempt.
    private(set) var tokenError: String?

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let client: any HuggingFaceClient
    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?

    init(keychain: KeychainStore = KeychainStore(), client: any HuggingFaceClient = URLSessionHuggingFaceClient()) {
        self.keychain = keychain
        self.client = client
        tokenPresent = keychain.read() != nil
    }

    private var gate: ModelAccessGate {
        let keychain = keychain
        return ModelAccessGate(client: client, token: { keychain.read() })
    }

    func authorize(_ entry: ModelEntry) async -> Bool {
        guard entry.gated else { return true }
        let decision = await gate.evaluate(entry)
        request = AccessRequest(entry: entry, decision: decision)
        return await withCheckedContinuation { continuation = $0 }
    }

    func recheck() async {
        guard let current = request, !isCheckingToken else { return }
        isCheckingToken = true
        defer { isCheckingToken = false }
        request?.decision = await gate.evaluate(current.entry)
    }

    /// Stores the token, asks Hugging Face who it belongs to, and, when the licence sheet is open, whether that account
    /// may download the model. A token Hugging Face rejects is not kept.
    func saveToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isCheckingToken else { return }
        isCheckingToken = true
        tokenError = nil
        defer { isCheckingToken = false }
        guard keychain.save(trimmed), keychain.read() == trimmed else {
            tokenError = "The token couldn\u{2019}t be saved to your Keychain."
            return
        }
        tokenPresent = true
        await refreshAccount()
        guard tokenPresent else {
            request?.decision = .invalidToken
            return
        }
        if let current = request { request?.decision = await gate.evaluate(current.entry) }
    }

    func removeToken() {
        keychain.delete()
        tokenPresent = false
        accountName = nil
    }

    /// Looks up the account the saved token belongs to. A token Hugging Face rejects is removed; with no connection it stays.
    func refreshAccount() async {
        guard let token = keychain.read() else { accountName = nil; return }
        guard let who = try? await client.whoami(token: token) else { accountName = nil; return }
        if who.status == 401 {
            removeToken()
            tokenError = "Hugging Face rejected this token. Paste a valid read token."
            return
        }
        accountName = who.name
    }

    func finish(agreed: Bool) {
        let waiting = continuation
        continuation = nil
        request = nil
        waiting?.resume(returning: agreed)
    }

    private func release(agreed: Bool) {
        guard let waiting = continuation else { return }
        continuation = nil
        waiting.resume(returning: agreed)
    }
}

struct HuggingFaceAccessPolicy: AccessPolicy {
    let coordinator: AccessCoordinator
    func authorize(_ entry: ModelEntry) async -> Bool { await coordinator.authorize(entry) }
}
