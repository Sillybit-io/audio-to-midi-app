import Foundation
import Testing
@testable import SillyMIDITools

private final class MockClient: HuggingFaceClient, @unchecked Sendable {
    var whoamiStatus = 200
    var authStatus = 200
    var fail = false
    private(set) var calls = 0

    func whoami(token: String) async throws -> (status: Int, name: String?) {
        calls += 1
        if fail { throw URLError(.notConnectedToInternet) }
        return (whoamiStatus, "tester")
    }

    func authCheck(repo: String, token: String) async throws -> Int {
        calls += 1
        return authStatus
    }
}

struct AccessGateTests {
    private let gated = ModelCatalog.entries[0]

    @Test func ungatedModelIsAllowedWithoutNetwork() async {
        let client = MockClient()
        let gate = ModelAccessGate(client: client, token: { nil })
        #expect(await gate.evaluate(ModelCatalog.entries[3]) == .allowed)
        #expect(client.calls == 0)
    }

    @Test func noTokenMeansNoNetworkCall() async {
        let client = MockClient()
        let gate = ModelAccessGate(client: client, token: { nil })
        #expect(await gate.evaluate(gated) == .needsToken)
        #expect(client.calls == 0)
    }

    @Test func rejectedTokenIsInvalid() async {
        let client = MockClient()
        client.whoamiStatus = 401
        let gate = ModelAccessGate(client: client, token: { "t" })
        #expect(await gate.evaluate(gated) == .invalidToken)
    }

    @Test func unacceptedTermsNeedTheModelPage() async {
        let client = MockClient()
        client.authStatus = 403
        let gate = ModelAccessGate(client: client, token: { "t" })
        #expect(await gate.evaluate(gated) == .needsTerms(gated.modelPageURL))
    }

    @Test func acceptedTermsAreAllowed() async {
        let gate = ModelAccessGate(client: MockClient(), token: { "t" })
        #expect(await gate.evaluate(gated) == .allowed)
    }

    @Test func networkFailureIsReported() async {
        let client = MockClient()
        client.fail = true
        let gate = ModelAccessGate(client: client, token: { "t" })
        guard case .failed = await gate.evaluate(gated) else { Issue.record("expected failed"); return }
    }

    @Test func keychainRoundTrip() {
        let store = KeychainStore(service: "io.sillybit.sillymiditools.tests.\(UUID().uuidString)")
        #expect(store.read() == nil)
        store.save("abc")
        #expect(store.read() == "abc")
        store.save("def")
        #expect(store.read() == "def")
        store.delete()
        #expect(store.read() == nil)
    }
}
