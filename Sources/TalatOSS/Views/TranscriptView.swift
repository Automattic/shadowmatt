import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject private var appState: AppState
    @Bindable var recording: Recording

    @State private var isEditing = false
    @State private var editedTitle: String = ""
    @State private var showingExportMenu = false
    @State private var selectedExportFormat: ExportFormat = .markdown
    @State private var exportOptions = ExportOptions()
    @State private var selectedTab: ContentTab = .transcript

    // Summary state
    @State private var summaryText: String = ""
    @State private var actionItems: [String] = []
    @State private var summaryError: String?

    enum ContentTab {
        case transcript
        case summary
    }

    var body: some View {
        TranscriptContentView(
            appState: appState,
            recording: recording,
            isEditing: $isEditing,
            editedTitle: $editedTitle,
            exportOptions: $exportOptions,
            selectedTab: $selectedTab,
            summaryText: $summaryText,
            actionItems: $actionItems,
            summaryError: $summaryError
        )
    }
}

struct TranscriptContentView: View {
    let appState: AppState
    @Bindable var recording: Recording
    @Binding var isEditing: Bool
    @Binding var editedTitle: String
    @Binding var exportOptions: ExportOptions
    @Binding var selectedTab: TranscriptView.ContentTab
    @Binding var summaryText: String
    @Binding var actionItems: [String]
    @Binding var summaryError: String?

    @ObservedObject var ollamaService: OllamaService

    init(
        appState: AppState,
        recording: Recording,
        isEditing: Binding<Bool>,
        editedTitle: Binding<String>,
        exportOptions: Binding<ExportOptions>,
        selectedTab: Binding<TranscriptView.ContentTab>,
        summaryText: Binding<String>,
        actionItems: Binding<[String]>,
        summaryError: Binding<String?>
    ) {
        self.appState = appState
        self._recording = Bindable(wrappedValue: recording)
        self._isEditing = isEditing
        self._editedTitle = editedTitle
        self._exportOptions = exportOptions
        self._selectedTab = selectedTab
        self._summaryText = summaryText
        self._actionItems = actionItems
        self._summaryError = summaryError
        self._ollamaService = ObservedObject(wrappedValue: appState.ollamaService)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Tab bar
            tabBar

            // Content
            if let transcript = recording.transcript {
                if selectedTab == .transcript {
                    transcriptContentView(transcript: transcript)
                } else {
                    summaryView(transcript: transcript)
                }
            } else {
                noTranscriptView
            }
        }
        .toolbar {
            toolbarContent
        }
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("Title", text: $editedTitle, onCommit: {
                    recording.title = editedTitle
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.title)
                .fontWeight(.bold)
            } else {
                Text(recording.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .onTapGesture(count: 2) {
                        editedTitle = recording.title
                        isEditing = true
                    }
            }

            HStack(spacing: 16) {
                Label(recording.formattedDuration, systemImage: "clock")
                Label(formatDate(recording.createdAt), systemImage: "calendar")
                Label(recording.audioSource.displayName, systemImage: "mic")

                if recording.transcript != nil {
                    Label("\(recording.transcript!.segments.count) segments", systemImage: "text.alignleft")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            // Transcript tab
            Button {
                selectedTab = .transcript
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                    Text("Transcript")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedTab == .transcript ? Color.accentColor.opacity(0.1) : Color.clear)
                .foregroundStyle(selectedTab == .transcript ? .primary : .secondary)
            }
            .buttonStyle(.plain)

            // Summary tab
            Button {
                selectedTab = .summary
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Summary")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(selectedTab == .summary ? Color.accentColor.opacity(0.1) : Color.clear)
                .foregroundStyle(selectedTab == .summary ? .primary : .secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // Search and copy buttons
            HStack(spacing: 8) {
                Button {
                    // Search
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    // Copy
                    copyTranscriptToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.trailing, 16)
        }
        .padding(.leading, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func transcriptContentView(transcript: Transcript) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                let sortedSegments = transcript.segments.sorted { $0.startTime < $1.startTime }

                ForEach(sortedSegments, id: \.id) { segment in
                    TranscriptSegmentRow(segment: segment)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func summaryView(transcript: Transcript) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !ollamaService.isAvailable {
                    ollamaNotAvailableView
                } else if transcript.segments.isEmpty {
                    emptyTranscriptView
                } else if summaryText.isEmpty && !ollamaService.isGenerating {
                    generateSummaryView(transcript: transcript)
                } else if ollamaService.isGenerating {
                    generatingSummaryView
                } else {
                    summaryContentView(transcript: transcript)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
    }

    @ViewBuilder
    private var ollamaNotAvailableView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Ollama Not Available")
                .font(.title2)
                .fontWeight(.semibold)

            Text("To generate AI summaries, please install and start Ollama.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                Text("Setup instructions:")
                    .font(.headline)

                Text("1. Install Ollama from ollama.com")
                Text("2. Run: ollama pull llama3.2")
                Text("3. Make sure Ollama is running")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Check Again") {
                Task {
                    await ollamaService.checkAvailability()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var emptyTranscriptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Empty Transcript")
                .font(.title2)
                .fontWeight(.semibold)

            Text("This recording has no transcript content to summarize.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func generateSummaryView(transcript: Transcript) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Generate AI Summary")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Use \(ollamaService.selectedModel) to create a summary of this recording.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Model picker
            if ollamaService.availableModels.count > 1 {
                Picker("Model", selection: Binding(
                    get: { ollamaService.selectedModel },
                    set: { ollamaService.selectedModel = $0 }
                )) {
                    ForEach(ollamaService.availableModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
            }

            Button {
                generateSummary(transcript: transcript)
            } label: {
                Label("Generate Summary", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let error = summaryError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var generatingSummaryView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Generating Summary...")
                .font(.title3)
                .fontWeight(.medium)

            Text("This may take a moment depending on the transcript length.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func summaryContentView(transcript: Transcript) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary header
            HStack {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    generateSummary(transcript: transcript)
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summaryText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Summary content
            Text(summaryText)
                .font(.body)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Action items
            if !actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Action Items", systemImage: "checklist")
                        .font(.title3)
                        .fontWeight(.semibold)

                    ForEach(actionItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item)
                                .font(.body)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var noTranscriptView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("No Transcript", systemImage: "text.badge.xmark")
            } description: {
                Text("This recording doesn't have a transcript yet.")
            } actions: {
                Button("Transcribe Now") {
                    Task {
                        await transcribeRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appState.transcriptionService.isTranscribing || !appState.whisperWrapper.isModelLoaded)
            }

            if !appState.whisperWrapper.isModelLoaded {
                Text("Whisper model not loaded. Please check settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.transcriptionService.isTranscribing {
                ProgressView("Transcribing...")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Copy Button
            Button {
                appState.exportService.copyToClipboard(
                    recording: recording,
                    format: .plainText,
                    options: ExportOptions(includeTimestamps: false, includeSpeakerLabels: true, includeMetadata: false)
                )
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(recording.transcript == nil)

            // Export Menu
            Menu {
                ForEach(ExportFormat.allCases) { format in
                    Button(format.displayName) {
                        Task {
                            _ = await appState.exportService.exportToFile(
                                recording: recording,
                                format: format,
                                options: exportOptions
                            )
                        }
                    }
                }

                Divider()

                Toggle("Include Timestamps", isOn: $exportOptions.includeTimestamps)
                Toggle("Include Metadata", isOn: $exportOptions.includeMetadata)
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(recording.transcript == nil)

            // Re-transcribe Button
            Button {
                Task {
                    await transcribeRecording()
                }
            } label: {
                Label("Re-transcribe", systemImage: "arrow.clockwise")
            }
            .disabled(appState.transcriptionService.isTranscribing || !appState.whisperWrapper.isModelLoaded)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyTranscriptToClipboard() {
        guard let transcript = recording.transcript else { return }
        let text = transcript.segments
            .sorted { $0.startTime < $1.startTime }
            .map { $0.text }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func generateSummary(transcript: Transcript) {
        let transcriptText = transcript.segments
            .sorted { $0.startTime < $1.startTime }
            .map { $0.text }
            .joined(separator: " ")

        summaryError = nil

        Task {
            do {
                summaryText = try await ollamaService.generateSummary(
                    transcript: transcriptText,
                    meetingTitle: recording.title
                )
                actionItems = try await ollamaService.generateActionItems(transcript: transcriptText)
            } catch {
                summaryError = error.localizedDescription
            }
        }
    }

    private func transcribeRecording() async {
        guard let audioURL = recording.audioFileURL else { return }

        do {
            let segments = try await appState.transcriptionService.transcribeFile(at: audioURL)

            // Create or update transcript
            let transcript = recording.transcript ?? Transcript()

            // Clear existing segments
            transcript.segments.removeAll()

            // Add new segments
            for segment in segments {
                let transcriptSegment = TranscriptSegment(
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    confidence: segment.confidence
                )
                transcript.addSegment(transcriptSegment)
            }

            transcript.modelUsed = appState.whisperWrapper.modelName
            recording.transcript = transcript

        } catch {
            print("Transcription failed: \(error)")
        }
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(segment.formattedTimestamp)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            // Speaker label (if available)
            if let speaker = segment.speakerLabel {
                Text(speaker)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                    .frame(width: 80, alignment: .leading)
            }

            // Text
            Text(segment.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.gray.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    let recording = Recording(
        title: "Test Recording",
        duration: 125,
        audioSource: .microphone,
        status: .completed
    )

    return TranscriptView(recording: recording)
        .environmentObject(AppState())
}
