import Foundation

/// Represents the transcription context - once parsed, this is the trusted state.
/// Follows Law #2: Make Illegal States Unrepresentable
enum ContextProfile: Equatable {
  case code   // IDE, terminal, code editor
  case prose  // Standard apps (Mail, Slack, Notes, etc.)

  /// The visual category for icon display in the notch UI.
  var category: ContextCategory {
    switch self {
    case .code:
      return .code
    case .prose:
      return .general  // Default to general (mic icon) for prose
    }
  }

  /// The initial prompt to bias Whisper transcription for this context.
  /// Returns nil for prose (vanilla Whisper behavior with style hint).
  var whisperPrompt: String? {
    switch self {
    case .prose:
      // Natural language prompt for proper punctuation/capitalization.
      // Pattern from VoiceInk - a greeting that demonstrates the style.
      return "Hello, how are you doing today? I hope you're having a great day."

    case .code:
      // Natural sentence with tech vocabulary for style emulation.
      // Whisper emulates STYLE, not instructions - use real sentences.
      // Pattern from VoiceInk: natural language that demonstrates the style.
      return """
        I'm working on TypeScript and Python code with React, NextJS, Supabase, \
        and Vercel. I'll run git pull, git push, use npm and bun, and work with \
        the API, SDK, and CLI. Let me check the useEffect and useState hooks.
        """
    }
  }
}
