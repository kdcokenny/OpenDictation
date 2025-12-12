import AppKit
import Foundation
import os.log

/// Detects when the app is running from a DMG or temporary location and offers to move it to Applications.
/// Based on the VibeMeter pattern (MIT licensed).
final class ApplicationMover {
    
    private static let logger = Logger(subsystem: "com.opendictation", category: "ApplicationMover")
    
    // MARK: - Public API
    
    /// Checks if the app should be moved to Applications and offers to do so.
    /// Call this early in app launch (e.g., applicationDidFinishLaunching).
    @MainActor
    static func checkAndOfferToMoveToApplications() {
        // Skip if already in Applications
        guard !isInApplicationsFolder() else {
            logger.debug("App is already in Applications folder")
            return
        }
        
        // Check if running from DMG or temporary location
        let runningFromDMG = isRunningFromDMG()
        let temporaryLocation = detectTemporaryLocation()
        
        if runningFromDMG {
            logger.info("App is running from DMG, offering to move to Applications")
            showMoveDialog(reason: .dmg)
        } else if let location = temporaryLocation {
            logger.info("App is running from temporary location: \(location), offering to move")
            showMoveDialog(reason: .temporaryLocation(location))
        }
    }
    
    // MARK: - Location Detection
    
    /// Returns true if the app is already in /Applications or ~/Applications.
    private static func isInApplicationsFolder() -> Bool {
        guard let bundlePath = Bundle.main.bundlePath as NSString? else { return false }
        let path = bundlePath as String
        
        // Check system Applications
        if path.hasPrefix("/Applications/") {
            return true
        }
        
        // Check user Applications
        let userApps = NSHomeDirectory() + "/Applications/"
        if path.hasPrefix(userApps) {
            return true
        }
        
        return false
    }
    
    /// Returns true if the app is running from a mounted DMG.
    private static func isRunningFromDMG() -> Bool {
        let bundlePath = Bundle.main.bundlePath
        
        // First check: path starts with /Volumes/ (quick heuristic)
        guard bundlePath.hasPrefix("/Volumes/") else { return false }
        
        // Second check: use statfs to check filesystem type
        var stat = statfs()
        guard statfs(bundlePath, &stat) == 0 else { return false }
        
        // Get filesystem type name
        let fsTypeName = withUnsafePointer(to: &stat.f_fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) { cPtr in
                String(cString: cPtr)
            }
        }
        
        // DMGs are typically mounted as "hfs" or "apfs"
        // To be sure it's a DMG (not a regular volume), check with hdiutil
        if fsTypeName == "hfs" || fsTypeName == "apfs" {
            return verifyDMGWithHdiutil(path: bundlePath)
        }
        
        return false
    }
    
    /// Uses hdiutil to verify if the path is on a DMG.
    private static func verifyDMGWithHdiutil(path: String) -> Bool {
        // Extract volume path from bundle path (e.g., /Volumes/Open Dictation)
        let components = path.components(separatedBy: "/")
        guard components.count >= 3, components[1] == "Volumes" else { return false }
        let volumePath = "/" + components[1] + "/" + components[2]
        
        // Run hdiutil info -plist and check if our volume is listed
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let images = plist["images"] as? [[String: Any]] else {
                return false
            }
            
            // Check if any mounted image contains our volume
            for image in images {
                if let entities = image["system-entities"] as? [[String: Any]] {
                    for entity in entities {
                        if let mountPoint = entity["mount-point"] as? String,
                           mountPoint == volumePath {
                            return true
                        }
                    }
                }
            }
        } catch {
            logger.warning("Failed to run hdiutil: \(error.localizedDescription)")
            // Fall back to path-based detection
            return path.hasPrefix("/Volumes/")
        }
        
        return false
    }
    
    /// Detects if the app is running from a temporary location.
    /// Returns the location type if detected, nil otherwise.
    private static func detectTemporaryLocation() -> String? {
        let bundlePath = Bundle.main.bundlePath
        let home = NSHomeDirectory()
        let tempLocations: [(path: String, name: String)] = [
            (home + "/Downloads/", "Downloads"),
            (home + "/Desktop/", "Desktop"),
            (home + "/Documents/", "Documents"),
            ("/private/var/folders/", "temporary folder"),
            ("/tmp/", "temporary folder"),
        ]
        
        for (path, name) in tempLocations {
            if bundlePath.hasPrefix(path) {
                return name
            }
        }
        
        return nil
    }
    
    // MARK: - Move Dialog
    
    private enum MoveReason {
        case dmg
        case temporaryLocation(String)
    }
    
    @MainActor
    private static func showMoveDialog(reason: MoveReason) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        
        switch reason {
        case .dmg:
            alert.messageText = "Move to Applications?"
            alert.informativeText = "Open Dictation is running from a disk image. Move it to your Applications folder for the best experience."
        case .temporaryLocation(let location):
            alert.messageText = "Move to Applications?"
            alert.informativeText = "Open Dictation is running from your \(location) folder. Move it to Applications for the best experience."
        }
        
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            performMove()
        }
    }
    
    // MARK: - Move Implementation
    
    @MainActor
    private static func performMove() {
        let sourcePath = Bundle.main.bundlePath
        let appName = (sourcePath as NSString).lastPathComponent
        let destinationPath = "/Applications/" + appName
        let fileManager = FileManager.default
        
        // Check if app already exists at destination
        if fileManager.fileExists(atPath: destinationPath) {
            // Check if the destination app is running
            if isAppRunningAtPath(destinationPath) {
                showError("Open Dictation is already running from Applications. Please quit that instance first.")
                return
            }
            
            // Offer to replace
            let replaceAlert = NSAlert()
            replaceAlert.alertStyle = .warning
            replaceAlert.messageText = "Replace Existing App?"
            replaceAlert.informativeText = "An older version of Open Dictation exists in Applications. Would you like to replace it?"
            replaceAlert.addButton(withTitle: "Replace")
            replaceAlert.addButton(withTitle: "Cancel")
            
            if replaceAlert.runModal() != .alertFirstButtonReturn {
                return
            }
            
            // Remove existing app
            do {
                try fileManager.removeItem(atPath: destinationPath)
            } catch {
                logger.error("Failed to remove existing app: \(error.localizedDescription)")
                showError("Could not replace the existing app. You may need to remove it manually.")
                return
            }
        }
        
        // Copy to Applications
        do {
            try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
            logger.info("Successfully moved app to \(destinationPath)")
        } catch {
            logger.error("Failed to copy app: \(error.localizedDescription)")
            showError("Could not move the app to Applications. Please try dragging it manually.")
            return
        }
        
        // Offer to relaunch
        offerRelaunch(newPath: destinationPath)
    }
    
    /// Checks if an app at the given path is currently running.
    private static func isAppRunningAtPath(_ path: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { app in
            app.bundleURL?.path == path
        }
    }
    
    @MainActor
    private static func offerRelaunch(newPath: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "App Moved Successfully"
        alert.informativeText = "Open Dictation has been moved to Applications. Would you like to relaunch it from there?"
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Quit")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            relaunchFromPath(newPath)
        } else {
            NSApp.terminate(nil)
        }
    }
    
    private static func relaunchFromPath(_ path: String) {
        // Use NSWorkspace to launch the new app with completion handler
        // This ensures we only terminate after the new instance successfully starts
        // Pattern used by Sindre Sorhus, Karabiner-Elements, NetNewsWire, etc.
        let appURL = URL(fileURLWithPath: path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error = error {
                    logger.error("Failed to relaunch: \(error.localizedDescription)")
                    // Present error to user so they know what happened
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Relaunch Failed"
                    alert.informativeText = "Failed to launch from new location. Please launch the app manually from Applications."
                    alert.runModal()
                    NSApp.terminate(nil)
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
    
    @MainActor
    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
