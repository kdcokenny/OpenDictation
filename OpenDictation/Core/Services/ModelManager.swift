import Foundation
import os.log
import Combine
import Network

/// Manages Whisper model downloads, storage, and lifecycle.
/// Handles bundled model copy on first launch, model downloads from Hugging Face,
/// and model deletion.
/// Adapted from VoiceInk/Whisper/WhisperState+LocalModelManager.swift
@MainActor
final class ModelManager: ObservableObject {
    
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
    
    /// Network path monitor for Wi-Fi detection (used for synchronous currentPath access)
    private let networkMonitor = NWPathMonitor()
    
    // MARK: - Initialization
    
    private init() {
        // Set up models directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelsDirectory = appSupport
            .appendingPathComponent("com.opendictation", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        
        // Load selected model from UserDefaults
        selectedModelName = UserDefaults.standard.string(forKey: "selectedLocalModel")
            ?? PredefinedModels.bundled.name
        
        // Load manual override preference
        isManualModelOverride = UserDefaults.standard.bool(forKey: "isManualModelOverride")
        
        // Create directory and load available models
        createModelsDirectoryIfNeeded()
        loadDownloadedModels()
        
        // Validate selected model exists - fall back to bundled if not (Apple-style: always functional)
        validateSelectedModelExists()
        
        // Start network monitoring for Wi-Fi detection
        startNetworkMonitoring()
    }
    
    /// Validates that the selected model file actually exists on disk.
    /// If not, falls back to the bundled model to ensure dictation always works.
    /// Apple philosophy: default state should always be functional.
    private func validateSelectedModelExists() {
        let selectedPath = modelsDirectory.appendingPathComponent("\(selectedModelName).bin").path
        
        // If selected model exists, we're good
        if FileManager.default.fileExists(atPath: selectedPath) {
            return
        }
        
        // Check if ANY models exist in the directory
        let hasAnyModels = (try? FileManager.default.contentsOfDirectory(atPath: modelsDirectory.path))?
            .contains { $0.hasSuffix(".bin") } ?? false
        
        // If no models exist, this is expected first-launch state
        // The bundled model will be copied shortly by setupBundledModelIfNeeded()
        guard hasAnyModels else {
            logger.debug("No models yet - expected on first launch")
            return
        }
        
        // Models exist but selected one is missing - fall back to bundled
        let bundledName = PredefinedModels.bundled.name
        let bundledPath = modelsDirectory.appendingPathComponent("\(bundledName).bin").path
        
        if FileManager.default.fileExists(atPath: bundledPath) {
            logger.info("Selected model '\(self.selectedModelName)' not found, falling back to '\(bundledName)'")
            selectedModelName = bundledName
            // Clear manual override since the model they selected is gone
            isManualModelOverride = false
        } else if let firstModel = downloadedModels.first {
            // Bundled also missing - use any available model
            logger.info("Falling back to available model: \(firstModel.name)")
            selectedModelName = firstModel.name
            isManualModelOverride = false
        } else {
            // This shouldn't happen - hasAnyModels was true but downloadedModels is empty
            // Could be non-.bin files in directory. Log for debugging.
            logger.warning("Models directory has files but no valid .bin models found")
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
    
    // MARK: - Model Loading
    
    /// Scans the models directory and updates the list of downloaded models.
    func loadDownloadedModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: nil
            )
            
            downloadedModels = fileURLs.compactMap { url in
                guard url.pathExtension == "bin" else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                return DownloadedModel(name: name, url: url)
            }
            
            logger.info("Found \(self.downloadedModels.count) downloaded models")
        } catch {
            logger.error("Failed to load downloaded models: \(error.localizedDescription)")
            downloadedModels = []
        }
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
        let bundledModel = PredefinedModels.bundled
        
        // Skip if already copied
        let destinationURL = modelsDirectory.appendingPathComponent(bundledModel.filename)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
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
        
        // Copy to Application Support
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            logger.info("Copied bundled model '\(bundledModel.name)' to \(destinationURL.path)")
            loadDownloadedModels()
        } catch {
            logger.error("Failed to copy bundled model: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Model Download
    
    /// Downloads a model from Hugging Face.
    /// Progress is reported via the `downloadProgress` published property.
    func downloadModel(_ model: WhisperModel) async {
        guard let url = URL(string: model.downloadURL) else {
            logger.error("Invalid download URL for \(model.name)")
            return
        }
        
        // Skip if already downloaded
        guard !isDownloaded(model) else {
            logger.info("Model \(model.name) already downloaded")
            return
        }
        
        // Check if already downloading
        guard activeDownloaders[model.name] == nil else {
            logger.info("Model \(model.name) already downloading")
            return
        }
        
        logger.info("Starting download of \(model.name) from \(model.downloadURL)")
        downloadProgress[model.name] = 0
        
        let destinationURL = modelsDirectory.appendingPathComponent(model.filename)
        
        // Create downloader with delegate-based progress tracking
        let downloader = ModelDownloader()
        activeDownloaders[model.name] = downloader
        
        // Set up progress handler (throttled by ModelDownloader)
        downloader.progressHandler = { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress[model.name] = progress
            }
        }
        
        // Start download and wait for completion
        let result = await withCheckedContinuation { continuation in
            downloader.completionHandler = { tempURL, error in
                continuation.resume(returning: (tempURL, error))
            }
            downloader.start(url: url)
        }
        
        // Clean up downloader
        activeDownloaders.removeValue(forKey: model.name)
        
        // Handle result
        if let error = result.1 {
            logger.error("Failed to download \(model.name): \(error.localizedDescription)")
            downloadProgress.removeValue(forKey: model.name)
            return
        }
        
        guard let tempURL = result.0 else {
            logger.error("Download completed but no file received for \(model.name)")
            downloadProgress.removeValue(forKey: model.name)
            return
        }
        
        // Move to final destination
        do {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            logger.info("Downloaded \(model.name) to \(destinationURL.path)")
            downloadProgress.removeValue(forKey: model.name)
            loadDownloadedModels()
        } catch {
            logger.error("Failed to move downloaded file: \(error.localizedDescription)")
            downloadProgress.removeValue(forKey: model.name)
        }
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
        PredefinedModels.find(byName: selectedModelName)
    }
    
    /// Checks if the current model supports the given language.
    func currentModelSupportsLanguage(_ languageCode: String) -> Bool {
        guard let model = currentModel else {
            return true // Unknown model, assume it works
        }
        return model.supportsLanguage(languageCode)
    }
    
    /// Checks if a specific model is downloaded by name.
    /// Reference: https://github.com/argmaxinc/WhisperKit/blob/main/Examples/WhisperAX/WhisperAX/Views/ContentView.swift#L984
    func isModelDownloaded(_ modelName: String) -> Bool {
        let modelPath = modelsDirectory.appendingPathComponent("\(modelName).bin").path
        return FileManager.default.fileExists(atPath: modelPath)
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
        // Use existing download infrastructure but don't show alerts
        await downloadModel(model)
        
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
        let bundledName = PredefinedModels.bundled.name
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
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        
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
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        
        // Move to a safe location before the delegate method returns
        // (Apple deletes the temp file after this method returns)
        let safeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        
        do {
            try FileManager.default.moveItem(at: location, to: safeURL)
            MainActor.assumeIsolated {
                self.completionHandler?(safeURL, nil)
                self.downloadSession?.finishTasksAndInvalidate()
                self.downloadSession = nil
            }
        } catch {
            MainActor.assumeIsolated {
                self.completionHandler?(nil, error)
                self.downloadSession?.finishTasksAndInvalidate()
                self.downloadSession = nil
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        
        MainActor.assumeIsolated {
            if let error = error {
                self.completionHandler?(nil, error)
            }
            
            self.downloadSession?.finishTasksAndInvalidate()
            self.downloadSession = nil
        }
    }
}
