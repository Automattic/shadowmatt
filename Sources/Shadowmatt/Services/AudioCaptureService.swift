import AVFoundation
import Combine
import Foundation
import ScreenCaptureKit

enum AudioCaptureError: Error, LocalizedError {
    case microphoneAccessDenied
    case screenCaptureAccessDenied
    case engineStartFailed(Error)
    case noInputDevice
    case fileCreationFailed
    case recordingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .microphoneAccessDenied:
            return "Microphone access denied. Please grant permission in System Settings."
        case .screenCaptureAccessDenied:
            return "Screen recording access denied. Please grant permission in System Settings."
        case .engineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .noInputDevice:
            return "No audio input device found."
        case .fileCreationFailed:
            return "Failed to create audio file."
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        }
    }
}

protocol AudioCaptureDelegate: AnyObject {
    func audioCaptureDidReceiveBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime)
    func audioCaptureDidUpdateLevel(_ level: Float)
    func audioCaptureDidFail(with error: AudioCaptureError)
}

@MainActor
final class AudioCaptureService: ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var currentLevel: Float = 0
    @Published var duration: TimeInterval = 0
    @Published var availableInputDevices: [AVCaptureDevice] = []
    @Published var selectedInputDevice: AVCaptureDevice?
    @Published var captureStatus: String = ""

    weak var delegate: AudioCaptureDelegate?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?

    private var recordingStartTime: Date?
    private var pausedDuration: TimeInterval = 0
    private var pauseStartTime: Date?

    private var durationTimer: Timer?
    private var tapInstalled = false
    private var buffersProcessed = 0

    private let audioBufferSize: AVAudioFrameCount = 4096
    private let whisperSampleRate: Double = 16000

    private var audioSource: AudioSource = .microphone

    // Buffer for sending to transcription
    private var audioBufferSubject = PassthroughSubject<AVAudioPCMBuffer, Never>()
    var audioBufferPublisher: AnyPublisher<AVAudioPCMBuffer, Never> {
        audioBufferSubject.eraseToAnyPublisher()
    }

    init() {
        refreshInputDevices()
    }

    func refreshInputDevices() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        availableInputDevices = discoverySession.devices

        if selectedInputDevice == nil {
            selectedInputDevice = AVCaptureDevice.default(for: .audio)
        }
    }

    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func startRecording(
        source: AudioSource,
        outputURL: URL
    ) async throws {
        guard !isRecording else { return }

        print("[Audio] Starting recording with source: \(source)")
        captureStatus = "Requesting permissions..."

        audioSource = source

        // Request microphone permission
        guard await requestMicrophonePermission() else {
            print("[Audio] Microphone permission denied")
            throw AudioCaptureError.microphoneAccessDenied
        }

        print("[Audio] Permission granted, setting up audio engine...")
        captureStatus = "Setting up audio..."

        // Set up audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            print("[Audio] Failed to create audio engine")
            return
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        print("[Audio] Input format: \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels")

        guard inputFormat.sampleRate > 0 else {
            print("[Audio] Invalid sample rate")
            throw AudioCaptureError.noInputDevice
        }

        // Create audio file for recording
        do {
            audioFile = try AVAudioFile(
                forWriting: outputURL,
                settings: inputFormat.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            print("[Audio] Audio file created at: \(outputURL.path)")
        } catch {
            print("[Audio] Failed to create audio file: \(error)")
            throw AudioCaptureError.fileCreationFailed
        }

        // Install tap directly on input node
        buffersProcessed = 0
        tapInstalled = true

        inputNode.installTap(onBus: 0, bufferSize: audioBufferSize, format: inputFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            Task { @MainActor in
                guard !self.isPaused else { return }

                self.buffersProcessed += 1

                // Write to file
                do {
                    try self.audioFile?.write(from: buffer)
                } catch {
                    print("[Audio] Error writing: \(error)")
                }

                // Convert to Whisper format (16kHz mono) and send
                if let converted = self.convertToWhisperFormat(buffer: buffer, inputFormat: inputFormat) {
                    self.audioBufferSubject.send(converted)

                    if self.buffersProcessed % 20 == 0 {
                        print("[Audio] Sent buffer #\(self.buffersProcessed), \(converted.frameLength) frames")
                    }
                }

                // Update level meter
                self.updateAudioLevel(buffer: buffer)
            }
        }

        // Start the engine
        do {
            try engine.start()
            print("[Audio] Engine started successfully")
            captureStatus = "Recording..."
        } catch {
            print("[Audio] Engine start failed: \(error)")
            throw AudioCaptureError.engineStartFailed(error)
        }

        recordingStartTime = Date()
        pausedDuration = 0
        isRecording = true
        isPaused = false

        startDurationTimer()
    }

    private func convertToWhisperFormat(buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        // Target format for Whisper: 16kHz mono Float32
        guard let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: whisperSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            print("[Audio] Failed to create whisper format")
            return nil
        }

        // If already correct format, return as-is
        if inputFormat.sampleRate == whisperSampleRate && inputFormat.channelCount == 1 {
            return buffer
        }

        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: whisperFormat) else {
            print("[Audio] Failed to create converter")
            return nil
        }

        // Calculate output frame count
        let ratio = whisperSampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: outputFrameCount) else {
            print("[Audio] Failed to create output buffer")
            return nil
        }

        var error: NSError?
        var inputBufferConsumed = false

        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputBufferConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputBufferConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            print("[Audio] Conversion error: \(error)")
            return nil
        }

        if status == .error {
            print("[Audio] Conversion failed")
            return nil
        }

        return outputBuffer
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pauseStartTime = Date()
        durationTimer?.invalidate()
        captureStatus = "Paused"
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }

        if let pauseStart = pauseStartTime {
            pausedDuration += Date().timeIntervalSince(pauseStart)
        }

        isPaused = false
        pauseStartTime = nil
        startDurationTimer()
        captureStatus = "Recording..."
    }

    func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        print("[Audio] Stopping recording, processed \(buffersProcessed) buffers")

        durationTimer?.invalidate()
        durationTimer = nil

        // Remove tap
        if tapInstalled {
            audioEngine?.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        audioEngine?.stop()

        let fileURL = audioFile?.url

        audioEngine = nil
        audioFile = nil

        isRecording = false
        isPaused = false
        currentLevel = 0
        captureStatus = "Stopped"

        return fileURL
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += abs(channelData[i])
        }

        let average = sum / Float(frameLength)
        let db = 20 * log10(max(average, 0.0001))
        let normalizedLevel = max(0, min(1, (db + 60) / 60))

        currentLevel = normalizedLevel
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self,
                  let startTime = self.recordingStartTime,
                  !self.isPaused else { return }

            Task { @MainActor in
                self.duration = Date().timeIntervalSince(startTime) - self.pausedDuration
            }
        }
    }

    static func getApplicationSupportDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let talatDir = appSupport.appendingPathComponent("Shadowmatt", isDirectory: true)

        if !FileManager.default.fileExists(atPath: talatDir.path) {
            try? FileManager.default.createDirectory(
                at: talatDir,
                withIntermediateDirectories: true
            )
        }

        return talatDir
    }

    static func createRecordingURL() -> URL {
        let directory = getApplicationSupportDirectory().appendingPathComponent("Recordings", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let filename = "recording_\(UUID().uuidString).m4a"
        return directory.appendingPathComponent(filename)
    }
}
