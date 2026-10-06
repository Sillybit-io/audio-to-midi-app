import Foundation
import Testing
@testable import SillyMIDITools

private final class ScriptedClient: HuggingFaceClient, @unchecked Sendable {
    var whoamiStatus = 200
    var authStatus = 200
    var delay: Duration = .zero

    func whoami(token: String) async throws -> (status: Int, name: String?) {
        try await Task.sleep(for: delay)
        return (whoamiStatus, whoamiStatus == 200 ? "tester" : nil)
    }

    func authCheck(repo: String, token: String) async throws -> Int {
        try await Task.sleep(for: delay)
        return authStatus
    }
}

@MainActor
struct AccessCoordinatorTests {
    private let gated = ModelCatalog.entries[0]

    fileprivate func make(_ client: ScriptedClient) -> (coordinator: AccessCoordinator, keychain: KeychainStore) {
        let keychain = KeychainStore(service: "smt-test-\(UUID().uuidString)")
        return (AccessCoordinator(keychain: keychain, client: client), keychain)
    }

    /// Opens the licence sheet's request the way a download does and waits until it is showing.
    fileprivate func openRequest(_ coordinator: AccessCoordinator) async -> Task<Bool, Never> {
        let task = Task { await coordinator.authorize(gated) }
        for _ in 0..<100 where coordinator.request == nil { try? await Task.sleep(for: .milliseconds(10)) }
        return task
    }

    @Test func savingATokenShowsProgressThenEnablesTheDownload() async {
        let client = ScriptedClient()
        let (coordinator, keychain) = make(client)
        defer { keychain.delete() }
        let task = await openRequest(coordinator)
        #expect(coordinator.request?.decision == .needsToken)

        client.delay = .milliseconds(150)
        let save = Task { await coordinator.saveToken("  hf_valid  ") }
        try? await Task.sleep(for: .milliseconds(60))
        #expect(coordinator.isCheckingToken)

        await save.value
        #expect(coordinator.isCheckingToken == false)
        #expect(coordinator.request?.decision == .allowed)
        #expect(coordinator.accountName == "tester")
        #expect(keychain.read() == "hf_valid")

        coordinator.finish(agreed: false)
        _ = await task.value
    }

    @Test func aRejectedTokenIsNotKeptAndTheSheetSaysSo() async {
        let client = ScriptedClient()
        client.whoamiStatus = 401
        let (coordinator, keychain) = make(client)
        defer { keychain.delete() }
        let task = await openRequest(coordinator)

        await coordinator.saveToken("hf_wrong")

        #expect(coordinator.request?.decision == .invalidToken)
        #expect(coordinator.tokenPresent == false)
        #expect(keychain.read() == nil)

        coordinator.finish(agreed: false)
        _ = await task.value
    }

    @Test func settingsRejectsABadTokenInsteadOfCallingItSaved() async {
        let client = ScriptedClient()
        client.whoamiStatus = 401
        let (coordinator, keychain) = make(client)
        defer { keychain.delete() }

        await coordinator.saveToken("hf_wrong")

        #expect(coordinator.tokenPresent == false)
        #expect(coordinator.tokenError?.contains("rejected") == true)
    }

    @Test func termsNotAcceptedLeavesTheDownloadBlockedWithAReason() async {
        let client = ScriptedClient()
        client.authStatus = 403
        let (coordinator, keychain) = make(client)
        defer { keychain.delete() }
        let task = await openRequest(coordinator)

        await coordinator.saveToken("hf_valid")

        #expect(coordinator.request?.decision == .needsTerms(gated.modelPageURL))
        #expect(coordinator.tokenPresent)

        coordinator.finish(agreed: false)
        _ = await task.value
    }
}

extension AccessCoordinatorTests {
    @Test func aSheetTakenAwayWithoutAnAnswerReleasesTheWaitingDownload() async {
        let (coordinator, keychain) = make(ScriptedClient())
        defer { keychain.delete() }
        let task = await openRequest(coordinator)
        #expect(coordinator.request != nil)

        coordinator.request = nil

        #expect(await task.value == false)
    }

    @Test func finishingTwiceAnswersOnce() async {
        let (coordinator, keychain) = make(ScriptedClient())
        defer { keychain.delete() }
        let task = await openRequest(coordinator)

        coordinator.finish(agreed: true)
        coordinator.finish(agreed: false)

        #expect(await task.value == true)
    }
}
