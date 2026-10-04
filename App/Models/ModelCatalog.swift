import Foundation

struct LicenseText: Hashable, Sendable {
    let resource: String
    let ext: String
}

enum LicenseKind: Sendable {
    case nonCommercial
    case commercialAllowed
    case attributionRequired

    var badge: String {
        switch self {
        case .nonCommercial: "Non-commercial use only"
        case .commercialAllowed: "Commercial use allowed"
        case .attributionRequired: "Commercial use allowed with credit"
        }
    }
}

struct ModelEntry: Identifiable, Hashable, Sendable {
    enum Engine: Sendable { case muscriptor, basicPitch, pianoOnnx }

    let id: String
    let displayName: String
    let engine: Engine
    let mirrorRepo: String?
    let revision: String?
    let remotePath: String?
    let byteSize: Int64
    let sha256: String?
    let authorsRepo: String?
    let gated: Bool
    let licenseName: String
    let licenseKind: LicenseKind
    let attribution: String
    let licenseTexts: [LicenseText]

    var fileName: String { remotePath.map { ($0 as NSString).lastPathComponent } ?? id }
    /// The sentence embedded in exported MIDI files and shown in the export sheet.
    var exportNotice: String {
        switch engine {
        case .muscriptor: "Transcribed with MuScriptor by Mirelo and Kyutai (CC BY-NC 4.0, non-commercial use only)."
        case .basicPitch: "Transcribed with Basic Pitch by Spotify (Apache-2.0)."
        case .pianoOnnx: "Transcribed with the high-resolution piano transcription model by Kong et al. (CC BY 4.0)."
        }
    }
    var needsDownload: Bool { engine != .basicPitch }
    /// Rough working set: the weights plus the float32 cache, estimated as twice the file size.
    var memoryEstimate: Int64 { byteSize * 2 }

    var downloadURL: URL? {
        guard let mirrorRepo, let revision, let remotePath else { return nil }
        return URL(string: "https://huggingface.co/\(mirrorRepo)/resolve/\(revision)/\(remotePath)")
    }

    var modelPageURL: URL? {
        authorsRepo.flatMap { URL(string: "https://huggingface.co/\($0)") }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (a: ModelEntry, b: ModelEntry) -> Bool { a.id == b.id }
}

enum ModelCatalog {
    static let mirrorRepo = "DamRsn/muscriptor-gguf"
    static let revision = "d7045f94e8b19427f4ff9542975035e66596e51c"

    private static func muscriptor(_ size: String, bytes: Int64, sha: String) -> ModelEntry {
        ModelEntry(
            id: "muscriptor-\(size)", displayName: "MuScriptor \(size.capitalized)", engine: .muscriptor,
            mirrorRepo: mirrorRepo, revision: revision, remotePath: "v1/muscriptor-\(size)-f16.gguf",
            byteSize: bytes, sha256: sha, authorsRepo: "MuScriptor/muscriptor-\(size)", gated: true,
            licenseName: "CC BY-NC 4.0", licenseKind: .nonCommercial,
            attribution: "Mirelo and Kyutai; GGUF conversion by Damien Ronssin",
            licenseTexts: [LicenseText(resource: "CC-BY-NC-4.0", ext: "txt"), LicenseText(resource: "MuScriptorNotice", ext: "md")])
    }

    private static let pianoOnnx = ModelEntry(
        id: "piano-onnx", displayName: "Piano (ONNX)", engine: .pianoOnnx,
        mirrorRepo: "LanOss/mobimml-piano-transcription", revision: "7dff58faf160d4c0bf13be48e30e614faecdba72",
        remotePath: "piano_transcription.onnx", byteSize: 154_214_201,
        sha256: "6ec4f07640837df2fcd2cede9c540865acff341def93fbd6432548dee169195a", authorsRepo: nil, gated: false,
        licenseName: "CC BY 4.0", licenseKind: .attributionRequired,
        attribution: "Piano only. Qiuqiang Kong et al., ONNX conversion by LanOss",
        licenseTexts: [LicenseText(resource: "CC-BY-4.0", ext: "txt"), LicenseText(resource: "PianoOnnxNotice", ext: "md")])

    static let entries: [ModelEntry] = [
        muscriptor("small", bytes: 209_425_152, sha: "925f55af65a20ebc4f8b45ceaf095a12b72493d436cb112623cd0041a1af23d4"),
        muscriptor("medium", bytes: 618_442_496, sha: "3850cc9e5b436b17a09bd25b8f2615cb3366ab96a71e7b50f73a793a917fdf03"),
        muscriptor("large", bytes: 2_739_142_176, sha: "35a750fb1ab1e77195cdc2c0b9b4aeea2f4d59f11f729f02af9920c4854ef72e"),
        ModelEntry(
            id: "basic-pitch", displayName: "Basic Pitch", engine: .basicPitch, mirrorRepo: nil, revision: nil,
            remotePath: nil, byteSize: 0, sha256: nil, authorsRepo: nil, gated: false,
            licenseName: "Apache-2.0", licenseKind: .commercialAllowed, attribution: "Spotify",
            licenseTexts: [LicenseText(resource: "Apache-2.0", ext: "txt"), LicenseText(resource: "BasicPitchNotice", ext: "txt")]),
        pianoOnnx,
    ]
}
