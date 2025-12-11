import Foundation

// When building with Xcode project (not SPM), we need to provide our own Bundle.module
// SPM auto-generates this, but Xcode projects need it manually defined
#if XCODE_BUILD
extension Bundle {
    /// The bundle containing app resources
    /// Uses Bundle.main for Xcode builds (resources are in Contents/Resources)
    static var module: Bundle {
        return Bundle.main
    }
}
#endif
