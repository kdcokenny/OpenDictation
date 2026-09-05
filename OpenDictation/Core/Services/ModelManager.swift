import Foundation
import os.log
import Combine
import CryptoKit
import Network

/// Manages Whisper model downloads, storage, and lifecycle.
/// Handles bundled model copy on first launch, model downloads from Hugging Face,
/// and model deletion.
/// Adapted from VoiceInk/Whisper/WhisperState+LocalModelManager.swift
@MainActor
final class ModelManager: ObservableObject {
    private static let stalePartialFileAge: TimeInterval = 24 * 60 * 60
    
    // MARK: - Singleton
    
    static let shared = ModelManager()
    
    // MARK: - Published State
    
    /// Models that have been downloaded and are available for use
    @Published private(set) var downloadedModels: [DownloadedModel] = []
    
    /// Currently selected model name
    @Published var selectedModelName: String {
        didSet {
            UserDefaults.standard.set(selectedModelName, forKey: "selectedLocalModel")
        }
    }
    
    /// Download progress for models being downloaded (model name -> progress 0-1)
    @Published private(set) var downloadProgress: [String: Double] = [:]

    /// The latest user-visible download or validation error for each model.
    @Published private(set) var downloadErrors: [String: String] = [:]
    
    /// Whether user has manually overridden automatic model selection
    @Published var isManualModelOverride: Bool {
        didSet {
            UserDefaults.standard.set(isManualModelOverride, forKey: "isManualModelOverride")
        }
    }
    
    // MARK: - Properties
    
    private let logger = Logger.app(category: "ModelManager")
    
    /// Directory where models are stored
    let modelsDirectory: URL
    
    /// Active downloaders (for progress tracking and cancellation)
    private var activeDownloaders: [String: ModelDownloader] = [:]

    private let models: [WhisperModel]
    private var initialModelScanTask: Task<ModelDirectoryScan, Never>?
    private var didFinishInitialModelScan = false
    private var modelStateGeneration = 0

    private var bundledModel: WhisperModel {
        guard let model = models.first(where: { $0.isBundled }) else {
            preconditionFailure("ModelManager requires one bundled model definition.")
        }
        return model
    }
    
    /// Network path monitor for Wi-Fi detection (used for synchronous currentPath access)
    private let networkMonitor = NWPathMonitor()
    
    // MARK: - Initialization
    
    internal init(
        modelsDirectory: URL? = nil,
        models: [WhisperModel] = PredefinedModels.all
    ) {
        self.models = models
        if let customDir = modelsDirectory {
            self.modelsDirectory = customDir
        } else {
            // Set up models directory in Application Support
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.modelsDirectory = appSupport
                .appendingPathComponent("com.opendictation", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        }
        
        // Load selected model from UserDefaults
        let defaultModelName = models.first(where: { $0.isBundled })?.name
            ?? PredefinedModels.bundled.name
        selectedModelName = UserDefaults.standard.string(forKey: "selectedLocalModel")
            ?? defaultModelName
        
        // Load manual override preference
        isManualModelOverride = UserDefaults.standard.bool(forKey: "isManualModelOverride")
        
        // Validate installed models away from the main actor. Until this finishes,
        // the published list stays empty and no unverified model is considered ready.
        createModelsDirectoryIfNeeded()
        removeOrphanedPartialFiles()
        let directory = self.modelsDirectory
        let modelCatalog = self.models
        initialModelScanTask = Task.detached(priority: .utility) {
            ModelDirectoryScanner.scan(directory: directory, models: modelCatalog)
        }
        
        // Start network monitoring for Wi-Fi detection
        startNetworkMonitoring()

        Task { @MainActor [weak self] in
            await self?.finishInitialModelScan()
        }
    }
    
    /// Validates that the selected model file actually exists on disk.
    /// If not, falls back to the bundled model to ensure dictation always works.
    /// Apple philosophy: default state should always be functional.
    internal func validateSelectedModelExists() {
        guard didFinishInitialModelScan else { return }

        if downloadedModels.contains(where: { $0.name == selectedModelName }) {
            return
        }
        
        // If no models exist, this is expected first-launch state
        // The bundled model will be copied shortly by setupBundledModelIfNeeded()
        guard !downloadedModels.isEmpty else {
            logger.debug("No models yet - expected on first launch")
            return
        }
        
        // Models exist but selected one is missing - fall back to bundled
        let bundledName = bundledModel.name
        if downloadedModels.contains(where: { $0.name == bundledName }) {
            logger.info("Selected model '\(self.selectedModelName)' not found, falling back to '\(bundledName)'")
            selectedModelName = bundledName
            // Clear manual override since the model they selected is gone
            isManualModelOverride = false
        } else if let firstModel = downloadedModels.first {
            // Bundled also missing - use any available model
            logger.info("Falling back to available model: \(firstModel.name)")
            selectedModelName = firstModel.name
            isManualModelOverride = false
        }
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Network Monitoring
    
    /// Starts network monitoring so currentPath is available for synchronous checks.
    /// Pattern from Firebase ReachabilityHelper: https://github.com/firebase/quickstart-ios
    private func startNetworkMonitoring() {
        networkMonitor.start(queue: DispatchQueue(label: "com.opendictation.networkmonitor"))
    }
    
    /// Checks current network status synchronously using NWPathMonitor.currentPath.
    /// Returns true if connected via Wi-Fi or Ethernet (not cellular/expensive).
    /// This avoids race conditions with async callbacks at app launch.
    ///
    /// Safety: If the path status is not `.satisfied`, we conservatively return false.
    /// This handles edge cases like:
    /// - Monitor just started and hasn't received first update yet
    /// - Captive portal (`.requiresConnection`)
    /// - No network (`.unsatisfied`)
    ///
    /// Pattern from: https://github.com/openhab/openhab-ios, https://github.com/damus-io/damus
    private var isOnWiFi: Bool {
        let path = networkMonitor.currentPath
        
        // Must be fully connected (not captive portal or disconnected)
        guard path.status == .satisfied else {
            logger.debug("[Network] Status not satisfied: \(String(describing: path.status))")
            return false
        }
        
        // Must be on Wi-Fi or wired Ethernet (not cellular)
        let onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        logger.debug("[Network] Wi-Fi/Ethernet: \(onWiFi)")
        return onWiFi
    }
    
    // MARK: - Directory Management
    
    private func createModelsDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            logger.info("Models directory: \(self.modelsDirectory.path)")
        } catch {
            logger.error("Failed to create models directory: \(error.localizedDescription)")
        }
    }

    /// Remove old staging files at startup. The age guard avoids touching a file
    /// that another app instance may still be validating.
    private func removeOrphanedPartialFiles() {
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]
        ) else { return }

        for url in fileURLs where url.pathExtension == "partial" {
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            )
            guard values?.isRegularFile == true,
                  let modifiedAt = values?.contentModificationDate,
                  Date().timeIntervalSince(modifiedAt) >= Self.stalePartialFileAge else {
                continue
            }
            do {
                try FileManager.default.removeItem(at: url)
                logger.info("Removed stale model staging file: \(url.lastPathComponent)")
            } catch {
                logger.warning("Couldn't remove stale model staging file: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Model Loading

    /// Waits until every model discovered at launch has passed size and checksum validation.
    /// Call this before reading model availability for a transcription decision.
    func waitForInitialScan() async {
        await finishInitialModelScan()
    }
    
    /// Rescans installed models without blocking the main actor on file hashes.
    func loadDownloadedModels() async {
        await waitForInitialScan()

        let directory = modelsDirectory
        let modelCatalog = models
        let generation = modelStateGeneration
        let scan = await Task.detached(priority: .utility) {
            ModelDirectoryScanner.scan(directory: directory, models: modelCatalog)
        }.value
        guard generation == modelStateGeneration else { return }
        apply(scan)
    }

    private func finishInitialModelScan() async {
        guard !didFinishInitialModelScan, let task = initialModelScanTask else { return }
        let scan = await task.value
        guard !didFinishInitialModelScan else { return }

        apply(scan)
        didFinishInitialModelScan = true
        initialModelScanTask = nil
        validateSelectedModelExists()
    }

    private func apply(_ scan: ModelDirectoryScan) {
        downloadedModels = scan.downloadedModels
        for model in scan.downloadedModels {
            downloadErrors.removeValue(forKey: model.name)
        }
        for (name, message) in scan.validationErrors {
            downloadErrors[name] = message
            logger.error("Ignoring invalid model \(name): \(message)")
        }
        for filename in scan.unrecognizedFiles {
            logger.warning("Ignoring unrecognized model file: \(filename)")
        }
        if let directoryError = scan.directoryError {
            logger.error("Failed to load downloaded models: \(directoryError)")
        }
        logger.info("Found \(self.downloadedModels.count) downloaded models")
    }
    
    /// Checks if a model is downloaded.
    func isDownloaded(_ model: WhisperModel) -> Bool {
        downloadedModels.contains { $0.name == model.name }
    }
    
    /// Returns the currently selected model, if downloaded.
    var selectedModel: DownloadedModel? {
        downloadedModels.first { $0.name == selectedModelName }
    }
    
    // MARK: - First-Run Setup
    
    /// Copies the bundled model from app bundle to Application Support on first launch.
    /// This enables instant first-run experience.
    func setupBundledModelIfNeeded() async {
        await waitForInitialScan()
        let bundledModel = self.bundledModel
        
        // Skip only after validating the installed copy.
        let destinationURL = modelsDirectory.appendingPathComponent(bundledModel.filename)
        guard !isDownloaded(bundledModel) else {
            logger.debug("Bundled model already exists at \(destinationURL.path)")
            return
        }
        
        // Look for bundled model in app resources
        // For SPM, use Bundle.module; for app bundle, use Bundle.main
        let possibleBundles = [Bundle.module, Bundle.main]
        var sourceURL: URL?
        
        for bundle in possibleBundles {
            // Try direct resource lookup
            if let url = bundle.url(forResource: bundledModel.name, withExtension: "bin") {
                sourceURL = url
                break
            }
            
            // Try Models subdirectory
            if let url = bundle.url(forResource: bundledModel.name, withExtension: "bin", subdirectory: "Models") {
                sourceURL = url
                break
            }
        }
        
        guard let sourceURL = sourceURL else {
            logger.warning("Bundled model '\(bundledModel.name)' not found in any bundle")
            return
        }
        
        let temporaryURL = modelsDirectory
            .appendingPathComponent(".\(bundledModel.filename).\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: temporaryURL)
            try await ModelFileValidator.validateAsync(fileAt: temporaryURL, for: bundledModel)
            try installValidatedModel(from: temporaryURL, to: destinationURL)
            logger.info("Copied bundled model '\(bundledModel.name)' to \(destinationURL.path)")
            recordInstalledModel(bundledModel, at: destinationURL)
            validateSelectedModelExists()
        } catch {
            logger.error("Failed to copy bundled model: \(error.localizedDescription)")
            downloadErrors[bundledModel.name] = error.localizedDescription
        }
    }
    
    // MARK: - Model Download
    
    /// Downloads a model from Hugging Face.
    /// Progress is reported via the `downloadProgress` published property.
    func downloadModel(_ model: WhisperModel) async throws {
        await waitForInitialScan()
        guard let url = URL(string: model.downloadURL),
              url.scheme == "https",
              url.host != nil else {
            let error = ModelDownloadError.invalidURL(model.downloadURL)
            recordDownloadFailure(error, for: model.name)
            throw error
        }
        
        // Skip if already downloaded
        guard !isDownloaded(model) else {
            logger.info("Model \(model.name) already downloaded")
            return
        }
        
        // Check if already downloading
        guard activeDownloaders[model.name] == nil else {
            throw ModelDownloadError.alreadyDownloading(model.name)
        }
        
        logger.info("Starting download of \(model.name) from \(model.downloadURL)")
        downloadProgress[model.name] = 0
        downloadErrors.removeValue(forKey: model.name)
        
        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        
        // Create downloader with delegate-based progress tracking
        let downloader = ModelDownloader(temporaryDirectory: modelsDirectory)
        activeDownloaders[model.name] = downloader
        
        // Set up progress handler (throttled by ModelDownloader)
        downloader.progressHandler = { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress[model.name] = progress
            }
        }
        
        // Start download and wait for completion
        defer {
            activeDownloaders.removeValue(forKey: model.name)
            downloadProgress.removeValue(forKey: model.name)
        }

        do {
            let temporaryURL = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    downloader.completionHandler = { tempURL, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let tempURL {
                            continuation.resume(returning: tempURL)
                        } else {
                            continuation.resume(throwing: ModelDownloadError.missingTemporaryFile)
                        }
                    }
                    downloader.start(url: url)
                }
            } onCancel: {
                Task { @MainActor in
                    downloader.cancel()
                }
            }

            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try Task.checkCancellation()
            try await ModelFileValidator.validateAsync(fileAt: temporaryURL, for: model)
            try Task.checkCancellation()
            try installValidatedModel(from: temporaryURL, to: destinationURL)

            logger.info("Downloaded \(model.name) to \(destinationURL.path)")
            recordInstalledModel(model, at: destinationURL)
        } catch {
            recordDownloadFailure(error, for: model.name)
            throw error
        }
    }

    private func installValidatedModel(from temporaryURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func recordDownloadFailure(_ error: Error, for modelName: String) {
        logger.error("Failed to download \(modelName): \(error.localizedDescription)")
        downloadErrors[modelName] = error.localizedDescription
    }

    private func recordInstalledModel(_ model: WhisperModel, at url: URL) {
        modelStateGeneration += 1
        downloadedModels.removeAll { $0.name == model.name }
        downloadedModels.append(DownloadedModel(name: model.name, url: url))
        downloadErrors.removeValue(forKey: model.name)
    }
    
    // MARK: - Auto Model Selection
    
    /// Returns the system-recommended model name based on hardware and current language.
    /// Uses UserDefaults "language" setting to determine optimal model.
    var recommendedModelName: String {
        let language = UserDefaults.standard.string(forKey: "language") ?? "auto"
        return SystemCapabilities.current.recommendedModelName(forLanguage: language)
    }
    
    /// Whether the currently selected model matches the system recommendation.
    var isUsingRecommendedModel: Bool {
        selectedModelName == recommendedModelName
    }
    
    /// Returns the currently selected model definition, if found.
    var currentModel: WhisperModel? {
        models.first { $0.name == selectedModelName }
    }
    
    /// Checks if the current model supports the given language.
    func currentModelSupportsLanguage(_ languageCode: String) -> Bool {
        guard let model = currentModel else {
            logger.error("Selected model definition not found: \(self.selectedModelName)")
            return false
        }
        return model.supportsLanguage(languageCode)
    }
    
    /// Checks if a specific model is downloaded by name.
    /// Reference: https://github.com/argmaxinc/WhisperKit/blob/main/Examples/WhisperAX/WhisperAX/Views/ContentView.swift#L984
    func isModelDownloaded(_ modelName: String) -> Bool {
        downloadedModels.contains { $0.name == modelName }
    }
    
    /// Checks if an upgrade is needed and starts silent download if on Wi-Fi.
    /// Called from AppDelegate on launch.
    ///
    /// Flow:
    /// 1. Skip if user has manual override
    /// 2. Detect system capabilities
    /// 3. Compare recommended model to current
    /// 4. If different and not downloaded and on Wi-Fi → start silent download
    func checkAndUpgradeIfNeeded() async {
        await waitForInitialScan()

        // Skip if user has explicitly chosen a model
        guard !isManualModelOverride else {
            logger.debug("[AutoSelect] Skipping: manual override active")
            return
        }
        
        // Get cached system capabilities
        let capabilities = SystemCapabilities.current
        let recommended = capabilities.recommendedModelName
        
        logger.debug("[AutoSelect] System: RAM=\(capabilities.ramGB)GB, Chip=\(capabilities.chipGeneration.rawValue)")
        logger.debug("[AutoSelect] Current=\(self.selectedModelName), Recommended=\(recommended)")
        
        // Check if recommended model is downloaded
        let recommendedIsDownloaded = isModelDownloaded(recommended)
        
        // If already using recommended AND it's downloaded, we're good
        if selectedModelName == recommended && recommendedIsDownloaded {
            logger.debug("[AutoSelect] Already using recommended model")
            return
        }
        
        // If recommended is downloaded but not selected, just switch to it
        if recommendedIsDownloaded {
            logger.info("[AutoSelect] Switching to recommended model")
            applyRecommendedModel()
            return
        }
        
        // Skip if not on Wi-Fi (respect user data plans)
        guard isOnWiFi else {
            logger.debug("[AutoSelect] Deferring download: not on Wi-Fi")
            return
        }
        
        // Find the model definition
        guard let model = PredefinedModels.find(byName: recommended) else {
            logger.warning("[AutoSelect] Model '\(recommended)' not found in predefined models")
            return
        }
        
        // Start silent download
        logger.info("[AutoSelect] Starting background download: \(recommended) (\(model.size))")
        await downloadModelSilently(model)
    }
    
    /// Downloads a model silently (no UI alerts) for auto-upgrade.
    /// On completion, automatically switches to the new model.
    private func downloadModelSilently(_ model: WhisperModel) async {
        do {
            try await downloadModel(model)
        } catch {
            logger.error("Background model download failed: \(error.localizedDescription)")
            return
        }
        
        // If download succeeded and we're still in auto mode, switch to new model
        if isModelDownloaded(model.name) && !isManualModelOverride {
            logger.info("[AutoSelect] Download completed, switching to \(model.name)")
            applyRecommendedModel()
        } else if !isModelDownloaded(model.name) {
            logger.warning("[AutoSelect] Download failed or was cancelled")
        }
    }
    
    /// Switches to the recommended model.
    /// Called after successful auto-upgrade download.
    func applyRecommendedModel() {
        let recommended = recommendedModelName
        guard isModelDownloaded(recommended) else {
            logger.warning("[AutoSelect] Cannot apply '\(recommended)': not downloaded")
            return
        }
        
        selectedModelName = recommended
        logger.info("[AutoSelect] Now using: \(recommended)")
    }
    
    /// Resets to automatic model selection.
    /// Clears manual override and triggers upgrade check.
    func resetToAutomatic() async {
        isManualModelOverride = false
        await checkAndUpgradeIfNeeded()
    }
    
    // MARK: - Language-Aware Model Selection
    
    /// Handles a language change by ensuring an appropriate model is available.
    /// Apple philosophy: Works immediately, optimizes in background.
    ///
    /// Flow:
    /// 1. If current model supports language → no action needed
    /// 2. If not, and user has manual override → just warn (they're advanced users)
    /// 3. If not, and auto mode:
    ///    a. Immediately fall back to bundled multilingual model (instant, always works)
    ///    b. Download optimal model for this language in background (if on WiFi)
    ///
    /// - Parameter languageCode: The new language code (e.g., "en", "es", "auto")
    /// - Returns: Whether the current model supports the language (for UI warnings)
    @discardableResult
    func handleLanguageChange(to languageCode: String) async -> Bool {
        await waitForInitialScan()
        logger.info("[LanguageChange] Language changed to: \(languageCode)")
        
        // Check if current model supports this language
        guard let currentModel = currentModel else {
            logger.debug("[LanguageChange] No current model, skipping")
            return true
        }
        
        let isSupported = currentModel.supportsLanguage(languageCode)
        
        if isSupported {
            logger.info("[LanguageChange] Current model '\(currentModel.name)' supports '\(languageCode)'")
            
            // Even if supported, check if we should upgrade to a better model
            // (e.g., switching to English might benefit from .en model)
            if !isManualModelOverride {
                await checkForLanguageOptimizedUpgrade(languageCode)
            }
            return true
        }
        
        // Current model doesn't support this language
        logger.info("[LanguageChange] Current model '\(currentModel.name)' doesn't support '\(languageCode)'")
        
        // If manual override, just return false (UI will show warning)
        if isManualModelOverride {
            logger.info("[LanguageChange] Manual override active - user will see warning")
            return false
        }
        
        // Auto mode: fall back to bundled multilingual model immediately
        let bundledName = bundledModel.name
        logger.info("[LanguageChange] Falling back to bundled model: \(bundledName)")
        selectedModelName = bundledName
        
        // Then download optimal model in background
        await downloadOptimalModelForLanguage(languageCode)
        
        return true // After fallback, we support the language
    }
    
    /// Downloads the optimal model for a language in background (if on WiFi).
    /// Called after falling back to bundled model.
    private func downloadOptimalModelForLanguage(_ languageCode: String) async {
        // Skip if manual override
        guard !isManualModelOverride else { return }
        
        // Get recommended model for this language
        let recommended = SystemCapabilities.current.recommendedModelName(forLanguage: languageCode)
        
        // Skip if already downloaded
        guard !isModelDownloaded(recommended) else {
            logger.info("[LanguageChange] Optimal model '\(recommended)' already downloaded, switching")
            selectedModelName = recommended
            return
        }
        
        // Skip if not on Wi-Fi
        guard isOnWiFi else {
            logger.info("[LanguageChange] Not on Wi-Fi, skipping background download")
            return
        }
        
        // Find model definition
        guard let model = PredefinedModels.find(byName: recommended) else {
            logger.warning("[LanguageChange] Model '\(recommended)' not found in predefined models")
            return
        }
        
        // Download in background
        logger.info("[LanguageChange] Starting background download of '\(recommended)'")
        await downloadModelSilently(model)
    }
    
    /// Checks if we should upgrade to a language-optimized model.
    /// E.g., switching to English might benefit from .en model.
    private func checkForLanguageOptimizedUpgrade(_ languageCode: String) async {
        let recommended = SystemCapabilities.current.recommendedModelName(forLanguage: languageCode)
        
        // If we're already using the recommended model, nothing to do
        if selectedModelName == recommended {
            return
        }
        
        // If recommended is downloaded, switch to it
        if isModelDownloaded(recommended) {
            logger.info("[LanguageChange] Switching to better model for '\(languageCode)': \(recommended)")
            selectedModelName = recommended
            return
        }
        
        // If on WiFi, download the better model
        if isOnWiFi {
            guard let model = PredefinedModels.find(byName: recommended) else { return }
            logger.info("[LanguageChange] Downloading better model for '\(languageCode)': \(recommended)")
            await downloadModelSilently(model)
        }
    }
}

// MARK: - Model Validation

struct ModelDirectoryScan: Sendable {
    let downloadedModels: [DownloadedModel]
    let validationErrors: [String: String]
    let unrecognizedFiles: [String]
    let directoryError: String?
}

enum ModelDirectoryScanner {
    static func scan(directory: URL, models: [WhisperModel]) -> ModelDirectoryScan {
        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            return ModelDirectoryScan(
                downloadedModels: [],
                validationErrors: [:],
                unrecognizedFiles: [],
                directoryError: error.localizedDescription
            )
        }

        var downloadedModels: [DownloadedModel] = []
        var validationErrors: [String: String] = [:]
        var unrecognizedFiles: [String] = []

        for url in fileURLs where url.pathExtension == "bin" {
            let name = url.deletingPathExtension().lastPathComponent
            guard let model = models.first(where: { $0.name == name }) else {
                unrecognizedFiles.append(url.lastPathComponent)
                continue
            }

            do {
                try ModelFileValidator.validate(fileAt: url, for: model)
                downloadedModels.append(DownloadedModel(name: name, url: url))
            } catch {
                validationErrors[name] = error.localizedDescription
            }
        }

        return ModelDirectoryScan(
            downloadedModels: downloadedModels,
            validationErrors: validationErrors,
            unrecognizedFiles: unrecognizedFiles,
            directoryError: nil
        )
    }
}

enum ModelDownloadError: LocalizedError {
    case invalidURL(String)
    case alreadyDownloading(String)
    case invalidHTTPStatus(Int)
    case responseSizeMismatch(expected: Int64, actual: Int64)
    case missingTemporaryFile

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid model download URL: \(url)"
        case .alreadyDownloading(let name):
            return "Model '\(name)' is already downloading."
        case .invalidHTTPStatus(let status):
            return "Model server returned HTTP \(status)."
        case .responseSizeMismatch(let expected, let actual):
            return "Model response size mismatch. Expected \(expected) bytes, received \(actual)."
        case .missingTemporaryFile:
            return "Model download finished without a temporary file."
        }
    }
}

enum ModelValidationError: LocalizedError, Equatable {
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .sizeMismatch(let expected, let actual):
            return "Model size mismatch. Expected \(expected) bytes, found \(actual)."
        case .checksumMismatch(let expected, let actual):
            return "Model checksum mismatch. Expected \(expected), found \(actual)."
        }
    }
}

enum ModelFileValidator {
    private static let readChunkSize = 1_048_576

    static func validateAsync(fileAt url: URL, for model: WhisperModel) async throws {
        let task = Task.detached(priority: .utility) {
            try validate(fileAt: url, for: model, checkingCancellation: true)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func validate(
        fileAt url: URL,
        for model: WhisperModel,
        checkingCancellation: Bool = false
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualByteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualByteCount == model.expectedByteCount else {
            throw ModelValidationError.sizeMismatch(
                expected: model.expectedByteCount,
                actual: actualByteCount
            )
        }

        let actualSHA256 = try sha256(
            fileAt: url,
            checkingCancellation: checkingCancellation
        )
        guard actualSHA256 == model.sha256.lowercased() else {
            throw ModelValidationError.checksumMismatch(
                expected: model.sha256.lowercased(),
                actual: actualSHA256
            )
        }
    }

    static func sha256(
        fileAt url: URL,
        checkingCancellation: Bool = false
    ) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }

        var hasher = SHA256()
        while let data = try file.read(upToCount: readChunkSize), !data.isEmpty {
            if checkingCancellation {
                try Task.checkCancellation()
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum ModelDownloadResponseValidator {
    static func validate(_ response: URLResponse?, fileAt url: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw ModelDownloadError.invalidHTTPStatus(status)
        }

        guard httpResponse.expectedContentLength > 0 else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let actualByteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard actualByteCount == httpResponse.expectedContentLength else {
            throw ModelDownloadError.responseSizeMismatch(
                expected: httpResponse.expectedContentLength,
                actual: actualByteCount
            )
        }
    }
}

// MARK: - Model Downloader

/// Apple-native download handler using URLSessionDownloadDelegate.
/// Provides reliable progress tracking without KVO lifecycle issues.
/// Pattern from OpenEmu and other polished macOS apps.
@MainActor
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    
    /// Called when progress updates (throttled to ≥1% change)
    var progressHandler: ((Double) -> Void)?
    
    /// Called when download completes (with temp file URL) or fails (with error)
    var completionHandler: ((URL?, Error?) -> Void)?
    
    private var downloadSession: URLSession?
    private var currentProgress: Double = 0

    private nonisolated let temporaryDirectory: URL

    init(temporaryDirectory: URL) {
        self.temporaryDirectory = temporaryDirectory
    }
    
    /// Starts downloading from the given URL.
    /// Uses Apple's URLSession Wi-Fi-only configuration as a safety net.
    /// Pattern from Cheetah Whisper downloader: https://github.com/leetcode-mafia/cheetah
    func start(url: URL) {
        currentProgress = 0
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600 // 10 minutes for large models
        
        // Apple-style Wi-Fi only: won't use cellular or hotspot
        // Respects user's "Low Data Mode" setting automatically
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        
        // Key: delegate on main queue for UI updates
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        session.sessionDescription = url.lastPathComponent
        self.downloadSession = session
        
        let task = session.downloadTask(with: url)
        task.resume()
    }
    
    /// Cancels the download.
    func cancel() {
        downloadSession?.invalidateAndCancel()
        downloadSession = nil
    }
    
    // MARK: - URLSessionDownloadDelegate
    // Note: These are nonisolated to satisfy protocol requirements, but they're called on main queue
    // (via delegateQueue: .main) so we use MainActor.assumeIsolated for safe access to our properties.
    
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        
        guard totalBytesExpectedToWrite > 0 else { return }
        
        let newProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        MainActor.assumeIsolated {
            // Throttle: only update if progress changed by ≥1%
            if abs(newProgress - self.currentProgress) >= 0.01 {
                self.currentProgress = newProgress
                self.progressHandler?(newProgress)
            }
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try ModelDownloadResponseValidator.validate(downloadTask.response, fileAt: location)
        } catch {
            MainActor.assumeIsolated {
                self.finish(with: nil, error: error)
            }
            return
        }

        // Move to a safe location before the delegate method returns
        // (Apple deletes the temp file after this method returns)
        let safeURL = temporaryDirectory
            .appendingPathComponent(".\(UUID().uuidString).partial")
        
        do {
            try FileManager.default.moveItem(at: location, to: safeURL)
            MainActor.assumeIsolated {
                self.finish(with: safeURL, error: nil)
            }
        } catch {
            MainActor.assumeIsolated {
                self.finish(with: nil, error: error)
            }
        }
    }
    
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        
        MainActor.assumeIsolated {
            if let error = error {
                self.finish(with: nil, error: error)
            }
        }
    }

    private func finish(with url: URL?, error: Error?) {
        guard let completionHandler else { return }
        self.completionHandler = nil
        completionHandler(url, error)
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
    }
}
