import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: DocumentModel
    private let engineProblem: String? = {
        do {
            _ = try EngineLocator.locate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let engineProblem {
                Text(engineProblem).foregroundStyle(.red).padding(8)
            }
            if model.document == nil {
                DropZoneView(model: model)
            } else {
                WaveformSliceView(model: model)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else { return false }
                        model.open(url)
                        return true
                    }
                Spacer()
            }
        }
        .fileImporter(isPresented: $model.isImporting, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): model.open(url)
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        .alert("Could not open audio", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
