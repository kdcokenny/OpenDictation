import AppKit
import Foundation
import os.log

/// Source metadata for one speech recognition pass.
struct TranscriptionMetadata: Equatable, Sendable {
    let provider: TranscriptionMode
    let speechModelID: String?
    let language: String?
}

/// Raw transcription output before transcript cleanup policy is applied.
struct TranscriptionProviderResult: Equatable, Sendable {
    let rawText: String
    let metadata: TranscriptionMetadata
}

enum CleanupRoute: String, Equatable, Codable, Sendable {
    case deterministic
    case modelEligible
    case terminal
    case developer
    case literal
    case formatting
}

enum CleanupModelState: Equatable, Sendable {
    case unloaded
    case loading
    case loaded
    case prewarming
    case ready
    case unavailable(String)
}

enum CleanupFallbackReason: String, Equatable, Codable, Sendable {
    case modelUnavailable
    case modelTimedOut
    case modelRejected
    case deterministicOnly
}

enum TranscriptCleanupError: LocalizedError, Equatable, Sendable {
    case modelUnavailable
    case modelTimedOut
    case modelRejected

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "Local cleanup model is not ready. Nothing was pasted."
        case .modelTimedOut:
            return "Local cleanup model timed out. Nothing was pasted."
        case .modelRejected:
            return "Local cleanup could not produce a safe result. Nothing was pasted."
        }
    }
}

enum CleanupValidationDecision: String, Equatable, Codable, Sendable {
    case accepted
    case rejected
    case notEvaluated
}

struct CleanupContextSnapshot: Equatable, Sendable {
    let profile: ContextProfile
    let bundleIdentifier: String?
    let appName: String?
    let isTerminalApp: Bool
    let isKnownCodeEditor: Bool
    let language: String?

    static func capture(profile: ContextProfile) -> CleanupContextSnapshot {
        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier
        return CleanupContextSnapshot(
            profile: profile,
            bundleIdentifier: bundleID,
            appName: app?.localizedName,
            isTerminalApp: bundleID.map(Self.terminalBundleIDs.contains) ?? false,
            isKnownCodeEditor: bundleID.map(Self.codeEditorBundleIDs.contains) ?? false,
            language: UserDefaults.standard.string(forKey: "language")
        )
    }

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "io.alacritty",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty"
    ]

    private static let codeEditorBundleIDs: Set<String> = [
        "com.apple.Xcode",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.todesktop.230313mzl4w4u92",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "com.exafunction.windsurf",
        "com.jetbrains.AppCode",
        "com.jetbrains.CLion",
        "com.jetbrains.intellij",
        "com.jetbrains.WebStorm"
    ]
}

struct CleanupResult: Equatable, Sendable {
    let rawText: String
    let artifactFilteredText: String
    let finalText: String
    let route: CleanupRoute
    let modelID: String?
    let promptVersion: String?
    let validationDecision: CleanupValidationDecision
    let fallbackReason: CleanupFallbackReason?
    let latencyMilliseconds: Int
}

extension CleanupResult {
    var blockingError: TranscriptCleanupError? {
        guard route == .modelEligible else { return nil }

        switch fallbackReason {
        case .modelUnavailable:
            return .modelUnavailable
        case .modelTimedOut:
            return .modelTimedOut
        case .modelRejected:
            return .modelRejected
        case .deterministicOnly, nil:
            return nil
        }
    }
}

struct DictationPipelineResult: Equatable, Sendable {
    let finalText: String
    let transcription: TranscriptionProviderResult
    let cleanup: CleanupResult
}

struct CleanupModelManifest: Equatable, Codable, Sendable {
    let id: String
    let runtime: String
    let promptVersion: String
    let quantization: String?
    let sha256: String?
    let minimumMemoryGB: Int
    let recommendedMemoryGB: Int
    let supportedRoutes: [CleanupRoute]
    let supportedLocales: [String]
    let bundlePath: String
    let benchmarkBaselineID: String?
}

struct CleanupModelRequest: Equatable, Sendable {
    let rawText: String
    let deterministicText: String
    let route: CleanupRoute
    let context: CleanupContextSnapshot
    let promptVersion: String
    let deadline: Date
    let maxOutputCharacters: Int
}

struct CleanupModelCandidate: Equatable, Sendable {
    let text: String
    let modelID: String
    let promptVersion: String
    let latencyMilliseconds: Int
    let timedOut: Bool
}

protocol CleanupModelRunner: Sendable {
    var manifest: CleanupModelManifest { get }
    func load() async throws
    func prewarm() async throws
    func state() async -> CleanupModelState
    func clean(_ request: CleanupModelRequest) async throws -> CleanupModelCandidate
    func cancel() async
}

actor CleanupModelRegistry {
    static let shared = CleanupModelRegistry()

    private let logger = Logger.app(category: "CleanupModelRegistry")
    private var runner: (any CleanupModelRunner)?
    private var lastUsedAt: Date?

    func installRunner(_ runner: any CleanupModelRunner) {
        self.runner = runner
    }

    func prepareForRecording() async {
        guard let runner else { return }
        let currentState = await runner.state()
        guard currentState == .unloaded else { return }

        do {
            try await runner.load()
            try await runner.prewarm()
            lastUsedAt = Date()
        } catch {
            logger.warning("Cleanup model unavailable: \(error.localizedDescription)")
        }
    }

    func readyRunner() async -> (any CleanupModelRunner)? {
        guard let runner else { return nil }
        guard await runner.state() == .ready else { return nil }
        lastUsedAt = Date()
        return runner
    }
}

actor TranscriptPostProcessor {
    static let shared = TranscriptPostProcessor()

    private let modelRegistry: CleanupModelRegistry

    init(modelRegistry: CleanupModelRegistry = .shared) {
        self.modelRegistry = modelRegistry
    }

    func prepareForRecording(context: ContextProfile) async {
        _ = context
        await modelRegistry.prepareForRecording()
    }

    func process(
        transcription: TranscriptionProviderResult,
        context: CleanupContextSnapshot
    ) async -> CleanupResult {
        let startedAt = Date()
        let artifactFiltered = TranscriptionOutputFilter.filter(transcription.rawText)
        let deterministic = DeterministicTranscriptCleaner.clean(artifactFiltered, context: context)
        let route = CleanupPolicyRouter.route(
            rawText: transcription.rawText,
            deterministicText: deterministic,
            context: context
        )

        guard route == .modelEligible,
              let runner = await modelRegistry.readyRunner() else {
            return CleanupResult(
                rawText: transcription.rawText,
                artifactFilteredText: artifactFiltered,
                finalText: deterministic,
                route: route,
                modelID: nil,
                promptVersion: nil,
                validationDecision: .notEvaluated,
                fallbackReason: route == .modelEligible ? .modelUnavailable : .deterministicOnly,
                latencyMilliseconds: Self.elapsedMilliseconds(since: startedAt)
            )
        }

        let manifest = runner.manifest
        let request = CleanupModelRequest(
            rawText: transcription.rawText,
            deterministicText: deterministic,
            route: route,
            context: context,
            promptVersion: manifest.promptVersion,
            deadline: Date().addingTimeInterval(2),
            maxOutputCharacters: max(artifactFiltered.count * 2, 256)
        )

        do {
            let candidate = try await runner.clean(request)
            let validation = CleanupValidator.validate(
                candidate: candidate.text,
                deterministicText: deterministic,
                route: route
            )
            guard validation == .accepted else {
                return CleanupResult(
                    rawText: transcription.rawText,
                    artifactFilteredText: artifactFiltered,
                    finalText: deterministic,
                    route: route,
                    modelID: candidate.modelID,
                    promptVersion: candidate.promptVersion,
                    validationDecision: validation,
                    fallbackReason: .modelRejected,
                    latencyMilliseconds: Self.elapsedMilliseconds(since: startedAt)
                )
            }

            return CleanupResult(
                rawText: transcription.rawText,
                artifactFilteredText: artifactFiltered,
                finalText: candidate.text,
                route: route,
                modelID: candidate.modelID,
                promptVersion: candidate.promptVersion,
                validationDecision: validation,
                fallbackReason: nil,
                latencyMilliseconds: Self.elapsedMilliseconds(since: startedAt)
            )
        } catch {
            return CleanupResult(
                rawText: transcription.rawText,
                artifactFilteredText: artifactFiltered,
                finalText: deterministic,
                route: route,
                modelID: manifest.id,
                promptVersion: manifest.promptVersion,
                validationDecision: .notEvaluated,
                fallbackReason: .modelUnavailable,
                latencyMilliseconds: Self.elapsedMilliseconds(since: startedAt)
            )
        }
    }

    private static func elapsedMilliseconds(since startDate: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(startDate) * 1_000))
    }
}

enum CleanupPolicyRouter {
    static func route(
        rawText: String,
        deterministicText: String,
        context: CleanupContextSnapshot
    ) -> CleanupRoute {
        let lower = rawText.lowercased()

        if context.isTerminalApp {
            return .terminal
        }

        if context.profile == .code || context.isKnownCodeEditor {
            return .developer
        }

        if lower.contains("write the word") ||
            lower.contains("write the phrase") ||
            lower.contains("literal") {
            return .literal
        }

        if lower.contains("bullet list") ||
            lower.contains("new paragraph") ||
            lower.contains("new line") {
            return .formatting
        }

        if containsAmbiguousCorrection(lower) {
            return .modelEligible
        }

        return .deterministic
    }

    private static func containsAmbiguousCorrection(_ text: String) -> Bool {
        text.range(
            of: #"\b(no[\s,]+actually|no[\s,]+wait|sorry|i mean|start over)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

enum CleanupValidator {
    static func validate(
        candidate: String,
        deterministicText: String,
        route: CleanupRoute
    ) -> CleanupValidationDecision {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected }

        let lower = trimmed.lowercased()
        if lower.hasPrefix("sure") ||
            lower.hasPrefix("here is") ||
            lower.hasPrefix("i can't") ||
            lower.hasPrefix("i cannot") {
            return .rejected
        }

        if route == .terminal || route == .literal {
            return trimmed == deterministicText ? .accepted : .rejected
        }

        let deterministicWords = wordCount(deterministicText)
        let candidateWords = wordCount(trimmed)
        if deterministicWords > 8 && candidateWords < max(4, deterministicWords / 2) {
            return .rejected
        }

        return .accepted
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }
}

enum DeterministicTranscriptCleaner {
    static func clean(_ text: String, context: CleanupContextSnapshot) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        result = removeLeadingScaffolding(result)
        result = applySpokenEditCommands(result)
        result = removeSafeFillers(result)
        result = dedupeAdjacentPhrases(result)
        result = normalizeCommonAcronyms(result)
        result = normalizeSpokenPunctuation(result)

        if context.profile == .code || context.isKnownCodeEditor || context.isTerminalApp {
            result = normalizeDeveloperVocabulary(result)
        }

        result = result.replacingOccurrences(
            of: #"[ \t\r\f\v]+"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !result.isEmpty else { return result }
        guard context.isTerminalApp == false else { return result }
        guard result.last.map({ ".!?:)\"]\n".contains($0) }) != true else { return result }
        return "\(result)."
    }

    private static func removeLeadingScaffolding(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"^\s*(i think what i mean is|what i mean is|i want to say that|basically|so basically|okay|ok|so|well)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    private static func applySpokenEditCommands(_ text: String) -> String {
        if text.range(
            of: #"\b(word|phrase|sentence|text|called|says|said)\s+scratch that\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return text
        }

        guard let range = text.range(
            of: #"\b(actually\s+)?scratch that[.!?,;:]?\s+(.+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return text
        }

        return String(text[range])
            .replacingOccurrences(
                of: #"^(actually\s+)?scratch that[.!?,;:]?\s+"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
    }

    private static func removeSafeFillers(_ text: String) -> String {
        var result = text
        let patterns = [
            #"^\s*(um+|uh+|erm|er|ah)\s+"#,
            #"^\s*(you know|like)\s+"#,
            #"\b,\s*(you know|like)\s+"#,
            #"(?<!word )\b(um+|uh+)\b"#,
            #"\bbut like\b"#
        ]

        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return result
    }

    private static func dedupeAdjacentPhrases(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        var changed = true

        while changed {
            changed = false
            var next: [String] = []
            var index = 0

            while index < words.count {
                var removed = false
                for length in stride(from: min(10, (words.count - index) / 2), through: 2, by: -1) {
                    let left = normalized(words[index..<(index + length)])
                    let right = normalized(words[(index + length)..<(index + length * 2)])
                    if left == right {
                        next.append(contentsOf: words[index..<(index + length)])
                        index += length * 2
                        changed = true
                        removed = true
                        break
                    }
                }

                if !removed {
                    next.append(words[index])
                    index += 1
                }
            }

            words = next
        }

        return words.joined(separator: " ")
    }

    private static func normalized(_ words: ArraySlice<String>) -> [String] {
        words.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: ".,")).lowercased()
        }
    }

    private static func normalizeCommonAcronyms(_ text: String) -> String {
        var result = text
        [
            "ai": "AI",
            "api": "API",
            "cli": "CLI",
            "llm": "LLM",
            "url": "URL"
        ].forEach { phrase, replacement in
            result = replaceWord(phrase, with: replacement, in: result)
        }
        return result
    }

    private static func normalizeSpokenPunctuation(_ text: String) -> String {
        var result = text
        [
            "note colon": "Note:",
            "new paragraph": "\n\n",
            "new line": "\n",
            "comma": ","
        ].forEach { phrase, replacement in
            result = replaceWord(phrase, with: replacement, in: result)
        }
        return result
    }

    private static func normalizeDeveloperVocabulary(_ text: String) -> String {
        var result = text
        [
            "open dictation": "OpenDictation",
            "transcription coordinator": "TranscriptionCoordinator",
            "transcript post processor": "TranscriptPostProcessor",
            "app delegate": "AppDelegate",
            "user defaults": "UserDefaults",
            "model manager": "ModelManager",
            "settings view": "SettingsView",
            "swift ui": "SwiftUI",
            "url session": "URLSession",
            "x c test": "XCTest",
            "async await": "async/await",
            "selected cleanup model name": "selectedCleanupModelName",
            "selected model name": "selectedModelName",
            "package dot swift": "Package.swift",
            "readme dot md": "README.md",
            "dash b": "-b",
            "dash dash": "--"
        ].forEach { phrase, replacement in
            result = replaceWord(phrase, with: replacement, in: result)
        }
        result = result.replacingOccurrences(
            of: #"\s+slash\s+"#,
            with: "/",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\s+dot\s+([A-Za-z0-9]+)"#,
            with: ".$1",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\s+underscore\s+"#,
            with: "_",
            options: [.regularExpression, .caseInsensitive]
        )
        return result
    }

    private static func replaceWord(
        _ phrase: String,
        with replacement: String,
        in text: String
    ) -> String {
        text.replacingOccurrences(
            of: #"\b\#(NSRegularExpression.escapedPattern(for: phrase))\b"#,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
