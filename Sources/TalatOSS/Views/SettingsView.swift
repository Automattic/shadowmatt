import AVFoundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAudioSource: AudioSource = .microphone
    @State private var selectedModel: String = "base.en"
    @State private var isLoadingModel = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            // Content
            Form {
                audioSettingsSection
                transcriptionSettingsSection
                storageSection
                aboutSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 500, height: 600)
        .onAppear {
            selectedAudioSource = appState.selectedAudioSource
            selectedModel = appState.whisperWrapper.modelName
        }
    }

    @ViewBuilder
    private var audioSettingsSection: some View {
        Section {
            // Audio Source Picker
            Picker("Audio Source", selection: $selectedAudioSource) {
                ForEach(AudioSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .onChange(of: selectedAudioSource) { _, newValue in
                appState.selectedAudioSource = newValue
            }

            // Input Device Picker
            if !appState.audioCaptureService.availableInputDevices.isEmpty {
                let devices = appState.audioCaptureService.availableInputDevices
                Picker("Input Device", selection: Binding(
                    get: { appState.audioCaptureService.selectedInputDevice },
                    set: { appState.audioCaptureService.selectedInputDevice = $0 }
                )) {
                    ForEach(devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device as AVCaptureDevice?)
                    }
                }
            }

            // Refresh Devices Button
            Button("Refresh Devices") {
                appState.audioCaptureService.refreshInputDevices()
            }
        } header: {
            Label("Audio", systemImage: "mic")
        } footer: {
            Text("System audio capture requires Screen Recording permission.")
        }
    }

    @ViewBuilder
    private var transcriptionSettingsSection: some View {
        Section {
            // Model Picker
            Picker("Whisper Model", selection: $selectedModel) {
                ForEach(appState.whisperWrapper.availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            // Model Status
            HStack {
                if appState.whisperWrapper.isModelLoaded {
                    Label("Model Loaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if appState.whisperWrapper.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading model...")
                } else {
                    Label("Model Not Loaded", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(appState.whisperWrapper.isModelLoaded ? "Reload" : "Load") {
                    loadModel()
                }
                .disabled(appState.whisperWrapper.isLoading)
            }

            // Loading Progress
            if appState.whisperWrapper.isLoading {
                ProgressView(value: appState.whisperWrapper.loadingProgress) {
                    Text("Downloading model...")
                }
            }
        } header: {
            Label("Transcription", systemImage: "text.bubble")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smaller models are faster but less accurate.")
                Text("Recommended: base.en for English, small for multilingual.")
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section {
            // Storage Location
            LabeledContent("Storage Location") {
                Text(AudioCaptureService.getApplicationSupportDirectory().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            // Open Storage Folder
            Button("Open Storage Folder") {
                NSWorkspace.shared.open(AudioCaptureService.getApplicationSupportDirectory())
            }

            // Clear All Data (dangerous)
            Button("Clear All Data", role: .destructive) {
                // This would show a confirmation dialog
            }
        } header: {
            Label("Storage", systemImage: "folder")
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text("1.0.0")
            }

            LabeledContent("Powered by") {
                Text("WhisperKit")
            }

            Link("View on GitHub", destination: URL(string: "https://github.com/your-repo/talat-oss")!)
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }

    private func loadModel() {
        Task {
            do {
                try await appState.whisperWrapper.loadModel(name: selectedModel)
                appState.transcriptionService = TranscriptionService(whisperWrapper: appState.whisperWrapper)
                try await appState.transcriptionService.loadModel(name: selectedModel)
            } catch {
                print("Failed to load model: \(error)")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
