import Foundation

enum OllamaError: Error, LocalizedError {
    case notRunning
    case requestFailed(Error)
    case invalidResponse
    case noModelsAvailable

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Ollama is not running. Please start Ollama and try again."
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Ollama."
        case .noModelsAvailable:
            return "No models available. Please pull a model first (e.g., 'ollama pull llama3.2')."
        }
    }
}

struct OllamaModel: Codable, Identifiable {
    let name: String
    let size: Int64?
    let digest: String?

    var id: String { name }

    var displayName: String {
        name.components(separatedBy: ":").first ?? name
    }

    var formattedSize: String {
        guard let size = size else { return "" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaGenerateRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
}

struct OllamaGenerateResponse: Codable {
    let model: String
    let response: String
    let done: Bool
}

@MainActor
final class OllamaService: ObservableObject {
    @Published var isAvailable = false
    @Published var isGenerating = false
    @Published var availableModels: [OllamaModel] = []
    @Published var selectedModel: String = "llama3.2"
    @Published var lastError: String?

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = URL(string: baseURL)!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // LLMs can be slow
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func checkAvailability() async {
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                isAvailable = false
                return
            }

            let modelsResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
            availableModels = modelsResponse.models
            isAvailable = true

            // Select first available model if current selection isn't available
            if !availableModels.contains(where: { $0.name == selectedModel || $0.name.hasPrefix(selectedModel) }) {
                if let firstModel = availableModels.first {
                    selectedModel = firstModel.name
                }
            }

        } catch {
            isAvailable = false
            availableModels = []
        }
    }

    func generateSummary(transcript: String, meetingTitle: String) async throws -> String {
        guard isAvailable else {
            throw OllamaError.notRunning
        }

        guard !availableModels.isEmpty else {
            throw OllamaError.noModelsAvailable
        }

        isGenerating = true
        lastError = nil

        defer { isGenerating = false }

        let prompt = """
        You are a helpful assistant that summarizes meeting transcripts. Please provide a concise summary of the following meeting transcript.

        Meeting: \(meetingTitle)

        Include:
        1. **Key Points** - Main topics discussed
        2. **Decisions Made** - Any decisions or conclusions reached
        3. **Action Items** - Tasks or follow-ups mentioned
        4. **Participants** - Who spoke (if identifiable)

        Keep the summary clear and actionable.

        ---
        TRANSCRIPT:
        \(transcript)
        ---

        SUMMARY:
        """

        let request = OllamaGenerateRequest(
            model: selectedModel,
            prompt: prompt,
            stream: false
        )

        let url = baseURL.appendingPathComponent("api/generate")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        do {
            let (data, response) = try await session.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw OllamaError.invalidResponse
            }

            let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            return generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)

        } catch let error as OllamaError {
            lastError = error.localizedDescription
            throw error
        } catch {
            lastError = error.localizedDescription
            throw OllamaError.requestFailed(error)
        }
    }

    func generateActionItems(transcript: String) async throws -> [String] {
        guard isAvailable else {
            throw OllamaError.notRunning
        }

        isGenerating = true
        defer { isGenerating = false }

        let prompt = """
        Extract action items from this meeting transcript. List each action item on a new line, starting with "- ".
        Only include clear, actionable tasks. If there are no action items, respond with "No action items identified."

        TRANSCRIPT:
        \(transcript)

        ACTION ITEMS:
        """

        let request = OllamaGenerateRequest(
            model: selectedModel,
            prompt: prompt,
            stream: false
        )

        let url = baseURL.appendingPathComponent("api/generate")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, _) = try await session.data(for: urlRequest)
        let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)

        let response = generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)

        if response.lowercased().contains("no action items") {
            return []
        }

        return response
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") || $0.hasPrefix("•") || $0.hasPrefix("*") }
            .map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
