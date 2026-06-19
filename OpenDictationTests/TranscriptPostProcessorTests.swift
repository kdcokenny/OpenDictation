import XCTest
@testable import OpenDictation

final class TranscriptPostProcessorTests: XCTestCase {

    func testArtifactFilterPreservesCodeAndLiteralText() {
        let input = #"Call transcribe(audioURL:context:) with array[index] and { "key": "value" }."#

        XCTAssertEqual(TranscriptionOutputFilter.filter(input), input)
    }

    func testArtifactFilterRemovesOnlyKnownStandaloneArtifacts() {
        let input = "Hello [BLANK_AUDIO] world (music)"

        XCTAssertEqual(TranscriptionOutputFilter.filter(input), "Hello world")
    }

    func testDeterministicCleanerRemovesRepeatedPhrase() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "tell Sarah the onboarding flow the onboarding flow should be behind a feature flag",
            context: context
        )

        XCTAssertEqual(output, "tell Sarah the onboarding flow should be behind a feature flag.")
    }

    func testLiteralScratchThatIsPreserved() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "write the phrase scratch that in the release notes",
            context: context
        )

        XCTAssertEqual(output, "write the phrase scratch that in the release notes.")
    }

    func testScratchThatCommandDropsAbandonedPrefix() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "send the draft tonight scratch that send the draft monday morning after I reread it",
            context: context
        )

        XCTAssertEqual(output, "send the draft monday morning after I reread it.")
    }

    func testScratchThatCommandDropsAbandonedSentence() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "Send the draft tonight. Actually scratch that. Send the draft Monday morning after I reread it.",
            context: context
        )

        XCTAssertEqual(output, "Send the draft Monday morning after I reread it.")
    }

    func testNoWayCorrectionRestoresAbandonedObject() {
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let output = DeterministicTranscriptCleaner.clean(
            "i was going to ask Nina to send the numbers today no way ask Omar to send them tomorrow morning after stand up",
            context: context
        )

        XCTAssertEqual(output, "Ask Omar to send the numbers tomorrow morning after stand-up.")
    }

    func testPostProcessorBlocksProseWhenModelIsUnavailable() async {
        let processor = TranscriptPostProcessor(modelRegistry: CleanupModelRegistry())
        let transcription = TranscriptionProviderResult(
            rawText: "um we should keep the settings simple",
            metadata: TranscriptionMetadata(provider: .local, speechModelID: "test-model", language: "en")
        )
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let result = await processor.process(transcription: transcription, context: context)

        XCTAssertEqual(result.finalText, "we should keep the settings simple.")
        XCTAssertEqual(result.route, .modelEligible)
        XCTAssertEqual(result.fallbackReason, .modelUnavailable)
        XCTAssertEqual(result.blockingError, .modelUnavailable)
        XCTAssertNil(result.modelID)
    }

    func testPostProcessorUsesInstalledRunnerForProse() async {
        let registry = CleanupModelRegistry()
        await registry.installRunner(
            StubCleanupModelRunner(output: "We should keep the settings simple and make the model automatic.")
        )
        await registry.prepareForRecording()

        let processor = TranscriptPostProcessor(modelRegistry: registry)
        let transcription = TranscriptionProviderResult(
            rawText: "um we should keep the settings simple in the model automatic",
            metadata: TranscriptionMetadata(provider: .cloud, speechModelID: "whisper-1", language: "en")
        )
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let result = await processor.process(transcription: transcription, context: context)

        XCTAssertEqual(result.finalText, "We should keep the settings simple and make the model automatic.")
        XCTAssertEqual(result.route, .modelEligible)
        XCTAssertEqual(result.validationDecision, .accepted)
        XCTAssertNil(result.fallbackReason)
        XCTAssertEqual(result.modelID, "stub-cleanup-model")
    }

    func testPostProcessorRestoresNamedPersonWhenModelLeavesPronoun() async {
        let registry = CleanupModelRegistry()
        await registry.installRunner(
            StubCleanupModelRunner(output: "Tell him the onboarding copy needs one more pass before review.")
        )
        await registry.prepareForRecording()

        let processor = TranscriptPostProcessor(modelRegistry: registry)
        let transcription = TranscriptionProviderResult(
            rawText: "can you tell Mark the onboarding copy is ready actually scratch that tell him the onboarding copy needs one more pass before review",
            metadata: TranscriptionMetadata(provider: .local, speechModelID: "test-model", language: "en")
        )
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let result = await processor.process(transcription: transcription, context: context)

        XCTAssertEqual(result.finalText, "Tell Mark the onboarding copy needs one more pass before review.")
        XCTAssertEqual(result.route, .modelEligible)
        XCTAssertEqual(result.validationDecision, .accepted)
        XCTAssertNil(result.fallbackReason)
    }

    func testPostProcessorFormatsChecklistFromRawCommand() async {
        let registry = CleanupModelRegistry()
        await registry.installRunner(
            StubCleanupModelRunner(
                output: "First test, correction phrases, second test, email formatting, third test, developer dictation, fourth test, literal text."
            )
        )
        await registry.prepareForRecording()

        let processor = TranscriptPostProcessor(modelRegistry: registry)
        let transcription = TranscriptionProviderResult(
            rawText: "make this a short checklist first test correction phrases second test email formatting third test developer dictation fourth test literal text",
            metadata: TranscriptionMetadata(provider: .local, speechModelID: "test-model", language: "en")
        )
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let result = await processor.process(transcription: transcription, context: context)

        XCTAssertEqual(
            result.finalText,
            """
            - Test correction phrases
            - Test email formatting
            - Test developer dictation
            - Test literal text
            """
        )
        XCTAssertEqual(result.route, .formatting)
        XCTAssertEqual(result.validationDecision, .accepted)
        XCTAssertNil(result.fallbackReason)
    }

    func testPostProcessorPreservesMeaningfulFillerWordWhenModelDropsIt() async {
        let registry = CleanupModelRegistry()
        await registry.installRunner(
            StubCleanupModelRunner(output: #"The song starts with the word "um" and that word should stay in the quote."#)
        )
        await registry.prepareForRecording()

        let processor = TranscriptPostProcessor(modelRegistry: registry)
        let transcription = TranscriptionProviderResult(
            rawText: "the song starts with the word um and that word should stay in the quote",
            metadata: TranscriptionMetadata(provider: .local, speechModelID: "test-model", language: "en")
        )
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let result = await processor.process(transcription: transcription, context: context)

        XCTAssertEqual(result.finalText, "The song starts with the word um and that word should stay in the quote.")
        XCTAssertEqual(result.route, .modelEligible)
        XCTAssertEqual(result.validationDecision, .accepted)
        XCTAssertNil(result.fallbackReason)
    }

    func testAmbiguousCorrectionWithPunctuationRequiresModel() {
        let rawText = "Send this to Alex. No, actually send it to Jordan before lunch."
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let route = CleanupPolicyRouter.route(
            rawText: rawText,
            deterministicText: rawText,
            context: context
        )

        XCTAssertEqual(route, .modelEligible)
    }

    func testCloudTranscriptionStillBlocksWhenLocalCleanupModelIsUnavailable() async {
        let processor = TranscriptPostProcessor(modelRegistry: CleanupModelRegistry())
        let transcription = TranscriptionProviderResult(
            rawText: "Send this to Alex. No, actually send it to Jordan before lunch.",
            metadata: TranscriptionMetadata(provider: .cloud, speechModelID: "whisper-1", language: "en")
        )
        let context = CleanupContextSnapshot(
            profile: .prose,
            bundleIdentifier: nil,
            appName: nil,
            isTerminalApp: false,
            isKnownCodeEditor: false,
            language: "en"
        )

        let result = await processor.process(transcription: transcription, context: context)

        XCTAssertEqual(result.route, .modelEligible)
        XCTAssertEqual(result.fallbackReason, .modelUnavailable)
        XCTAssertEqual(result.blockingError, .modelUnavailable)
    }

    func testHybridProductBenchmarkSuiteIsLoadable() throws {
        let fixtures = try Self.loadHybridProductFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 70)

        var seenIDs = Set<String>()
        for fixture in fixtures {
            XCTAssertTrue(seenIDs.insert(fixture.id).inserted, "Duplicate benchmark id: \(fixture.id)")
            XCTAssertFalse(fixture.raw.isEmpty, "\(fixture.id) raw transcript is empty")
            XCTAssertTrue(fixture.hasKnownContext, "\(fixture.id) has unknown context: \(fixture.context)")
            XCTAssertFalse(fixture.assertions.isEmpty, "\(fixture.id) has no assertions")
        }
    }

    func testHybridProductBenchmarkProtectedRoutesPassWithoutModel() async throws {
        let fixtures = try Self.loadHybridProductFixtures()
        let processor = TranscriptPostProcessor(modelRegistry: CleanupModelRegistry())
        var checkedCount = 0
        var failures: [String] = []

        for fixture in fixtures {
            let result = await processor.process(
                transcription: fixture.transcription,
                context: fixture.contextSnapshot
            )

            guard !result.route.requiresModel else { continue }
            checkedCount += 1
            failures.append(contentsOf: fixture.failures(for: result))
        }

        XCTAssertGreaterThan(checkedCount, 0)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testLiveHybridProductBenchmarkPassesDefaultLocalModel() async throws {
        guard Self.liveBenchmarkIsEnabled else {
            throw XCTSkip("Run script/benchmark_transcript_cleanup.sh to enable the local cleanup model benchmark.")
        }

        guard let runner = MLXCleanupModelRunner.makeDefaultIfAvailable() else {
            XCTFail("Default local cleanup model is not available.")
            return
        }

        let registry = CleanupModelRegistry()
        await registry.installRunner(runner)
        do {
            try await runner.load()
            try await runner.prewarm()
        } catch {
            XCTFail("Default local cleanup model could not be prepared: \(error.localizedDescription)")
            return
        }

        let processor = TranscriptPostProcessor(modelRegistry: registry)
        let fixtures = try Self.filteredLiveBenchmarkFixtures()
        var failures: [String] = []

        for fixture in fixtures {
            FileHandle.standardError.write(Data("Benchmarking \(fixture.id)\n".utf8))
            let result = await processor.process(
                transcription: fixture.transcription,
                context: fixture.contextSnapshot
            )

            if result.route.requiresModel {
                if let blockingError = result.blockingError {
                    failures.append("\(fixture.id): \(blockingError.localizedDescription)")
                    continue
                }
                if result.validationDecision != .accepted {
                    failures.append("\(fixture.id): model result was \(result.validationDecision.rawValue)")
                    continue
                }
            }

            failures.append(contentsOf: fixture.failures(for: result))
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private static func loadHybridProductFixtures() throws -> [TranscriptCleanupBenchmarkFixture] {
        let suiteURL = hybridProductSuiteURL
        let contents = try String(contentsOf: suiteURL, encoding: .utf8)
        let decoder = JSONDecoder()

        return try contents
            .split(whereSeparator: \.isNewline)
            .enumerated()
            .map { lineOffset, line in
                do {
                    return try decoder.decode(
                        TranscriptCleanupBenchmarkFixture.self,
                        from: Data(line.utf8)
                    )
                } catch {
                    throw TranscriptCleanupBenchmarkDecodeError(
                        line: lineOffset + 1,
                        underlyingError: error
                    )
                }
            }
    }

    private static var liveBenchmarkIsEnabled: Bool {
        if ProcessInfo.processInfo.environment["OPENDICTATION_RUN_LIVE_CLEANUP_BENCHMARKS"] == "1" {
            return true
        }

        return FileManager.default.fileExists(atPath: liveBenchmarkMarkerURL.path)
    }

    private static func filteredLiveBenchmarkFixtures() throws -> [TranscriptCleanupBenchmarkFixture] {
        let fixtures = try loadHybridProductFixtures()
        let filterIDs = liveBenchmarkFilterIDs
        guard !filterIDs.isEmpty else { return fixtures }
        return fixtures.filter { filterIDs.contains($0.id) }
    }

    private static var liveBenchmarkFilterIDs: Set<String> {
        guard let contents = try? String(contentsOf: liveBenchmarkMarkerURL, encoding: .utf8) else {
            return []
        }

        return Set(contents.split { $0.isWhitespace }.map(String.init))
    }

    private static var liveBenchmarkMarkerURL: URL {
        hybridProductSuiteURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".run-live-benchmark")
    }

    private static var hybridProductSuiteURL: URL {
        let testFile = URL(fileURLWithPath: #filePath)
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Benchmarks/TranscriptCleanup/suites/hybrid_product.jsonl")
    }
}

private struct TranscriptCleanupBenchmarkDecodeError: Error, CustomStringConvertible {
    let line: Int
    let underlyingError: Error

    var description: String {
        "Could not decode transcript cleanup benchmark line \(line): \(underlyingError)"
    }
}

private struct TranscriptCleanupBenchmarkFixture: Decodable {
    let id: String
    let context: String
    let raw: String
    let assertions: TranscriptCleanupBenchmarkAssertions

    var hasKnownContext: Bool {
        ["code", "email", "prose", "terminal"].contains(context)
    }

    var transcription: TranscriptionProviderResult {
        TranscriptionProviderResult(
            rawText: raw,
            metadata: TranscriptionMetadata(provider: .local, speechModelID: "benchmark", language: "en")
        )
    }

    var contextSnapshot: CleanupContextSnapshot {
        switch context {
        case "code":
            return CleanupContextSnapshot(
                profile: .code,
                bundleIdentifier: "com.microsoft.VSCode",
                appName: "Visual Studio Code",
                isTerminalApp: false,
                isKnownCodeEditor: true,
                language: "en"
            )
        case "terminal":
            return CleanupContextSnapshot(
                profile: .code,
                bundleIdentifier: "com.apple.Terminal",
                appName: "Terminal",
                isTerminalApp: true,
                isKnownCodeEditor: false,
                language: "en"
            )
        case "email":
            return CleanupContextSnapshot(
                profile: .prose,
                bundleIdentifier: "com.apple.mail",
                appName: "Mail",
                isTerminalApp: false,
                isKnownCodeEditor: false,
                language: "en"
            )
        default:
            return CleanupContextSnapshot(
                profile: .prose,
                bundleIdentifier: nil,
                appName: nil,
                isTerminalApp: false,
                isKnownCodeEditor: false,
                language: "en"
            )
        }
    }

    func failures(for result: CleanupResult) -> [String] {
        assertions.failures(
            output: result.finalText,
            raw: raw
        ).map { assertionFailure in
            """
            \(id): \(assertionFailure)
              route: \(result.route.rawValue)
              fallback: \(result.fallbackReason?.rawValue ?? "none")
              output: \(result.finalText.debugSingleLine)
            """
        }
    }
}

private struct TranscriptCleanupBenchmarkAssertions: Decodable {
    let contains: [String]
    let containsAny: [[String]]
    let notContains: [String]
    let maxOccurrences: [String: Int]
    let minWordRatio: Double?

    enum CodingKeys: String, CodingKey {
        case contains
        case containsAny = "contains_any"
        case notContains = "not_contains"
        case maxOccurrences = "max_occurrences"
        case minWordRatio = "min_word_ratio"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contains = try container.decodeIfPresent([String].self, forKey: .contains) ?? []
        containsAny = try container.decodeIfPresent([[String]].self, forKey: .containsAny) ?? []
        notContains = try container.decodeIfPresent([String].self, forKey: .notContains) ?? []
        maxOccurrences = try container.decodeIfPresent([String: Int].self, forKey: .maxOccurrences) ?? [:]
        minWordRatio = try container.decodeIfPresent(Double.self, forKey: .minWordRatio)
    }

    var isEmpty: Bool {
        contains.isEmpty &&
            containsAny.isEmpty &&
            notContains.isEmpty &&
            maxOccurrences.isEmpty &&
            minWordRatio == nil
    }

    func failures(output: String, raw: String) -> [String] {
        var failures: [String] = []

        for fragment in contains where !output.contains(fragment) {
            failures.append("missing required fragment \(fragment.debugSingleLine)")
        }

        for alternatives in containsAny where !alternatives.contains(where: output.contains) {
            let formattedAlternatives = alternatives
                .map(\.debugSingleLine)
                .joined(separator: " | ")
            failures.append("missing one of required fragments \(formattedAlternatives)")
        }

        for fragment in notContains where output.contains(fragment) {
            failures.append("contained forbidden fragment \(fragment.debugSingleLine)")
        }

        for (fragment, maximum) in maxOccurrences {
            let actual = output.occurrenceCount(of: fragment)
            if actual > maximum {
                failures.append("fragment \(fragment.debugSingleLine) occurred \(actual)x, expected <= \(maximum)x")
            }
        }

        if let minWordRatio {
            let rawWordCount = max(1, raw.benchmarkWordCount)
            let outputWordCount = output.benchmarkWordCount
            let ratio = Double(outputWordCount) / Double(rawWordCount)
            if ratio < minWordRatio {
                failures.append(
                    "word ratio \(String(format: "%.2f", ratio)) was below \(String(format: "%.2f", minWordRatio))"
                )
            }
        }

        return failures
    }
}

private extension String {
    var debugSingleLine: String {
        replacingOccurrences(of: "\n", with: "\\n")
    }

    var benchmarkWordCount: Int {
        split { !$0.isLetter && !$0.isNumber }.count
    }

    func occurrenceCount(of needle: String) -> Int {
        guard !needle.isEmpty else { return 0 }

        var count = 0
        var searchRange = startIndex..<endIndex
        while let range = range(of: needle, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<endIndex
        }
        return count
    }
}

private actor StubCleanupModelRunner: CleanupModelRunner {
    nonisolated let manifest = CleanupModelManifest(
        id: "stub-cleanup-model",
        runtime: "test",
        promptVersion: "stub-v1",
        quantization: nil,
        sha256: nil,
        minimumMemoryGB: 0,
        recommendedMemoryGB: 0,
        supportedRoutes: [.modelEligible, .formatting],
        supportedLocales: ["en"],
        bundlePath: "stub",
        benchmarkBaselineID: nil
    )
    nonisolated let output: String
    private var currentState: CleanupModelState = .unloaded

    init(output: String) {
        self.output = output
    }

    func load() async throws {
        currentState = .loaded
    }

    func prewarm() async throws {
        currentState = .ready
    }

    func state() async -> CleanupModelState {
        currentState
    }

    func clean(_ request: CleanupModelRequest) async throws -> CleanupModelCandidate {
        CleanupModelCandidate(
            text: output,
            modelID: manifest.id,
            promptVersion: manifest.promptVersion,
            latencyMilliseconds: 1,
            timedOut: false
        )
    }

    func cancel() async {}
}
