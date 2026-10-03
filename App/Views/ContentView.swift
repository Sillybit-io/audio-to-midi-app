import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: DocumentModel
    let store: ModelStore
    @Bindable var access: AccessCoordinator
    @State private var showModels = false
    @State private var selectedModel: ModelEntry.ID?
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
        .toolbar { Button("Models") { showModels = true } }
        .sheet(isPresented: $showModels) {
            VStack { ModelPickerView(store: store, selection: $selectedModel); Button("Done") { showModels = false }.padding() }
                .frame(width: 640, height: 360)
        }
        .sheet(item: $access.request) { request in
            LicenseSheet(coordinator: access, request: request).interactiveDismissDisabled()
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
