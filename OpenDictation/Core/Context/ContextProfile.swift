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
      // Glossary format per OpenAI Whisper prompting guide.
      // Whisper matches style/spelling, not instructions.
      // 224 token limit - glossary packs more terms efficiently.
      // swiftlint:disable:next line_length
      return """
        Glossary: shadcn, MCP, SDK, API, tRPC, RAG, LLM, CLI,
        git pull, git push, git commit, git merge, git rebase, git stash, git diff,
        npm, pnpm, bun, yarn, npx, pip, poetry, uv,
        zod, prisma, drizzle, tanstack, vitest, playwright,
        NextJS, Vercel, Supabase, Firebase, Cloudflare, Netlify,
        LangChain, LlamaIndex, OpenAI, Anthropic, Ollama, Gemini, Claude,
        useEffect, useState, useCallback, useMemo, async await,
        TypeScript, JavaScript, Python, Swift, Rust, Go,
        tailwind, vite, remix, astro, nuxt, svelte,
        kubectl, terraform, docker, nginx, redis, postgres,
        localhost, env, dotenv, JSON, YAML, GraphQL, REST
        """
    }
  }
}
