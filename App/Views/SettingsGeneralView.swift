import AppKit
import SwiftUI

struct SettingsGeneralView: View {
    let workingFolder: WorkingFolderStore
    @Bindable var preferences: AppPreferences


    var body: some View {
        Form {
            Section {
                HStack(spacing: Metric.sp4) {
                    Image(systemName: "folder").foregroundStyle(Token.accentText)
                    VStack(alignment: .leading, spacing: Metric.sp1) {
                        Text(workingFolder.folder?.lastPathComponent ?? "No folder chosen")
                        Text(workingFolder.folder.map { $0.abbreviatedPath + "/" } ?? "Choose where your audio and MIDI files live.")
                            .font(.caption.monospaced()).foregroundStyle(Native.fgSecondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Show in Finder") {
                        if let folder = workingFolder.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                    .disabled(workingFolder.folder == nil)
                    Button("Choose…") { pick(inDefaultLocation: false) }
                }
                LabeledContent("Audio/") { Text("Audio you add or drop on the window").foregroundStyle(Native.fgSecondary) }
                LabeledContent("MIDI/") { Text("Transcriptions and your edits, saved automatically").foregroundStyle(Native.fgSecondary) }
                Picker("When you add audio", selection: $preferences.addAudioMode) {
                    Text("Copy into the Audio folder").tag(AddAudioMode.copy)
                    Text("Leave it where it is").tag(AddAudioMode.reference)
                }
                HStack {
                    Button("Reset to Default…") { pick(inDefaultLocation: true) }
                    Spacer()
                }
                if let message = workingFolder.errorMessage {
                    Text(message).font(.caption).foregroundStyle(Token.warn)
                }
            } header: {
                Text("Working Folder")
            } footer: {
                Text("The app keeps access to this folder with a security-scoped bookmark, so it keeps working inside the macOS sandbox. Changing the folder doesn\u{2019}t move the files already in the old one.")
            }
            Section("Appearance") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            Section("Transcription") {
                Picker("Default model", selection: $preferences.defaultModelID) {
                    ForEach(ModelCatalog.entries) { Text($0.displayName).tag($0.id) }
                }
            }
            Section("Playback and files") {
                LabeledContent("Sound", value: "General MIDI")
                Toggle("Scroll piano roll to follow playhead", isOn: $preferences.followPlayhead)
                LabeledContent("MIDI file", value: "Type 1 · 120 BPM · 4/4")
            }
        }
        .formStyle(.grouped)
    }

    private func directory(inDefaultLocation: Bool) -> URL {
        if !inDefaultLocation, let folder = workingFolder.folder { return folder.deletingLastPathComponent() }
        return WorkingFolderStore.suggestedFolder.deletingLastPathComponent()
    }

    private func pick(inDefaultLocation: Bool) {
        workingFolder.choose(using: SystemFolderPanel(), startingIn: directory(inDefaultLocation: inDefaultLocation))
    }
}
