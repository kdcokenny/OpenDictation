import Foundation
import os.log

/// Errors that can occur during transcription.
enum TranscriptionError: Error, LocalizedError {
    case apiKeyMissing
    case invalidURL
    case invalidConfiguration(String)
    case audioFileNotFound
    case audioFileEmpty
    case networkError(Error)
    case transcriptionTimedOut
    case apiRequestFailed(statusCode: Int, message: String)
    case noTranscriptionReturned
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "No API key. Add one in Settings."
        case .invalidConfiguration(let message):
            return message
        case .invalidURL:
            return "The server address isn't valid."
        case .audioFileNotFound:
            return "Audio file not found."
        case .audioFileEmpty:
            return "Audio file is empty."
        case .networkError(let error):
            return "Couldn't connect: \(error.localizedDescription)"
        case .transcriptionTimedOut:
            return "Transcription timed out."
        case .apiRequestFailed(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .noTranscriptionReturned:
            return "The server didn't return any text."
        case .invalidResponse:
            return "Received an unexpected response from the server."
        }
    }
}

/// Cloud transcription provider using OpenAI-compatible APIs.
///
/// Supports:
/// - OpenAI Whisper API (default)
/// - Groq (https://api.groq.com/openai/v1)
/// - Any OpenAI-compatible transcription endpoint
///
/// Configuration is read from UserDefaults (baseURL, model, temperature, language)
/// and Keychain (API key).
actor CloudTranscriptionProvider: TranscriptionProvider {

    typealias UploadHandler = @Sendable (URLRequest, Data) async throws -> (Data, URLResponse)
    typealias APIKeyProvider = @Sendable () -> String?
    
    // MARK: - Singleton
    
    static let shared = CloudTranscriptionProvider()
    
    // MARK: - Logger
    
    private let logger = Logger.app(category: "CloudTranscriptionProvider")

    private let session: URLSession
    private let apiKeyProvider: APIKeyProvider
    private let uploadHandler: UploadHandler?
    private let configurationProvider: @Sendable () -> CloudTranscriptionConfiguration

    private enum NetworkPolicy {
        static let maxUploadAttempts = 2
        static let retryDelayNanoseconds: UInt64 = 500_000_000
    }

    private init(
        session: URLSession = CloudTranscriptionProvider.makeSession(),
        apiKeyProvider: @escaping APIKeyProvider = {
            KeychainService.shared.load(KeychainService.Key.apiKey)
        }
    ) {
        self.session = session
        self.apiKeyProvider = apiKeyProvider
        self.uploadHandler = nil
        self.configurationProvider = { .load() }
    }

    init(
        apiKeyProvider: @escaping APIKeyProvider,
        configurationProvider: @escaping @Sendable () -> CloudTranscriptionConfiguration = { .load() },
        uploadHandler: @escaping UploadHandler
    ) {
        self.session = CloudTranscriptionProvider.makeSession()
        self.apiKeyProvider = apiKeyProvider
        self.uploadHandler = uploadHandler
        self.configurationProvider = configurationProvider
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }
    
    // MARK: - Public API
    
    /// Transcribes the audio file at the given URL.
    ///
    /// - Parameters:
    ///   - audioURL: URL to the audio file (wav, m4a, mp3, etc.)
    ///   - context: The pre-captured context profile.
    /// - Returns: The transcribed text.
    /// - Throws: `TranscriptionError` if transcription fails.
    func transcribe(audioURL: URL, context: ContextProfile) async throws -> String {
        try Task.checkCancellation()
        let configuration = configurationProvider()
        let url = try configuration.endpoint()
        guard configuration.temperature.isFinite, (0...1).contains(configuration.temperature) else {
            throw TranscriptionError.invalidConfiguration("Temperature must be between 0 and 1.")
        }

        // Get API key from the configured credential source.
        let apiKey = apiKeyProvider()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey,
              !apiKey.isEmpty else {
            logger.error("API key is missing")
            throw TranscriptionError.apiKeyMissing
        }
        
        // Validate audio file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            logger.error("Audio file not found: \(audioURL.path)")
            throw TranscriptionError.audioFileNotFound
        }
        
        // Validate audio file is not empty
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path)
        let fileSize = fileAttributes?[.size] as? Int64 ?? 0
        guard fileSize > 0 else {
            logger.error("Audio file is empty: \(audioURL.path)")
            throw TranscriptionError.audioFileEmpty
        }
        
        logger.info("Starting transcription for file: \(audioURL.lastPathComponent) (\(fileSize) bytes)")
        
        // Create multipart form data
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Azure uses "api-key" header, OpenAI uses "Authorization: Bearer"
        if let host = url.host, host.hasSuffix(".openai.azure.com") {
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
        } else {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        // Build multipart body
        let audioData: Data
        do {
            audioData = try Data(contentsOf: audioURL)
        } catch {
            logger.error("Failed to read audio file: \(error.localizedDescription)")
            throw TranscriptionError.audioFileNotFound
        }
        
        let body = buildMultipartBody(
            boundary: boundary,
            audioData: audioData,
            audioFileName: audioURL.lastPathComponent,
            context: context,
            configuration: configuration
        )
        
        // Make the request using upload API (better for large files)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await uploadWithRetry(request: request, body: body)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            throw mapNetworkError(error)
        }
        
        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid HTTP response")
            throw TranscriptionError.invalidResponse
        }
        
        // Check for success status codes (200-299)
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            logger.error("API request failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw TranscriptionError.apiRequestFailed(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        // Parse response
        let whisperResponse: WhisperResponse
        do {
            whisperResponse = try JSONDecoder().decode(WhisperResponse.self, from: data)
        } catch {
            logger.error("Failed to decode response: \(error.localizedDescription)")
            throw TranscriptionError.invalidResponse
        }
        
        // Check for empty transcription
        guard !whisperResponse.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("API returned empty transcription")
            throw TranscriptionError.noTranscriptionReturned
        }
        
        try Task.checkCancellation()
        logger.info("Cloud transcription completed")
        
        // Clean and return text
        return whisperResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Upload Retry

    private func uploadWithRetry(request: URLRequest, body: Data) async throws -> (Data, URLResponse) {
        var lastError: Error?

        for attempt in 1...NetworkPolicy.maxUploadAttempts {
            do {
                return try await upload(request: request, body: body)
            } catch {
                if Task.isCancelled || isCancellation(error) {
                    throw CancellationError()
                }

                lastError = error
                logNetworkError(error, attempt: attempt)

                guard attempt < NetworkPolicy.maxUploadAttempts,
                      isTransientNetworkError(error) else {
                    throw error
                }

                // A lost upload response may already have reached the server. Keep this
                // to one retry unless the transcription endpoint supports idempotency.
                logger.info("Retrying cloud transcription upload after transient network error")
                try await Task.sleep(nanoseconds: NetworkPolicy.retryDelayNanoseconds)
            }
        }

        throw lastError ?? TranscriptionError.invalidResponse
    }

    private func upload(request: URLRequest, body: Data) async throws -> (Data, URLResponse) {
        if let uploadHandler {
            return try await uploadHandler(request, body)
        }

        return try await session.upload(for: request, from: body)
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func mapNetworkError(_ error: Error) -> TranscriptionError {
        if let urlError = error as? URLError,
           urlError.code == .timedOut {
            return .transcriptionTimedOut
        }

        logger.error("Network request failed: \(error.localizedDescription)")
        return .networkError(error)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        return (error as? URLError)?.code == .cancelled
    }

    private func logNetworkError(_ error: Error, attempt: Int) {
        if let urlError = error as? URLError {
            logger.error("Cloud transcription upload attempt \(attempt) failed with URLError \(urlError.code.rawValue): \(urlError.localizedDescription)")
        } else {
            logger.error("Cloud transcription upload attempt \(attempt) failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Error Parsing
    
    /// Attempts to parse an error message from the API response body.
    private func parseErrorMessage(from data: Data) -> String? {
        // Try OpenAI error format
        if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return errorResponse.error.message
        }
        
        // Try plain text
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text.prefix(200).description
        }
        
        return nil
    }
    
    // MARK: - Multipart Form Data
    
    private func buildMultipartBody(boundary: String, audioData: Data, audioFileName: String, context: ContextProfile, configuration: CloudTranscriptionConfiguration) -> Data {
        var body = Data()
        let crlf = "\r\n"
        
        // Determine content type based on file extension
        let contentType = mimeType(for: audioFileName)
        
        // Helper to safely append UTF-8 strings
        func appendString(_ string: String) {
            if let data = string.data(using: .utf8) {
                body.append(data)
            }
        }
        
        // File field
        appendString("--\(boundary)\(crlf)")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioFileName)\"\(crlf)")
        appendString("Content-Type: \(contentType)\(crlf)\(crlf)")
        body.append(audioData)
        appendString(crlf)
        
        // Model field
        appendString("--\(boundary)\(crlf)")
        appendString("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)")
        appendString("\(configuration.modelName)\(crlf)")
        
        // Response format field (ensures JSON response)
        appendString("--\(boundary)\(crlf)")
        appendString("Content-Disposition: form-data; name=\"response_format\"\(crlf)\(crlf)")
        appendString("json\(crlf)")
        
        // GPT-Transcribe uses language arrays and does not accept the legacy temperature field.
        if !configuration.usesLanguageArray {
            appendString("--\(boundary)\(crlf)")
            appendString("Content-Disposition: form-data; name=\"temperature\"\(crlf)\(crlf)")
            appendString("\(configuration.temperature)\(crlf)")
        }

        if let language = configuration.languageHint {
            let field = configuration.usesLanguageArray ? "languages[]" : "language"
            appendString("--\(boundary)\(crlf)")
            appendString("Content-Disposition: form-data; name=\"\(field)\"\(crlf)\(crlf)")
            appendString("\(language)\(crlf)")
        }

        // Prompt field (only if context provides one)
        if let prompt = context.whisperPrompt {
            appendString("--\(boundary)\(crlf)")
            appendString("Content-Disposition: form-data; name=\"prompt\"\(crlf)\(crlf)")
            appendString("\(prompt)\(crlf)")
        }
        
        // Closing boundary
        appendString("--\(boundary)--\(crlf)")
        
        return body
    }
    
    /// Returns the MIME type for an audio file based on extension.
    private func mimeType(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        case "m4a", "mp4":
            return "audio/mp4"
        case "webm":
            return "audio/webm"
        case "flac":
            return "audio/flac"
        case "ogg":
            return "audio/ogg"
        default:
            return "audio/wav"  // Default to wav
        }
    }
    
    // MARK: - Text Cleaning
    
    static func cleanTranscriptionText(_ text: String) -> String {
        TranscriptionOutputFilter.filter(text)
    }

}

// MARK: - Response Models

/// OpenAI Whisper API response.
private struct WhisperResponse: Codable {
    let text: String
}

/// OpenAI API error response.
private struct APIErrorResponse: Codable {
    let error: APIError
    
    struct APIError: Codable {
        let message: String
        let type: String?
        let code: String?
    }
}
