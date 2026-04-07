import SwiftData
import SwiftUI

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(sort: \Recording.createdAt, order: .reverse)
    private var recordings: [Recording]

    @State private var selectedRecording: Recording?
    @State private var showingSettings = false
    @State private var searchText = ""

    var filteredRecordings: [Recording] {
        if searchText.isEmpty {
            return recordings
        }
        return recordings.filter { recording in
            recording.title.localizedCaseInsensitiveContains(searchText) ||
            (recording.transcript?.fullText.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // New Recording Button
            Button {
                appState.startNewRecording()
            } label: {
                Label("New Recording", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()

            Divider()

            // Recording List
            if filteredRecordings.isEmpty {
                ContentUnavailableView {
                    Label("No Recordings", systemImage: "waveform")
                } description: {
                    Text("Start a new recording to get started.")
                }
            } else {
                List(selection: $selectedRecording) {
                    ForEach(filteredRecordings) { recording in
                        RecordingRowView(recording: recording)
                            .tag(recording)
                            .contextMenu {
                                recordingContextMenu(for: recording)
                            }
                    }
                    .onDelete(perform: deleteRecordings)
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Recordings")
        .searchable(text: $searchText, prompt: "Search recordings")
        .frame(minWidth: 250)
    }

    @ViewBuilder
    private var detailContent: some View {
        if appState.isRecording {
            RecordingView()
        } else if let recording = selectedRecording {
            TranscriptView(recording: recording)
        } else {
            ContentUnavailableView {
                Label("Select a Recording", systemImage: "doc.text")
            } description: {
                Text("Select a recording from the sidebar or start a new one.")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    @ViewBuilder
    private func recordingContextMenu(for recording: Recording) -> some View {
        Button {
            renameRecording(recording)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Divider()

        Menu("Export") {
            ForEach(ExportFormat.allCases) { format in
                Button(format.displayName) {
                    exportRecording(recording, format: format)
                }
            }
        }

        Button {
            copyTranscriptToClipboard(recording)
        } label: {
            Label("Copy Transcript", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            deleteRecording(recording)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = filteredRecordings[index]
            deleteRecording(recording)
        }
    }

    private func deleteRecording(_ recording: Recording) {
        // Delete audio file
        if let audioPath = recording.audioFilePath {
            try? FileManager.default.removeItem(atPath: audioPath)
        }

        if selectedRecording == recording {
            selectedRecording = nil
        }

        modelContext.delete(recording)
    }

    private func renameRecording(_ recording: Recording) {
        // This would typically show a rename dialog
        // For simplicity, we'll leave this as a placeholder
    }

    private func exportRecording(_ recording: Recording, format: ExportFormat) {
        Task {
            _ = await appState.exportService.exportToFile(
                recording: recording,
                format: format
            )
        }
    }

    private func copyTranscriptToClipboard(_ recording: Recording) {
        appState.exportService.copyToClipboard(
            recording: recording,
            format: .plainText,
            options: ExportOptions(includeTimestamps: false, includeSpeakerLabels: true, includeMetadata: false)
        )
    }
}

struct RecordingRowView: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Label(recording.formattedDuration, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                statusBadge
            }

            Text(formatDate(recording.createdAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch recording.status {
        case .recording:
            Label("Recording", systemImage: "record.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        case .paused:
            Label("Paused", systemImage: "pause.circle")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .completed:
            if recording.transcript != nil {
                Label("Transcribed", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else {
                Label("No Transcript", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        case .failed:
            Label("Failed", systemImage: "xmark.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    MainView()
        .environmentObject(AppState())
}
