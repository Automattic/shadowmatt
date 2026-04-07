import SwiftUI

struct RecordingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: TranscriptTab = .transcript
    @State private var showPeoplePanel = true
    @State private var notesText = ""

    // Observe nested objects directly for live updates
    @ObservedObject private var transcriptionService: TranscriptionService
    @ObservedObject private var audioCaptureService: AudioCaptureService

    init() {
        // These will be replaced by the actual instances in body
        // We need a workaround since we can't access @EnvironmentObject in init
        _transcriptionService = ObservedObject(wrappedValue: TranscriptionService(whisperWrapper: WhisperWrapper()))
        _audioCaptureService = ObservedObject(wrappedValue: AudioCaptureService())
    }

    enum TranscriptTab {
        case transcript
        case summary
    }

    var body: some View {
        // Use the actual services from appState
        RecordingContentView(
            appState: appState,
            selectedTab: $selectedTab,
            showPeoplePanel: $showPeoplePanel,
            notesText: $notesText
        )
    }
}

// Separate view that can properly observe the services
struct RecordingContentView: View {
    let appState: AppState
    @Binding var selectedTab: RecordingView.TranscriptTab
    @Binding var showPeoplePanel: Bool
    @Binding var notesText: String

    // Direct observation of nested ObservableObjects
    @ObservedObject var transcriptionService: TranscriptionService
    @ObservedObject var audioCaptureService: AudioCaptureService
    @ObservedObject var ollamaService: OllamaService

    // Summary state
    @State private var summaryText: String = ""
    @State private var actionItems: [String] = []
    @State private var summaryError: String?

    init(
        appState: AppState,
        selectedTab: Binding<RecordingView.TranscriptTab>,
        showPeoplePanel: Binding<Bool>,
        notesText: Binding<String>
    ) {
        self.appState = appState
        self._selectedTab = selectedTab
        self._showPeoplePanel = showPeoplePanel
        self._notesText = notesText
        self._transcriptionService = ObservedObject(wrappedValue: appState.transcriptionService)
        self._audioCaptureService = ObservedObject(wrappedValue: appState.audioCaptureService)
        self._ollamaService = ObservedObject(wrappedValue: appState.ollamaService)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            recordingHeader

            Divider()

            // Main content area
            HStack(spacing: 0) {
                // Left: Transcript/Summary area
                VStack(spacing: 0) {
                    // Tab bar
                    tabBar

                    // Content
                    if selectedTab == .transcript {
                        liveTranscriptView
                    } else {
                        summaryView
                    }

                    // Playback bar
                    playbackBar
                }

                // Right sidebar
                if showPeoplePanel {
                    Divider()
                    rightSidebar
                        .frame(width: 280)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    @ViewBuilder
    private var recordingHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.currentRecording?.title ?? "New Recording")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text(formatDate(Date()))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    Label(formatDuration(audioCaptureService.duration), systemImage: "clock")
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    // Recording indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(audioCaptureService.isPaused ? Color.orange : Color.red)
                            .frame(width: 8, height: 8)
                            .opacity(audioCaptureService.isPaused ? 1 : 1)
                            .animation(
                                audioCaptureService.isRecording && !audioCaptureService.isPaused
                                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                                    : .default,
                                value: audioCaptureService.isRecording
                            )
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    // Download/export action
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    // Delete action
                } label: {
                    Image(systemName: "trash")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Tab Bar

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
                    Image(systemName: "doc.text")
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

    // MARK: - Live Transcript View

    @ViewBuilder
    private var liveTranscriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(transcriptionService.currentSegments.enumerated()), id: \.offset) { index, segment in
                        TranscriptBubbleView(
                            segment: segment,
                            isSystemAudio: index % 2 == 0,
                            audioSource: appState.selectedAudioSource
                        )
                        .id(index)
                    }

                    if transcriptionService.currentSegments.isEmpty && audioCaptureService.isRecording {
                        VStack(spacing: 12) {
                            if appState.isModelLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading Whisper model...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else if !appState.isModelReady {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundStyle(.orange)
                                Text("Model not loaded")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(appState.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Listening...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                // Buffer status
                                Text(transcriptionService.bufferStatus)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.tertiary)

                                Text("Speak clearly into your microphone")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding()
            }
            .onChange(of: transcriptionService.currentSegments.count) { _, newCount in
                if newCount > 0 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
    }

    // MARK: - Summary View

    @ViewBuilder
    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Ollama status and controls
                if !ollamaService.isAvailable {
                    ollamaNotAvailableView
                } else if transcriptionService.currentSegments.isEmpty {
                    noTranscriptView
                } else if summaryText.isEmpty && !ollamaService.isGenerating {
                    generateSummaryView
                } else if ollamaService.isGenerating {
                    generatingSummaryView
                } else {
                    summaryContentView
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
    private var noTranscriptView: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Transcript Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start speaking to generate a transcript, then you can create a summary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private var generateSummaryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple)

            Text("Generate AI Summary")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Use \(ollamaService.selectedModel) to create a summary of the conversation so far.")
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
                generateSummary()
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
    private var summaryContentView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary header
            HStack {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button {
                    generateSummary()
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

    private func generateSummary() {
        let transcript = transcriptionService.currentSegments
            .map { $0.text }
            .joined(separator: " ")

        let title = appState.currentRecording?.title ?? "Meeting"

        summaryError = nil

        Task {
            do {
                summaryText = try await ollamaService.generateSummary(
                    transcript: transcript,
                    meetingTitle: title
                )
                actionItems = try await ollamaService.generateActionItems(transcript: transcript)
            } catch {
                summaryError = error.localizedDescription
            }
        }
    }

    // MARK: - Playback Bar

    @ViewBuilder
    private var playbackBar: some View {
        HStack(spacing: 16) {
            // Play/Pause button
            Button {
                if audioCaptureService.isPaused {
                    appState.resumeRecording()
                } else {
                    appState.pauseRecording()
                }
            } label: {
                Image(systemName: audioCaptureService.isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            // Current time
            Text(formatDuration(audioCaptureService.duration))
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)

            // Progress bar / waveform placeholder
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)

                    // Audio level indicator
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * CGFloat(audioCaptureService.currentLevel), height: 4)
                        .animation(.easeOut(duration: 0.1), value: audioCaptureService.currentLevel)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)

            // Duration
            Text(formatDuration(audioCaptureService.duration))
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)

            // Stop button
            Button {
                Task {
                    await appState.stopRecording()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Right Sidebar

    @ViewBuilder
    private var rightSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button {
                    withAnimation {
                        showPeoplePanel = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // People section
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    // You (the user)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)

                        Text("You")
                            .fontWeight(.medium)

                        Spacer()

                        Text("\(formatDuration(audioCaptureService.duration)) • \(Int(audioCaptureService.currentLevel * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Add someone button
                    Button {
                        // Add participant
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                            Text("Add someone...")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("People")
                        .font(.headline)
                    Text("(1)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "person.2")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Notes section
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Capture your thoughts, additional context, or anything else the transcript might miss.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("You can attach a note to any specific part of the transcript using the reply icon on each bubble.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $notesText)
                        .font(.body)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.top, 8)
            } label: {
                Text("Notes")
                    .font(.headline)
            }
            .padding()

            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy • h:mm a"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func copyTranscriptToClipboard() {
        let text = transcriptionService.currentSegments
            .map { $0.text }
            .joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Transcript Bubble View

struct TranscriptBubbleView: View {
    let segment: WhisperSegment
    let isSystemAudio: Bool
    let audioSource: AudioSource

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSystemAudio {
                systemAudioBubble
                Spacer(minLength: 100)
            } else {
                Spacer(minLength: 100)
                userBubble
            }
        }
    }

    @ViewBuilder
    private var systemAudioBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("SYSTEM AUDIO")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(formatTime(segment.startTime))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                if isHovered {
                    actionButtons
                }
            }

            // Bubble
            Text(segment.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.darkGray))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Header
            HStack(spacing: 8) {
                if isHovered {
                    actionButtons
                }

                Spacer()

                Image(systemName: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)

                Text("YOU")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Text(formatTime(segment.startTime))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Bubble
            Text(segment.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.pink.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 4) {
            Button {
                // Bookmark
            } label: {
                Image(systemName: "bookmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                // Play
            } label: {
                Image(systemName: "play")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                // Reply/Note
            } label: {
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button {
                // Star
            } label: {
                Image(systemName: "star")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(AppState())
        .frame(width: 1000, height: 700)
}
