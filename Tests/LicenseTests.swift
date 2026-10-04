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
            let keyword = switch entry.licenseKind {
            case .nonCommercial: "NonCommercial"
            case .commercialAllowed: "Apache License"
            case .attributionRequired: "Attribution 4.0 International"
            }
            #expect(joined.contains(keyword), "\(entry.id) text should name its licence")
        }
    }

    @Test func noticesHeadingsMatchComponents() {
        let text = ThirdPartyComponents.noticesText()
        #expect(!text.isEmpty)
        #expect(ThirdPartyComponents.headings(in: text) == ThirdPartyComponents.names)
    }

    @Test func onnxRuntimeNoticesAreBundled() {
        #expect(ThirdPartyComponents.onnxRuntimeNoticesText().contains("Third Party Notices") || ThirdPartyComponents.onnxRuntimeNoticesText().count > 100_000)
    }
}
