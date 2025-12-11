import SwiftUI

@main
struct OpenDictationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // No window group - this is a menu bar only app
        Settings {
            SettingsView()
        }
    }
}
