import AppKit

/// Detects context profile from the frontmost application at dictation time.
/// Follows Law #1: Early Exit - unknown apps default to prose.
enum ContextDetector {

  /// Bundle identifiers for developer applications.
  /// Sources: OpenInTerminal, Claude Island, AeroSpace
  private static let developerBundleIDs: Set<String> = [
    // IDEs
    "com.apple.Xcode",
    "com.microsoft.VSCode",
    "com.microsoft.VSCodeInsiders",
    "com.todesktop.230313mzl4w4u92",  // Cursor
    "dev.zed.Zed",
    "dev.zed.Zed-Preview",
    "com.exafunction.windsurf",
    "com.google.antigravity",
    "ai.opencode.desktop",
    "com.visualstudio.code.oss",  // VSCodium
    "com.sublimetext.3",
    "com.sublimetext.4",
    "com.panic.Nova",
    "org.vim.MacVim",
    "com.macromates.TextMate",
    "com.barebones.bbedit",

    // JetBrains
    "com.jetbrains.AppCode",
    "com.jetbrains.CLion",
    "com.jetbrains.fleet",
    "com.jetbrains.goland",
    "com.jetbrains.intellij",
    "com.jetbrains.PhpStorm",
    "com.jetbrains.pycharm",
    "com.jetbrains.rubymine",
    "com.jetbrains.WebStorm",
    "com.jetbrains.rider",
    "com.jetbrains.datagrip",

    // Git & DB Tools
    "com.github.GitHubClient",  // GitHub Desktop
    "io.beekeeperstudio.desktop",

    // Terminals
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "net.kovidgoyal.kitty",
    "com.github.wez.wezterm",
    "io.alacritty",
    "dev.warp.Warp-Stable",
    "com.mitchellh.ghostty",
    "co.zeit.hyper",
    "org.tabby"
  ]

  /// Detects the current context profile based on frontmost application.
  /// Called at dictation trigger time (Option+Space).
  ///
  /// - Returns: `.code` if in a developer app, `.prose` otherwise.
  static func detect() -> ContextProfile {
    guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
      return .prose
    }
    return developerBundleIDs.contains(bundleID) ? .code : .prose
  }
}
