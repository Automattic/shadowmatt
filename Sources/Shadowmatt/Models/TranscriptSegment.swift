import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    var id: UUID
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var confidence: Double
    var speakerLabel: String?
    var createdAt: Date

    @Relationship(inverse: \Transcript.segments)
    var transcript: Transcript?

    init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double = 1.0,
        speakerLabel: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
        self.speakerLabel = speakerLabel
        self.createdAt = createdAt
    }

    var formattedTimestamp: String {
        let startFormatted = formatTime(startTime)
        let endFormatted = formatTime(endTime)
        return "[\(startFormatted) - \(endFormatted)]"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        } else {
            return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
        }
    }
}
