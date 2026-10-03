import Foundation
import Testing
@testable import SillyMIDITools

struct LicenseTests {
    @Test func everyCatalogEntryHasLicenseText() throws {
        let bundle = Bundle(for: ModelStoreProbe.self)
        for entry in ModelCatalog.entries {
            let joined = try entry.licenseTexts.map { t in
                try String(contentsOf: #require(bundle.url(forResource: t.resource, withExtension: t.ext)), encoding: .utf8)
            }.joined()
            #expect(!joined.isEmpty)
            let keyword = entry.licenseKind == .nonCommercial ? "NonCommercial" : "Apache License"
            #expect(joined.contains(keyword), "\(entry.id) text should name its licence")
        }
    }

    @Test func noticesHeadingsMatchComponents() {
        let text = ThirdPartyComponents.noticesText()
        #expect(!text.isEmpty)
        #expect(ThirdPartyComponents.headings(in: text) == ThirdPartyComponents.names)
    }
}
