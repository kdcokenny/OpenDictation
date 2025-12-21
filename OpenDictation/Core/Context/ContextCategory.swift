import Foundation

/// Categories for app context with associated SF Symbol icons.
/// Extensible design system for visual differentiation in the notch UI.
///
/// Icon Design Guidelines:
/// - Use `.fill` variants for visibility on dark backgrounds
/// - Icons should be recognizable at 14x14pt (matching waveform height)
/// - Choose base symbols without decorative suffixes (.circle, .square, etc.)
enum ContextCategory: String, CaseIterable, Equatable {
    /// Code editors, terminals, IDEs
    case code
    /// General prose apps (Notes, TextEdit, etc.)
    case prose
    /// Communication apps (Slack, Discord, Messages, etc.)
    case communication
    /// Productivity apps (Notion, Obsidian, Linear, etc.)
    case productivity
    /// Creative apps (Figma, Photoshop, etc.)
    case creative
    /// Web browsers
    case browser
    /// Media apps (Spotify, Music, etc.)
    case media
    /// Default fallback
    case general
    
    /// SF Symbol name for this category.
    var sfSymbol: String {
        switch self {
        case .code:
            return "terminal.fill"
        case .prose:
            return "doc.text.fill"
        case .communication:
            return "bubble.left.fill"
        case .productivity:
            return "checklist"
        case .creative:
            return "paintbrush.fill"
        case .browser:
            return "globe"
        case .media:
            return "play.fill"
        case .general:
            return "microphone.fill"
        }
    }
    
    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .code: return "Code"
        case .prose: return "Prose"
        case .communication: return "Communication"
        case .productivity: return "Productivity"
        case .creative: return "Creative"
        case .browser: return "Browser"
        case .media: return "Media"
        case .general: return "General"
        }
    }
}
