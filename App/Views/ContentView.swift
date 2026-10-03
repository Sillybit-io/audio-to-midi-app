import SwiftUI

struct ContentView: View {
    private let engineProblem: String? = {
        do {
            _ = try EngineLocator.locate()
            return nil
        } catch {
            return error.localizedDescription
        }
    }()

    var body: some View {
        VStack(spacing: 12) {
            Text("Silly MIDI Tools")
                .font(.largeTitle.bold())
            if let engineProblem {
                Text(engineProblem)
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
