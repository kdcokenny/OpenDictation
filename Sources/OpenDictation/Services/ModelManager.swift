import Foundation
import os.log
import Combine

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
    
    /// Error message from last operation
    @Published private(set) var lastError: String?
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.opendictation", category: "ModelManager")
    
    /// Directory where models are stored
    let modelsDirectory: URL
    
    /// Active downloaders (for progress tracking and cancellation)
    private var activeDownloaders: [String: ModelDownloader] = [:]
    
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
        
        // Create directory and load available models
        createModelsDirectoryIfNeeded()
        loadDownloadedModels()
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
                let isBundled = PredefinedModels.bundled.name == name
                return DownloadedModel(name: name, url: url, isBundled: isBundled)
            }
            
            logger.info("Found \(self.downloadedModels.count) downloaded models")
        } catch {
            logger.error("Failed to load downloaded models: \(error.localizedDescription)")
            downloadedModels = []
        }
    }
    
    /// Returns the URL for a downloaded model by name.
    func modelURL(for name: String) -> URL? {
        downloadedModels.first { $0.name == name }?.url
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
        // Skip if already copied
        let destinationURL = modelsDirectory.appendingPathComponent(PredefinedModels.bundled.filename)
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
            if let url = bundle.url(forResource: "ggml-tiny.en", withExtension: "bin") {
                sourceURL = url
                break
            }
            
            // Try Models subdirectory
            if let url = bundle.url(forResource: "ggml-tiny.en", withExtension: "bin", subdirectory: "Models") {
                sourceURL = url
                break
            }
        }
        
        guard let sourceURL = sourceURL else {
            logger.warning("Bundled model not found in any bundle")
            return
        }
        
        // Copy to Application Support
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            logger.info("Copied bundled model to \(destinationURL.path)")
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
            lastError = "Couldn't download: invalid address"
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
        lastError = nil
        
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
            lastError = "Couldn't download: \(error.localizedDescription)"
            downloadProgress.removeValue(forKey: model.name)
            return
        }
        
        guard let tempURL = result.0 else {
            logger.error("Download completed but no file received for \(model.name)")
            lastError = "Download interrupted. Try again."
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
            lastError = "Couldn't download: \(error.localizedDescription)"
            downloadProgress.removeValue(forKey: model.name)
        }
    }
    
    /// Cancels an in-progress download.
    func cancelDownload(_ model: WhisperModel) {
        activeDownloaders[model.name]?.cancel()
        activeDownloaders.removeValue(forKey: model.name)
        downloadProgress.removeValue(forKey: model.name)
        logger.info("Cancelled download of \(model.name)")
    }
    
    // MARK: - Model Deletion
    
    /// Deletes a downloaded model.
    /// Returns false if deletion would leave no models and cloud mode isn't configured.
    func deleteModel(_ model: DownloadedModel) async -> Bool {
        // Check if this is the last model
        if downloadedModels.count == 1 {
            // Check if cloud mode is available (has API key)
            let hasApiKey = KeychainService.shared.load(KeychainService.Key.apiKey) != nil
            if !hasApiKey {
                lastError = "You need at least one model for offline transcription."
                return false
            }
        }
        
        do {
            try FileManager.default.removeItem(at: model.url)
            logger.info("Deleted model \(model.name)")
            
            // Update selected model if we deleted the selected one
            if selectedModelName == model.name {
                // Select another available model, or clear selection
                if let nextModel = downloadedModels.first(where: { $0.name != model.name }) {
                    selectedModelName = nextModel.name
                } else {
                    selectedModelName = ""
                }
            }
            
            loadDownloadedModels()
            return true
            
        } catch {
            logger.error("Failed to delete model \(model.name): \(error.localizedDescription)")
            lastError = "Couldn't delete: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Deletes a model by its predefined definition.
    func deleteModel(_ model: WhisperModel) async -> Bool {
        guard let downloaded = downloadedModels.first(where: { $0.name == model.name }) else {
            return false
        }
        return await deleteModel(downloaded)
    }
}

// MARK: - Model Downloader

/// Apple-native download handler using URLSessionDownloadDelegate.
/// Provides reliable progress tracking without KVO lifecycle issues.
/// Pattern from OpenEmu and other polished macOS apps.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    
    /// Called when progress updates (throttled to ≥1% change)
    var progressHandler: ((Double) -> Void)?
    
    /// Called when download completes (with temp file URL) or fails (with error)
    var completionHandler: ((URL?, Error?) -> Void)?
    
    private var downloadSession: URLSession?
    private var currentProgress: Double = 0
    
    /// Starts downloading from the given URL.
    func start(url: URL) {
        currentProgress = 0
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600 // 10 minutes for large models
        
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
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        
        guard totalBytesExpectedToWrite > 0 else { return }
        
        let newProgress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        // Throttle: only update if progress changed by ≥1%
        if abs(newProgress - currentProgress) >= 0.01 {
            currentProgress = newProgress
            progressHandler?(newProgress)
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        
        // Move to a safe location before the delegate method returns
        // (Apple deletes the temp file after this method returns)
        let safeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".bin")
        
        do {
            try FileManager.default.moveItem(at: location, to: safeURL)
            completionHandler?(safeURL, nil)
        } catch {
            completionHandler?(nil, error)
        }
        
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        
        if let error = error {
            completionHandler?(nil, error)
        }
        
        downloadSession?.finishTasksAndInvalidate()
        downloadSession = nil
    }
}
