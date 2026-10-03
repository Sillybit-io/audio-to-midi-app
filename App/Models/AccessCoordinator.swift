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
    var request: AccessRequest?
    var accountName: String?
    var tokenPresent: Bool

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
        guard let current = request else { return }
        request?.decision = await gate.evaluate(current.entry)
    }

    func saveToken(_ token: String) async {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        keychain.save(trimmed)
        tokenPresent = true
        await refreshAccount()
        await recheck()
    }

    func removeToken() {
        keychain.delete()
        tokenPresent = false
        accountName = nil
    }

    func refreshAccount() async {
        guard let token = keychain.read() else { accountName = nil; return }
        accountName = try? await client.whoami(token: token).name
    }

    func finish(agreed: Bool) {
        request = nil
        continuation?.resume(returning: agreed)
        continuation = nil
    }
}

struct HuggingFaceAccessPolicy: AccessPolicy {
    let coordinator: AccessCoordinator
    func authorize(_ entry: ModelEntry) async -> Bool { await coordinator.authorize(entry) }
}
