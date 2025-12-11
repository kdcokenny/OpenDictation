## 1. System Capability Detection

- [x] 1.1 Create `SystemCapabilities.swift` with RAM detection (`ProcessInfo.physicalMemory`)
- [x] 1.2 Add chip generation detection via `sysctl` (hw.model → parse M1/M2/M3/M4)
- [x] 1.3 Add system language detection via `Locale.current`
- [x] 1.4 Implement `recommendedModelName` computed property with mapping logic
  - Return `ggml-` prefixed names (e.g., `ggml-tiny.en`, `ggml-base.en`, `ggml-large-v3-turbo-q5_0`)
- [ ] 1.5 Add unit tests for capability detection and model mapping (deferred)

## 2. ModelManager Auto-Selection

- [x] 2.1 Add `@AppStorage("isManualModelOverride")` flag to ModelManager
- [x] 2.2 Add `isUsingRecommendedModel` computed property
- [x] 2.3 Add `isModelDownloaded(_ modelName: String) -> Bool` method
- [x] 2.4 Implement `checkAndUpgradeIfNeeded()` method:
  - Check Wi-Fi availability via `NWPathMonitor`
  - Detect system capabilities
  - Compare recommended model to current
  - If different and not manual override and on Wi-Fi → start download
- [x] 2.5 Add `applyRecommendedModel()` to switch after download completes
- [x] 2.6 Call `checkAndUpgradeIfNeeded()` from `AppDelegate.applicationDidFinishLaunching`

## 3. Silent Foreground Download (Wi-Fi Only)

- [x] 3.1 Add `NWPathMonitor` wrapper for Wi-Fi detection
- [x] 3.2 Modify `downloadModel()` to support silent mode (no UI updates except progress tracking)
  - Set `allowsCellularAccess = false` on URLSession configuration
- [x] 3.3 Add completion callback that calls `applyRecommendedModel()` when in auto mode
- [x] 3.4 Handle download resume on app relaunch (check if recommended model missing + on Wi-Fi)

**Note**: v1 uses foreground silent downloads. Downloads pause if app quits, resume on next Wi-Fi launch. True background downloads (with AppDelegate hooks) deferred to future enhancement.

## 4. Migration Handling (MUST RUN BEFORE UI CLEANUP)

- [x] 4.1 Read old `transcriptionQuality` value from UserDefaults BEFORE removing it
- [x] 4.2 If user was on Fast tier → apply auto-recommendation logic
- [x] 4.3 If user was on Balanced/Best tier:
  - Check if corresponding model file actually exists via `FileManager.default.fileExists()`
  - If model exists → set `isManualModelOverride = true`, keep their model
  - If model doesn't exist → apply auto-recommendation (user never completed download)
- [x] 4.4 Mark migration as complete to prevent re-running

**IMPORTANT**: This section MUST complete before Section 5 removes old settings.

## 5. Settings UI Simplification
- [x] 5.1 Remove `localSettingsSection` (quality rows) from SettingsView
- [x] 5.2 Remove quality-related `@AppStorage` and computed properties (AFTER migration runs)
- [x] 5.3 Remove download alert logic triggered by quality changes
- [x] 5.4 Keep language picker in main settings (universal for both modes)
- [x] 5.5 Update Settings frame height to account for removed content

## 6. Advanced Settings Tab

- [x] 6.1 Create `AdvancedSettingsView.swift` with:
  - Current model display
  - Recommended model display (based on SystemCapabilities)
  - Manual model picker (dropdown of all predefined models)
  - Download/delete buttons per model
  - "Reset to Automatic" button
- [x] 6.2 Add "Advanced" disclosure or tab to SettingsView
- [x] 6.3 Wire manual model selection to set `isManualModelOverride = true`
- [x] 6.4 Wire "Reset to Automatic" to clear override and trigger `checkAndUpgradeIfNeeded()`

## 7. Validation and Testing
- [x] 7.1 Test first launch flow (bundled `ggml-tiny.en` works immediately)
- [x] 7.2 Test silent download flow (starts after capability detection when on Wi-Fi)
- [x] 7.3 Test model switch (next dictation uses new model after download)
- [x] 7.4 Test offline/cellular first launch (works with bundled, defers download until Wi-Fi)
- [x] 7.5 Test Advanced settings (manual selection persists, reset works)
- [x] 7.6 Test migration - user with Balanced setting + model downloaded → keeps model
- [x] 7.7 Test migration - user with Balanced setting + model NOT downloaded → gets auto-recommendation
