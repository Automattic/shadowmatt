import Foundation
import SwiftData

enum RecordingStatus: String, Codable {
    case recording
    case paused
    case completed
    case failed
}

enum AudioSource: String, Codable, CaseIterable {
    case microphone
    case systemAudio
    case both

    var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .systemAudio: return "System Audio"
        case .both: return "Microphone + System Audio"
        }
    }
}

@Model
final class Recording {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var audioFilePath: String?
    var audioSource: AudioSource
    var status: RecordingStatus
    var fileSize: Int64

    @Relationship(deleteRule: .cascade)
    var transcript: Transcript?

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFilePath: String? = nil,
        audioSource: AudioSource = .microphone,
        status: RecordingStatus = .recording,
        fileSize: Int64 = 0,
        transcript: Transcript? = nil
    ) {
        self.id = id
        self.title = title.isEmpty ? Self.generateDefaultTitle(date: createdAt) : title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.duration = duration
        self.audioFilePath = audioFilePath
        self.audioSource = audioSource
        self.status = status
        self.fileSize = fileSize
        self.transcript = transcript
    }

    static func generateDefaultTitle(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Recording \(formatter.string(from: date))"
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var audioFileURL: URL? {
        guard let path = audioFilePath else { return nil }
        return URL(fileURLWithPath: path)
    }
}
