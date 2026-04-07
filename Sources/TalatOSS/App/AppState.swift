import Combine
import Foundation
import SwiftData

@MainActor
final class AppState: ObservableObject {
    // Services
    let audioCaptureService: AudioCaptureService
    let whisperWrapper: WhisperWrapper
    var transcriptionService: TranscriptionService
    let exportService: ExportService
    let ollamaService: OllamaService

    // State
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var currentRecording: Recording?
    @Published var selectedAudioSource: AudioSource = .microphone
    @Published var isModelLoading = false
    @Published var isModelReady = false
    @Published var modelLoadingProgress: String = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String = "Initializing..."

    private var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()

    init() {
        audioCaptureService = AudioCaptureService()
        whisperWrapper = WhisperWrapper()
        transcriptionService = TranscriptionService(whisperWrapper: whisperWrapper)
        exportService = ExportService()
        ollamaService = OllamaService()

        setupBindings()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    private func setupBindings() {
        // Bind audio capture state
        audioCaptureService.$isRecording
            .assign(to: &$isRecording)

        audioCaptureService.$isPaused
            .assign(to: &$isPaused)

        // Bind model state
        whisperWrapper.$isModelLoaded
            .assign(to: &$isModelReady)

        whisperWrapper.$isLoading
            .assign(to: &$isModelLoading)
    }

    func initializeApp() async {
        statusMessage = "Fetching available models..."

        // Fetch available models
        await whisperWrapper.fetchAvailableModels()

        statusMessage = "Loading Whisper model (this may take a moment)..."
        isModelLoading = true

        // Load default model
        do {
            try await whisperWrapper.loadModel(name: "base.en")
            isModelReady = true
            statusMessage = "Model loaded. Ready to record."

            // Update transcription service model ready state
            transcriptionService.isModelReady = true

        } catch {
            errorMessage = "Failed to load Whisper model: \(error.localizedDescription)"
            statusMessage = "Model loading failed: \(error.localizedDescription)"
            print("Model loading error: \(error)")
        }

        isModelLoading = false

        // Check Ollama availability for summaries
        await ollamaService.checkAvailability()
        if ollamaService.isAvailable {
            print("Ollama available with models: \(ollamaService.availableModels.map { $0.name })")
        } else {
            print("Ollama not available - summaries will be disabled")
        }
    }

    func startNewRecording() {
        Task {
            await startRecording()
        }
    }

    func startRecording() async {
        // Check if model is ready
        guard isModelReady else {
            errorMessage = "Whisper model not loaded. Please wait for initialization."
            statusMessage = "Cannot record: Model not loaded"
            return
        }

        guard let context = modelContext else {
            errorMessage = "Model context not available"
            return
        }

        let outputURL = AudioCaptureService.createRecordingURL()

        // Create recording object
        let recording = Recording(
            audioSource: selectedAudioSource,
            status: .recording
        )
        recording.audioFilePath = outputURL.path

        context.insert(recording)
        currentRecording = recording
        statusMessage = "Recording..."

        do {
            // Start audio capture
            try await audioCaptureService.startRecording(
                source: selectedAudioSource,
                outputURL: outputURL
            )

            print("Audio capture started, starting transcription...")
            print("Model ready: \(isModelReady), Transcription service ready: \(transcriptionService.isModelReady)")

            // Ensure transcription service knows model is ready
            transcriptionService.isModelReady = isModelReady

            // Start transcription
            transcriptionService.startTranscription(
                audioPublisher: audioCaptureService.audioBufferPublisher
            )

            print("Transcription started, isTranscribing: \(transcriptionService.isTranscribing)")

        } catch {
            recording.status = .failed
            errorMessage = error.localizedDescription
            statusMessage = "Recording failed: \(error.localizedDescription)"
            currentRecording = nil
            print("Recording error: \(error)")
        }
    }

    func pauseRecording() {
        audioCaptureService.pauseRecording()
        currentRecording?.status = .paused
        statusMessage = "Paused"
    }

    func resumeRecording() {
        audioCaptureService.resumeRecording()
        currentRecording?.status = .recording
        statusMessage = "Recording..."
    }

    func stopRecording() async {
        statusMessage = "Stopping and processing..."

        // Stop transcription first
        await transcriptionService.stopTranscription()

        // Stop audio capture
        let audioURL = await audioCaptureService.stopRecording()

        guard let recording = currentRecording else { return }

        // Update recording
        recording.status = .completed
        recording.duration = audioCaptureService.duration

        // Get file size
        if let url = audioURL {
            recording.audioFilePath = url.path
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int64 {
                recording.fileSize = size
            }
        }

        // Create transcript from transcription service segments
        let transcript = Transcript(
            language: "en",
            modelUsed: whisperWrapper.modelName
        )

        for segment in transcriptionService.currentSegments {
            let transcriptSegment = TranscriptSegment(
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                confidence: segment.confidence
            )
            transcript.addSegment(transcriptSegment)
        }

        recording.transcript = transcript
        recording.updatedAt = Date()

        currentRecording = nil
        statusMessage = "Recording saved."
    }

    func cancelRecording() async {
        await transcriptionService.stopTranscription()
        _ = await audioCaptureService.stopRecording()

        if let recording = currentRecording {
            // Delete the audio file
            if let path = recording.audioFilePath {
                try? FileManager.default.removeItem(atPath: path)
            }

            // Delete the recording from context
            modelContext?.delete(recording)
        }

        currentRecording = nil
        statusMessage = "Recording cancelled."
    }
}
