import Foundation
import os.log

extension Logger {
    /// Creates a logger with the app's subsystem.
    ///
    /// This provides a consistent subsystem across all loggers in the app,
    /// derived from the bundle identifier.
    ///
    /// - Parameter category: The category for this logger (typically the class/service name)
    /// - Returns: A Logger configured with the app's subsystem
    static func app(category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.opendictation", category: category)
    }
}

extension OSLog {
    /// Creates an OSLog with the app's subsystem.
    ///
    /// Use this in `nonisolated` contexts where the Swift `Logger` type cannot be used
    /// due to actor isolation requirements.
    ///
    /// - Parameter category: The category for this log (typically the class/service name)
    /// - Returns: An OSLog configured with the app's subsystem
    static func app(category: String) -> OSLog {
        OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.opendictation", category: category)
    }
}
