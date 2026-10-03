import Foundation

protocol HuggingFaceClient: Sendable {
    /// Returns the HTTP status and, on 200, the account name.
    func whoami(token: String) async throws -> (status: Int, name: String?)
    /// Returns the HTTP status of the gated repository's auth-check endpoint.
    func authCheck(repo: String, token: String) async throws -> Int
}

struct URLSessionHuggingFaceClient: HuggingFaceClient {
    private func request(_ path: String, token: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "https://huggingface.co" + path)!)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    func whoami(token: String) async throws -> (status: Int, name: String?) {
        let (data, response) = try await URLSession.shared.data(for: request("/api/whoami-v2", token: token))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let name = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["name"] as? String
        return (status, status == 200 ? name : nil)
    }

    func authCheck(repo: String, token: String) async throws -> Int {
        let (_, response) = try await URLSession.shared.data(for: request("/api/models/\(repo)/auth-check", token: token))
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
