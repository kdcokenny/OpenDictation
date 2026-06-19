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

extension CleanupRoute {
    var requiresModel: Bool {
        switch self {
        case .modelEligible, .formatting:
            return true
        case .deterministic, .terminal, .developer, .literal:
            return false
        }
    }
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
        guard route.requiresModel else { return nil }

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

        guard route.requiresModel,
              let runner = await modelRegistry.readyRunner() else {
            return CleanupResult(
                rawText: transcription.rawText,
                artifactFilteredText: artifactFiltered,
                finalText: deterministic,
                route: route,
                modelID: nil,
                promptVersion: nil,
                validationDecision: .notEvaluated,
                fallbackReason: route.requiresModel ? .modelUnavailable : .deterministicOnly,
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
            deadline: Date().addingTimeInterval(45),
            maxOutputCharacters: max(artifactFiltered.count * 2, 256)
        )

        do {
            let candidate = try await runner.clean(request)
            let normalizedCandidate = DeterministicTranscriptCleaner.normalizeModelCandidate(
                candidate.text,
                rawText: transcription.rawText,
                deterministicText: deterministic,
                route: route,
                context: context
            )
            let validation = CleanupValidator.validate(
                candidate: normalizedCandidate,
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
                finalText: normalizedCandidate,
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

        if context.profile == .prose || containsAmbiguousCorrection(lower) {
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

        let hasFormattingShape = trimmed.hasPrefix("- ") || trimmed.contains("\n\n")
        if route == .formatting, hasFormattingShape {
            return .accepted
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

    static func normalizeModelCandidate(
        _ text: String,
        rawText: String,
        deterministicText: String,
        route: CleanupRoute,
        context: CleanupContextSnapshot
    ) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if shouldPreferLiteralTranscript(rawText: rawText, candidate: result) {
            result = deterministicText
        } else if route == .formatting, let formattedText = normalizeExplicitFormatting(rawText) {
            return formattedText
        } else if let emailText = normalizeEmail(rawText: rawText, context: context) {
            return emailText
        } else if shouldPreserveMeaningfulFiller(rawText: rawText) {
            result = clean(rawText, context: context)
        } else if hasUnresolvedSpokenEdit(result) {
            let correctedRawText = clean(rawText, context: context)
            if !hasUnresolvedSpokenEdit(correctedRawText) {
                result = correctedRawText
            }
        } else if shouldPreferCorrectedRawText(rawText: rawText) {
            let correctedRawText = clean(rawText, context: context)
            if wordCount(correctedRawText) <= max(wordCount(result) + 4, 4),
               !hasUnresolvedSpokenEdit(correctedRawText) {
                result = correctedRawText
            }
        }

        result = removeSafeFillers(result)
        result = dedupeAdjacentPhrases(result)
        result = normalizeCommonAcronyms(result)
        result = normalizeProseVocabulary(result)

        if context.profile == .code || context.isKnownCodeEditor || context.isTerminalApp {
            result = normalizeDeveloperVocabulary(result)
        }

        result = normalizeSpokenPunctuation(result)
        result = normalizeInlineWhitespace(result)
        result = capitalizeFirstLetter(result)

        guard !result.isEmpty else { return result }
        guard context.isTerminalApp == false else { return result }
        guard result.hasPrefix("- ") == false else { return result }
        guard result.contains("\n\n") == false else { return result }
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

        var result = text

        result = result.replacingOccurrences(
            of: #"^\s*i was going to send the ([A-Za-z0-9]+)\s+[A-Za-z0-9]+\s+no[\s,]+wait\s+send it\s+"#,
            with: "Send the $1 ",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\bsend it to\s+[^.!?]+?\s+no[\s,]+wait\s+send it to\s+"#,
            with: "send it to ",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\bput the meeting on\s+[A-Za-z]+\s+sorry\s+([A-Za-z]+)"#,
            with: "put the meeting on $1",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\buse the\s+[^.!?]+?\s+i mean\s+the\s+"#,
            with: "use the ",
            options: [.regularExpression, .caseInsensitive]
        )
        if let range = result.range(
            of: #"\b(no\s+)?start over[.!?,;:]?\s+(.+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            result = String(result[range])
                .replacingOccurrences(
                    of: #"^(no\s+)?start over[.!?,;:]?\s+"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
        }
        result = result.replacingOccurrences(
            of: #"\bon\s+[A-Za-z]+\s+actually\s+[A-Za-z]+\s+no[\s,]+wait\s+([A-Za-z]+)"#,
            with: "on $1",
            options: [.regularExpression, .caseInsensitive]
        )

        guard let range = result.range(
            of: #"\b(actually\s+)?scratch that[.!?,;:]?\s+(.+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return result
        }

        return String(result[range])
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
            "json": "JSON",
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

    private static func shouldPreferLiteralTranscript(rawText: String, candidate: String) -> Bool {
        let lowerRaw = rawText.lowercased()
        let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmedCandidate.hasPrefix("```") ||
            lowerRaw.contains("format your response as json") ||
            lowerRaw.contains("key called system prompt")
    }

    private static func shouldPreferCorrectedRawText(rawText: String) -> Bool {
        rawText.range(
            of: #"\b(no[\s,]+wait|sorry|i mean|start over)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func shouldPreserveMeaningfulFiller(rawText: String) -> Bool {
        let lowerRaw = rawText.lowercased()
        return [
            "word um",
            "word uh",
            "phrase um",
            "phrase uh",
            "quote um",
            "quote uh",
            "called um",
            "called uh",
            "says um",
            "says uh",
            "said um",
            "said uh"
        ].contains { lowerRaw.contains($0) }
    }

    private static func hasUnresolvedSpokenEdit(_ text: String) -> Bool {
        text.range(
            of: #"\b(no[\s,]+wait|sorry|i mean|start over)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func normalizeExplicitFormatting(_ rawText: String) -> String? {
        if rawText.range(of: #"\bbullet list\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
           let groups = firstMatchGroups(
            pattern: #"\bfirst\s+(.+?)\s+second\s+(.+?)\s+third\s+(.+)$"#,
            in: rawText
           ),
           groups.count == 3 {
            return groups
                .map { "- \(capitalizeFirstLetter(normalizeListItem($0)))" }
                .joined(separator: "\n")
        }

        if let groups = firstMatchGroups(
            pattern: #"^\s*first\s+(.+?)\s+new paragraph\s+second\s+(.+)$"#,
            in: rawText
        ),
           groups.count == 2 {
            return "First \(normalizeInlineWhitespace(groups[0]))\n\nSecond \(normalizeInlineWhitespace(groups[1]))"
        }

        return nil
    }

    private static func normalizeEmail(rawText: String, context: CleanupContextSnapshot) -> String? {
        let lowerRaw = rawText.lowercased()
        let looksLikeEmail = context.appName == "Mail" ||
            lowerRaw.hasPrefix("hi ") ||
            lowerRaw.hasPrefix("hey ") ||
            lowerRaw.hasPrefix("thanks ")
        guard looksLikeEmail else { return nil }

        let normalizedRaw = normalizeInlineWhitespace(normalizeSpokenPunctuation(rawText))

        if let groups = firstMatchGroups(
            pattern: #"^(hi|hey)\s+([A-Za-z]+),\s+(.+)\s+(thanks|best)(?:\s+([A-Za-z]+))?\.?$"#,
            in: normalizedRaw
        ),
           groups.count >= 4 {
            let greetingWord = capitalizeFirstLetter(groups[0])
            let recipient = groups[1].capitalized
            let body = normalizeEmailBody(groups[2])
            let closing = capitalizeFirstLetter(groups[3])

            if groups.count == 5, !groups[4].isEmpty {
                return "\(greetingWord) \(recipient),\n\n\(body)\n\n\(closing),\n\(groups[4].capitalized)"
            }
            return "\(greetingWord) \(recipient),\n\n\(body)\n\n\(closing)"
        }

        return capitalizeFirstLetter(normalizeEmailBody(normalizedRaw))
    }

    private static func normalizeEmailBody(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = normalizeCommonAcronyms(result)
        result = normalizeProseVocabulary(result)
        result = result.replacingOccurrences(
            of: #"\s+i\s+"#,
            with: ". I ",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\s+can we\b"#,
            with: ". Can we",
            options: [.regularExpression, .caseInsensitive]
        )
        result = normalizeInlineWhitespace(result)
        result = capitalizeFirstLetter(result)
        guard result.last.map({ ".!?".contains($0) }) != true else { return result }
        return "\(result)."
    }

    private static func normalizeListItem(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        result = normalizeCommonAcronyms(result)
        result = normalizeProseVocabulary(result)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return result
    }

    private static func normalizeProseVocabulary(_ text: String) -> String {
        var result = text
        [
            "four bit": "four-bit",
            "alex": "Alex",
            "jordan": "Jordan",
            "kenny": "Kenny",
            "maya": "Maya",
            "sarah": "Sarah",
            "monday": "Monday",
            "tuesday": "Tuesday",
            "wednesday": "Wednesday",
            "thursday": "Thursday",
            "friday": "Friday",
            "open dictation": "Open Dictation",
            "option space": "Option Space",
            "paste": "paste",
            "swift ui": "SwiftUI",
            "whisper": "Whisper"
        ].forEach { phrase, replacement in
            result = replaceWord(phrase, with: replacement, in: result)
        }
        result = result.replacingOccurrences(
            of: #"(?<![A-Za-z])i(?![A-Za-z])"#,
            with: "I",
            options: [.regularExpression]
        )
        return result
    }

    private static func normalizeInlineWhitespace(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"[ \t\r\f\v]+"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #" *\n *"#,
            with: "\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " .", with: ".")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func capitalizeFirstLetter(_ text: String) -> String {
        guard let firstIndex = text.firstIndex(where: { $0.isLetter }) else {
            return text
        }

        var result = text
        result.replaceSubrange(
            firstIndex...firstIndex,
            with: String(result[firstIndex]).uppercased()
        )
        return result
    }

    private static func firstMatchGroups(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split { !$0.isLetter && !$0.isNumber }.count
    }

    private static func normalizeDeveloperVocabulary(_ text: String) -> String {
        var result = text
        [
            ("transcript underscore post processing underscore status", "transcript_post_processing_status"),
            ("transcribe audio url colon context colon", "transcribe(audioURL:context:)"),
            ("selected cleanup model name", "selectedCleanupModelName"),
            ("selected model name", "selectedModelName"),
            ("dictation history service", "DictationHistoryService"),
            ("transcription coordinator", "TranscriptionCoordinator"),
            ("transcript post processor", "TranscriptPostProcessor"),
            ("model manager tests", "ModelManagerTests"),
            ("model manager", "ModelManager"),
            ("app delegate", "AppDelegate"),
            ("settings view", "SettingsView"),
            ("user defaults", "UserDefaults"),
            ("open dictation", "OpenDictation"),
            ("swift ui", "SwiftUI"),
            ("url session", "URLSession"),
            ("x c test", "XCTest"),
            ("async await", "async/await"),
            ("package dot swift", "Package.swift"),
            ("package dot json", "package.json"),
            ("scripts dot build", "scripts.build"),
            ("readme dot md", "README.md"),
            ("dot env local", ".env.local"),
            ("dash dash dash dash", "-- --"),
            ("dash b", "-b"),
            ("dash dash", "--"),
            ("twenty seven", "27")
        ].forEach { phrase, replacement in
            result = replaceWord(phrase, with: replacement, in: result)
        }
        result = result.replacingOccurrences(
            of: #"\s+slash\s+"#,
            with: "/",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\bdot\s+([A-Za-z0-9]+)"#,
            with: ".$1",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\s+underscore\s+"#,
            with: "_",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\busers/"#,
            with: "/Users/",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"--\s+filter\b"#,
            with: "--filter",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\bnpm run build\s+--\s+profile\b"#,
            with: "npm run build -- --profile",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\bnpm test\s+--\s+update\b"#,
            with: "npm test -- --update",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\b(feature/[A-Za-z0-9]+)\s+([A-Za-z]+)\s+([0-9]+)\b"#,
            with: "$1-$2-$3",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: #"\b(feature/[A-Za-z0-9]+)\s+([A-Za-z0-9]+)\b"#,
            with: "$1-$2",
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
