## Context

OpenDictation currently exposes model selection via quality tiers (Fast/Balanced/Best Quality). This creates unnecessary cognitive load and doesn't match Apple's design philosophy where features "just work" without configuration.

**Inspiration**: Apple's native dictation, VoiceInk's approach, and WhisperKit's `recommendedModels()` device-mapping pattern.

**Stakeholders**: End users (want simplicity), power users (want control), developers (maintain code).

## Goals / Non-Goals

### Goals
- Zero-config experience for normal users (like Apple's dictation)
- Immediate functionality on first launch (bundled model)
- Silent progressive improvement (better model downloads in foreground when on Wi-Fi)
- Power user escape hatch (manual selection in Advanced tab)
- Language picker remains visible (Apple does this)

### Non-Goals
- Supporting Intel Macs (app is Apple Silicon only per project constraints)
- Neural Engine utilization detection (too complex for v1)
- Multiple concurrent model downloads
- Automatic deletion of old models

## Decisions

### Decision 1: Keep bundled tiny model, don't auto-delete
**Choice**: Never delete the bundled `ggml-tiny.en` model automatically.
**Rationale**: Acts as reliable fallback, disk cost is negligible (75MB), prevents edge cases where user has no working model.
**Alternatives considered**: Auto-delete after upgrade (rejected - too risky, breaks offline fallback).

### Decision 2: Check for upgrade on first launch + app launch with Wi-Fi
**Choice**: Detect specs on first launch, start download if on Wi-Fi. On subsequent launches, check if recommended model is missing and Wi-Fi available → resume/start download. Use `NWPathMonitor` for network detection.
**Rationale**: Balances responsiveness with respecting user data plans. Doesn't spam network checks. Wi-Fi only prevents unexpected cellular data usage for 500MB+ downloads.
**Alternatives considered**: Check on every dictation (too aggressive), allow cellular (bad for users with limited data), only check once ever (misses network-unavailable-at-first-launch case).

### Decision 3: Switch models between dictation sessions, not during
**Choice**: When better model download completes, switch happens on next dictation start, not mid-session.
**Rationale**: Avoids potential audio processing interruption, simpler implementation, matches user expectation.
**Alternatives considered**: Hot-swap during session (complex, risky), require app restart (bad UX).

### Decision 4: System language detection for model type
**Choice**: Detect system language from `Locale.current`. English → use `.en` models. Non-English → use multilingual models.
**Rationale**: Automatic optimization without user input. Matches Apple's locale-aware design.
**Alternatives considered**: Always use multilingual (less accurate for English), ask user (adds friction).

### Decision 5: Use RAM + Chip for recommendation, not GPU memory
**Choice**: Use `ProcessInfo.processInfo.physicalMemory` and `sysctl` for chip detection.
**Rationale**: Simpler, more reliable. GPU memory detection via Metal is complex and chip generation correlates well enough with capability.
**Alternatives considered**: Metal device queries (overkill), benchmark on first run (poor UX).

## Technical Approach

### SystemCapabilities Service
```swift
struct SystemCapabilities {
  let ramGB: Int
  let chipGeneration: ChipGeneration  // m1, m2, m3, m4
  let isEnglishSystem: Bool
  
  var recommendedModelName: String { ... }
  
  static func detect() -> SystemCapabilities
}
```

### ModelManager Extensions
```swift
extension ModelManager {
  /// Check if auto-upgrade is needed and start silent foreground download (Wi-Fi only)
  func checkAndUpgradeIfNeeded() async
  
  /// Whether current model matches auto-recommendation
  var isUsingRecommendedModel: Bool { get }
  
  /// Whether user has overridden auto-selection
  @AppStorage var isManualOverride: Bool
  
  /// Check if a model file actually exists on disk
  func isModelDownloaded(_ modelName: String) -> Bool
}
```

### Silent Foreground Download Strategy
- Use existing `ModelDownloader` (URLSessionDownloadDelegate) with `allowsCellularAccess = false`
- Check Wi-Fi availability via `NWPathMonitor` before starting download
- No UI indication during download (silent) - user continues using current model
- On completion: update `selectedModelName` if not in manual override mode
- Next dictation picks up new model via existing `LocalTranscriptionProvider` logic

**Note**: True background downloads (app suspended) require `URLSessionConfiguration.background()` + AppDelegate hooks. For v1, we use foreground silent downloads which pause if user quits app. This is acceptable since downloads resume on next Wi-Fi launch.

### Settings UI Changes
- Remove `localSettingsSection` with quality rows
- Add new `AdvancedSettingsView` accessible via tab or disclosure
- Advanced view shows: current model, recommended model, manual picker, download/delete controls

## Risks / Trade-offs

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Wi-Fi unavailable at first launch | Medium | Low | Bundled model works, retry on next Wi-Fi connection |
| User with <8GB RAM gets subpar experience | Low | Medium | Tiny model still functional, they can manually upgrade |
| Download interrupted if user quits app | Medium | Low | Download resumes on next Wi-Fi launch (not true background) |
| Model switch causes brief delay on first post-upgrade dictation | High | Low | Model loading is <2s, acceptable |

## Migration Plan

1. **No breaking changes** - Existing `transcriptionQuality` AppStorage key read during migration, then ignored
2. **First launch after update** (migration runs BEFORE removing old settings):
   - Read old `transcriptionQuality` value
   - Detect system capabilities
   - If user was on Fast tier → auto-recommendation applies
   - If user was on Balanced/Best:
     - Check if corresponding model file actually exists via `FileManager.default.fileExists()`
     - If model exists → mark as manual override, keep their model
     - If model doesn't exist → apply auto-recommendation (user never completed download)
3. **Order matters**: Migration (read old value + check file exists) must complete before UI cleanup removes old settings
4. **Rollback**: Previous version can still use models in Application Support

## Open Questions

1. ~~Should we show any indication when download completes?~~ **Decided: No, silent switch**
2. ~~Should we auto-delete tiny model after upgrade?~~ **Decided: No, keep as fallback**
3. ~~Should we restrict auto-downloads to Wi-Fi?~~ **Decided: Yes, Wi-Fi only by default**
4. Should we add cellular download option in Advanced settings? (Defer to future enhancement)
