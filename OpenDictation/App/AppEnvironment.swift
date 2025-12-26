import Foundation

/// Global app environment information.
enum AppEnvironment {
    /// Returns `true` if the app is running in a unit test environment.
    /// Uses Apple's standard XCTest environment variable which is most reliable.
    static var isRunningTests: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }
}
