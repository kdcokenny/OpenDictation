# Design: Local Whisper Model Support

## Context

OpenDictation needs offline transcription that works instantly on first launch—like opening a new MacBook.

**Constraints:**
- Must work instantly on first launch (no download wait)
- Bundled model must be deletable (user choice)
- Simple UI with Advanced section for power users
- macOS 14.0+ (Apple Silicon optimized)

## Goals / Non-Goals

**Goals:**
- Zero-config first-run: bundle tiny.en model, works immediately
- Local/Cloud toggle: simple mode switch in Settings
- Reuse existing code: adapt VoiceInk/OpenSuperWhisper patterns
- Hidden complexity: VAD, output filtering automatic

**Non-Goals:**
- Feature parity with any single app
- Real-time streaming transcription (batch is sufficient)
- Custom model training

## Decisions

### 1. Bundled Model: `ggml-tiny.en`

**Decision:** Bundle `ggml-tiny.en.bin` (~75MB) in app for instant first-run.

**Rationale:**
- Smallest model = smallest app size increase
- Good enough for casual dictation
- Users can upgrade to base/large in Settings
- Matches OpenSuperWhisper's approach

### 2. Model Storage

**Decision:** Store models in `~/Library/Application Support/com.opendictation/Models/`

Bundled model is copied from app bundle on first launch, then treated like any downloaded model (deletable).

### 3. Settings UI: Apple-Style Quality Tiers

**Decision:** Instead of showing technical model names, use simple quality tiers like Apple does with audio/video quality settings.

```
┌─────────────────────────────────────────┐
│ Transcription Mode                      │
│ [Local (Offline)] [Cloud (API)]         │
├─────────────────────────────────────────┤
│ Quality                                 │
│ ◉ Fast          Quick, good for casual  │
│ ○ Balanced      Better accuracy, daily  │
│ ○ Best Quality  Highest accuracy        │
├─────────────────────────────────────────┤
│ Language                                │
│ [English ▾]                             │
└─────────────────────────────────────────┘
```

**Under the hood mapping:**
| Quality | Language=English | Language=Other |
|---------|-----------------|----------------|
| Fast | tiny.en (bundled) | tiny |
| Balanced | base.en | base |
| Best Quality | large-v3-turbo-q5_0 | large-v3-turbo-q5_0 |

**Key principles (Apple-style):**
- No model names visible to users
- No file sizes in picker (show only when downloading)
- Language is a separate, first-class setting
- Users never see "multilingual" as a concept

### 4. Language Selection

**Decision:** Language picker in main settings (not hidden in Advanced).

When user selects:
- English → use `.en` optimized models
- Any other language → silently swap to multilingual models
- User never sees this switching happen

This follows Apple's Dictation pattern where language is a separate choice from any quality/model concept.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| +77MB app bundle size | Acceptable for instant UX; users can delete model |
| whisper.cpp updates | Pin to specific release tag |

## Open Questions

- Should we show download progress in menu bar icon while model downloads in background?
- Growing sine wave for processing state? (Note for future, not v1)
