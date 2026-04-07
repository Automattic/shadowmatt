import AVFoundation
import Foundation
import WhisperKit

enum WhisperError: Error, LocalizedError {
    case modelNotLoaded
    case transcriptionFailed(Error)
    case invalidAudioFormat
    case modelDownloadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Whisper model is not loaded."
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .invalidAudioFormat:
            return "Invalid audio format. Expected 16kHz mono Float32."
        case .modelDownloadFailed(let error):
            return "Failed to download model: \(error.localizedDescription)"
        }
    }
}

struct WhisperSegment {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Double
}

@MainActor
final class WhisperWrapper: ObservableObject {
    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var modelName: String = "base.en"
    @Published var availableModels: [String] = []

    private var whisperKit: WhisperKit?
    private let modelDirectory: URL

    init() {
        modelDirectory = AudioCaptureService.getApplicationSupportDirectory()
            .appendingPathComponent("Models", isDirectory: true)

        if !FileManager.default.fileExists(atPath: modelDirectory.path) {
            try? FileManager.default.createDirectory(
                at: modelDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    func loadModel(name: String = "base.en") async throws {
        guard !isLoading else { return }

        isLoading = true
        loadingProgress = 0
        modelName = name

        do {
            // WhisperKit will download the model if not present
            whisperKit = try await WhisperKit(
                model: name,
                downloadBase: modelDirectory,
                verbose: false,
                prewarm: true
            )

            isModelLoaded = true
            loadingProgress = 1.0
        } catch {
            isModelLoaded = false
            isLoading = false
            throw WhisperError.modelDownloadFailed(error)
        }

        isLoading = false
    }

    func unloadModel() {
        whisperKit = nil
        isModelLoaded = false
    }

    func transcribe(audioBuffer: AVAudioPCMBuffer) async throws -> [WhisperSegment] {
        guard let whisper = whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        // Convert buffer to float array
        let audioArray = bufferToFloatArray(buffer: audioBuffer)

        do {
            let results = try await whisper.transcribe(audioArray: audioArray)

            return results.flatMap { result in
                result.segments.map { segment in
                    WhisperSegment(
                        text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: TimeInterval(segment.start),
                        endTime: TimeInterval(segment.end),
                        confidence: Double(segment.avgLogprob)
                    )
                }
            }
        } catch {
            throw WhisperError.transcriptionFailed(error)
        }
    }

    func transcribe(audioURL: URL) async throws -> [WhisperSegment] {
        guard let whisper = whisperKit else {
            throw WhisperError.modelNotLoaded
        }

        do {
            let results = try await whisper.transcribe(audioPath: audioURL.path)

            return results.flatMap { result in
                result.segments.map { segment in
                    WhisperSegment(
                        text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                        startTime: TimeInterval(segment.start),
                        endTime: TimeInterval(segment.end),
                        confidence: Double(segment.avgLogprob)
                    )
                }
            }
        } catch {
            throw WhisperError.transcriptionFailed(error)
        }
    }

    private func bufferToFloatArray(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return []
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            // Mix down to mono
            var monoArray = [Float](repeating: 0, count: frameLength)
            for i in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][i]
                }
                monoArray[i] = sum / Float(channelCount)
            }
            return monoArray
        }
    }

    func fetchAvailableModels() async {
        // Common WhisperKit models
        availableModels = [
            "tiny.en",
            "tiny",
            "base.en",
            "base",
            "small.en",
            "small",
            "medium.en",
            "medium",
            "large-v2",
            "large-v3"
        ]
    }
}
