import AVFoundation
import Combine
import Foundation

protocol TranscriptionServiceDelegate: AnyObject {
    func transcriptionService(_ service: TranscriptionService, didTranscribe segments: [WhisperSegment])
    func transcriptionService(_ service: TranscriptionService, didFailWith error: Error)
}

@MainActor
final class TranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var currentSegments: [WhisperSegment] = []
    @Published var isModelReady = false
    @Published var bufferStatus: String = ""

    weak var delegate: TranscriptionServiceDelegate?

    private let whisperWrapper: WhisperWrapper
    private var audioBufferAccumulator: [Float] = []
    private var audioSubscription: AnyCancellable?

    private let sampleRate: Double = 16000
    private let minBufferDuration: TimeInterval = 1.5 // Reduced for faster feedback
    private let maxBufferDuration: TimeInterval = 30.0

    private var transcriptionTask: Task<Void, Never>?
    private var accumulatedTime: TimeInterval = 0
    private var buffersReceived: Int = 0

    init(whisperWrapper: WhisperWrapper) {
        self.whisperWrapper = whisperWrapper
    }

    func loadModel(name: String = "base.en") async throws {
        try await whisperWrapper.loadModel(name: name)
        isModelReady = whisperWrapper.isModelLoaded
    }

    func startTranscription(audioPublisher: AnyPublisher<AVAudioPCMBuffer, Never>) {
        print("[Transcription] Starting transcription, model ready: \(isModelReady)")

        guard isModelReady else {
            print("[Transcription] ERROR: Model not ready, cannot start")
            return
        }

        isTranscribing = true
        currentSegments = []
        audioBufferAccumulator = []
        accumulatedTime = 0
        buffersReceived = 0

        audioSubscription = audioPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffer in
                self?.processAudioBuffer(buffer)
            }

        // Start periodic transcription
        startPeriodicTranscription()

        print("[Transcription] Transcription started successfully")
    }

    func stopTranscription() async {
        print("[Transcription] Stopping transcription...")
        audioSubscription?.cancel()
        audioSubscription = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil

        // Transcribe any remaining audio
        if !audioBufferAccumulator.isEmpty {
            print("[Transcription] Transcribing remaining \(audioBufferAccumulator.count) samples...")
            await transcribeAccumulatedAudio()
        }

        isTranscribing = false
        print("[Transcription] Stopped. Total segments: \(currentSegments.count)")
    }

    func transcribeFile(at url: URL) async throws -> [WhisperSegment] {
        guard isModelReady else {
            throw WhisperError.modelNotLoaded
        }

        isTranscribing = true
        defer { isTranscribing = false }

        let segments = try await whisperWrapper.transcribe(audioURL: url)
        currentSegments = segments
        return segments
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            print("[Transcription] No channel data in buffer")
            return
        }

        let frameLength = Int(buffer.frameLength)
        let newSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        audioBufferAccumulator.append(contentsOf: newSamples)
        buffersReceived += 1

        let duration = Double(audioBufferAccumulator.count) / sampleRate
        bufferStatus = String(format: "Buffer: %.1fs (%d samples)", duration, audioBufferAccumulator.count)

        if buffersReceived % 10 == 0 {
            print("[Transcription] Received \(buffersReceived) buffers, accumulated \(audioBufferAccumulator.count) samples (%.1f sec)")
        }
    }

    private func startPeriodicTranscription() {
        transcriptionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(1_500_000_000)) // 1.5 seconds

                guard let self = self else { break }

                let bufferDuration = Double(self.audioBufferAccumulator.count) / self.sampleRate

                print("[Transcription] Periodic check: buffer duration = \(bufferDuration)s, min = \(self.minBufferDuration)s")

                if bufferDuration >= self.minBufferDuration {
                    print("[Transcription] Buffer ready, transcribing...")
                    await self.transcribeAccumulatedAudio()
                }
            }
        }
    }

    private func transcribeAccumulatedAudio() async {
        guard !audioBufferAccumulator.isEmpty else {
            print("[Transcription] Empty buffer, skipping")
            return
        }

        let audioToTranscribe = audioBufferAccumulator
        let startTime = accumulatedTime

        // Calculate duration of audio being transcribed
        let duration = Double(audioToTranscribe.count) / sampleRate
        accumulatedTime += duration

        print("[Transcription] Transcribing \(audioToTranscribe.count) samples (\(duration)s) starting at \(startTime)s")

        // Clear accumulator
        audioBufferAccumulator = []

        // Create PCM buffer from accumulated audio
        guard let buffer = createPCMBuffer(from: audioToTranscribe) else {
            print("[Transcription] Failed to create PCM buffer")
            return
        }

        do {
            var segments = try await whisperWrapper.transcribe(audioBuffer: buffer)

            print("[Transcription] Got \(segments.count) segments from Whisper")

            // Adjust timestamps based on accumulated time
            segments = segments.map { segment in
                WhisperSegment(
                    text: segment.text,
                    startTime: segment.startTime + startTime,
                    endTime: segment.endTime + startTime,
                    confidence: segment.confidence
                )
            }

            // Filter out empty segments
            segments = segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            if !segments.isEmpty {
                print("[Transcription] Adding \(segments.count) non-empty segments")
                for segment in segments {
                    print("[Transcription] Segment: \"\(segment.text)\"")
                }
                currentSegments.append(contentsOf: segments)
                delegate?.transcriptionService(self, didTranscribe: segments)
            } else {
                print("[Transcription] All segments were empty")
            }
        } catch {
            print("[Transcription] Error: \(error)")
            delegate?.transcriptionService(self, didFailWith: error)
        }
    }

    private func createPCMBuffer(from floatArray: [Float]) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(floatArray.count)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(floatArray.count)

        guard let channelData = buffer.floatChannelData else { return nil }

        for (index, sample) in floatArray.enumerated() {
            channelData[0][index] = sample
        }

        return buffer
    }
}
