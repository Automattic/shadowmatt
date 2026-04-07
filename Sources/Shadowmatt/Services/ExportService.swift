import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case plainText = "txt"
    case markdown = "md"
    case json = "json"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .plainText: return "Plain Text (.txt)"
        case .markdown: return "Markdown (.md)"
        case .json: return "JSON (.json)"
        }
    }

    var fileExtension: String { rawValue }

    var utType: UTType {
        switch self {
        case .plainText: return .plainText
        case .markdown: return .init(filenameExtension: "md") ?? .plainText
        case .json: return .json
        }
    }
}

struct ExportOptions {
    var includeTimestamps: Bool = true
    var includeSpeakerLabels: Bool = true
    var includeMetadata: Bool = true
}

@MainActor
final class ExportService: ObservableObject {
    @Published var isExporting = false
    @Published var lastExportURL: URL?
    @Published var lastError: Error?

    func export(
        recording: Recording,
        format: ExportFormat,
        options: ExportOptions = ExportOptions()
    ) -> String {
        guard let transcript = recording.transcript else {
            return ""
        }

        switch format {
        case .plainText:
            return exportPlainText(recording: recording, transcript: transcript, options: options)
        case .markdown:
            return exportMarkdown(recording: recording, transcript: transcript, options: options)
        case .json:
            return exportJSON(recording: recording, transcript: transcript, options: options)
        }
    }

    func exportToFile(
        recording: Recording,
        format: ExportFormat,
        options: ExportOptions = ExportOptions()
    ) async -> URL? {
        isExporting = true
        defer { isExporting = false }

        let content = export(recording: recording, format: format, options: options)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.utType]
        savePanel.nameFieldStringValue = "\(recording.title).\(format.fileExtension)"
        savePanel.canCreateDirectories = true

        let response = await savePanel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())

        guard response == .OK, let url = savePanel.url else {
            return nil
        }

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            lastExportURL = url
            return url
        } catch {
            lastError = error
            return nil
        }
    }

    func copyToClipboard(recording: Recording, format: ExportFormat, options: ExportOptions = ExportOptions()) {
        let content = export(recording: recording, format: format, options: options)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
    }

    // MARK: - Export Formatters

    private func exportPlainText(
        recording: Recording,
        transcript: Transcript,
        options: ExportOptions
    ) -> String {
        var output = ""

        if options.includeMetadata {
            output += "Title: \(recording.title)\n"
            output += "Date: \(formatDate(recording.createdAt))\n"
            output += "Duration: \(recording.formattedDuration)\n"
            output += "\n---\n\n"
        }

        let sortedSegments = transcript.segments.sorted { $0.startTime < $1.startTime }

        for segment in sortedSegments {
            var line = ""

            if options.includeTimestamps {
                line += "\(segment.formattedTimestamp) "
            }

            if options.includeSpeakerLabels, let speaker = segment.speakerLabel {
                line += "[\(speaker)] "
            }

            line += segment.text
            output += line + "\n"
        }

        return output
    }

    private func exportMarkdown(
        recording: Recording,
        transcript: Transcript,
        options: ExportOptions
    ) -> String {
        var output = ""

        if options.includeMetadata {
            output += "# \(recording.title)\n\n"
            output += "**Date:** \(formatDate(recording.createdAt))  \n"
            output += "**Duration:** \(recording.formattedDuration)  \n"
            output += "**Audio Source:** \(recording.audioSource.displayName)  \n"
            output += "\n---\n\n"
            output += "## Transcript\n\n"
        }

        let sortedSegments = transcript.segments.sorted { $0.startTime < $1.startTime }

        for segment in sortedSegments {
            var line = ""

            if options.includeTimestamps {
                line += "`\(segment.formattedTimestamp)` "
            }

            if options.includeSpeakerLabels, let speaker = segment.speakerLabel {
                line += "**\(speaker):** "
            }

            line += segment.text
            output += line + "\n\n"
        }

        return output
    }

    private func exportJSON(
        recording: Recording,
        transcript: Transcript,
        options: ExportOptions
    ) -> String {
        var dict: [String: Any] = [:]

        if options.includeMetadata {
            dict["metadata"] = [
                "title": recording.title,
                "date": ISO8601DateFormatter().string(from: recording.createdAt),
                "duration": recording.duration,
                "audioSource": recording.audioSource.rawValue,
                "language": transcript.language,
                "model": transcript.modelUsed
            ]
        }

        let sortedSegments = transcript.segments.sorted { $0.startTime < $1.startTime }

        dict["segments"] = sortedSegments.map { segment -> [String: Any] in
            var segmentDict: [String: Any] = [
                "text": segment.text,
                "confidence": segment.confidence
            ]

            if options.includeTimestamps {
                segmentDict["start"] = segment.startTime
                segmentDict["end"] = segment.endTime
            }

            if options.includeSpeakerLabels, let speaker = segment.speakerLabel {
                segmentDict["speaker"] = speaker
            }

            return segmentDict
        }

        dict["fullText"] = transcript.fullText

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
