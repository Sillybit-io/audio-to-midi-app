import CryptoKit
import Foundation
import Testing
@testable import SillyMIDITools

struct ModelStoreTests {
    @Test func catalogSumsMatchPinnedRevision() {
        let sums = Dictionary(uniqueKeysWithValues: ModelCatalog.entries.compactMap { e in e.sha256.map { (e.id, $0) } })
        #expect(sums["muscriptor-small"] == "925f55af65a20ebc4f8b45ceaf095a12b72493d436cb112623cd0041a1af23d4")
        #expect(sums["muscriptor-medium"] == "3850cc9e5b436b17a09bd25b8f2615cb3366ab96a71e7b50f73a793a917fdf03")
        #expect(sums["muscriptor-large"] == "35a750fb1ab1e77195cdc2c0b9b4aeea2f4d59f11f729f02af9920c4854ef72e")
        let urls = ModelCatalog.entries.compactMap(\.downloadURL)
        #expect(urls.count == 3)
        #expect(urls.allSatisfy { $0.absoluteString.contains("d7045f94e8b19427f4ff9542975035e66596e51c") && !$0.absoluteString.contains("/main/") })
    }

    @Test func verifyAcceptsGoodAndRejectsCorruptFile() async throws {
        let good = Data((0..<4096).map { UInt8($0 % 251) })
        let sum = SHA256.hash(data: good).map { String(format: "%02x", $0) }.joined()
        let dir = FileManager.default.temporaryDirectory
        let okURL = dir.appendingPathComponent("ok-\(UUID().uuidString).bin")
        try good.write(to: okURL)
        try await ModelStore.verify(fileAt: okURL, sha256: sum, byteSize: Int64(good.count))
        #expect(FileManager.default.fileExists(atPath: okURL.path))
        try? FileManager.default.removeItem(at: okURL)

        var bad = good
        bad[10] ^= 0xFF
        let badURL = dir.appendingPathComponent("bad-\(UUID().uuidString).bin")
        try bad.write(to: badURL)
        await #expect(throws: ModelStoreError.self) {
            try await ModelStore.verify(fileAt: badURL, sha256: sum, byteSize: Int64(good.count))
        }
        #expect(!FileManager.default.fileExists(atPath: badURL.path))
    }

    @Test func licenseResourcesResolve() throws {
        let bundle = Bundle(for: ModelStoreProbe.self)
        for entry in ModelCatalog.entries {
            #expect(!entry.licenseTexts.isEmpty)
            for text in entry.licenseTexts {
                let url = try #require(bundle.url(forResource: text.resource, withExtension: text.ext), "\(text.resource) missing")
                #expect(try String(contentsOf: url, encoding: .utf8).count > 100)
            }
        }
    }
}
