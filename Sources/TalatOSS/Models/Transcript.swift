import Foundation
import SwiftData

@Model
final class Transcript {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var language: String
    var modelUsed: String

    @Relationship(deleteRule: .cascade)
    var segments: [TranscriptSegment]

    @Relationship(inverse: \Recording.transcript)
    var recording: Recording?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        language: String = "en",
        modelUsed: String = "base.en",
        segments: [TranscriptSegment] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.language = language
        self.modelUsed = modelUsed
        self.segments = segments
    }

    var fullText: String {
        segments
            .sorted { $0.startTime < $1.startTime }
            .map { $0.text }
            .joined(separator: " ")
    }

    var textWithTimestamps: String {
        segments
            .sorted { $0.startTime < $1.startTime }
            .map { "\($0.formattedTimestamp) \($0.text)" }
            .joined(separator: "\n")
    }

    var duration: TimeInterval {
        guard let lastSegment = segments.max(by: { $0.endTime < $1.endTime }) else {
            return 0
        }
        return lastSegment.endTime
    }

    func addSegment(_ segment: TranscriptSegment) {
        segments.append(segment)
        segment.transcript = self
        updatedAt = Date()
    }
}
