# Design: Automatic Updates

## Context

Open Dictation needs an automatic update mechanism that:
- Works without Apple Developer Program ($99/year)
- Provides silent, "Apple-like" background updates
- Is secure (cryptographic signature verification)
- Is the industry standard for macOS apps

## Goals / Non-Goals

**Goals:**
- Silent automatic updates (no user prompts for routine updates)
- Secure update verification via EdDSA signatures
- Simple release workflow via GitHub Actions
- Alpha channel support for early adopters

**Non-Goals:**
- Apple notarization (requires Developer Program)
- Mac App Store distribution (different update mechanism)
- Delta updates (complexity not justified at this stage)
- Multiple update channels (stable/beta) - defer until 1.0

## Decisions

### Decision: Use Sparkle Framework

**What**: Integrate Sparkle 2.8.1 via Swift Package Manager

**Why**: 
- Industry standard (used by Rectangle, Ghostty, Whisky, Sindre Sorhus apps, etc.)
- MIT licensed, actively maintained
- Supports EdDSA signatures (no Apple code signing required)
- Built-in automatic download and installation
- SwiftUI-friendly with `SPUStandardUpdaterController`

**Alternatives considered**:
- Custom implementation → Too much work, security risk
- GitHub Releases only → No automatic installation, poor UX
- BasicUpdater → Less mature, fewer features

### Decision: Fully Automatic (Silent) Updates

**What**: Configure Sparkle to download and install updates automatically without user prompts

**Why**:
- Matches native macOS app behavior (Apple-like UX)
- Reduces friction for users
- Ensures users stay on latest version

**Configuration**:
```xml
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUAllowsAutomaticUpdates</key>
<true/>
<key>SUAutomaticallyUpdate</key>
<true/>
```

**User override**: Users can disable automatic updates in Settings if desired.

### Decision: Daily Update Checks (86400 seconds)

**What**: Check for updates once every 24 hours

**Why**:
- Most common interval used by popular apps (Transmission, WWDC, Jitsi)
- Balances freshness with not being annoying
- User can manually check anytime via menu

### Decision: Host Appcast in Repository Root

**What**: Store `appcast.xml` in repository root, served via GitHub raw URLs

**Why**:
- Simplest approach, no additional hosting needed
- GitHub raw URLs are reliable and free
- CI can automatically update on release

**URL**: `https://raw.githubusercontent.com/kdcokenny/OpenDictation/main/appcast.xml`

### Decision: Alpha Versioning Scheme

**What**: Use `CFBundleShortVersionString: 0.x.0-alpha` with incrementing `CFBundleVersion` build numbers

**Why**:
- Clearly communicates pre-release status
- Build numbers provide unambiguous ordering for Sparkle
- Can transition to stable versioning when ready

**Example**:
- Version 1: `0.1.0-alpha` (build 1)
- Version 2: `0.1.1-alpha` (build 2)
- Version 3: `0.2.0-alpha` (build 3)

### Decision: No Apple Code Signing (For Now)

**What**: Use only Sparkle EdDSA signatures, not Apple Developer ID

**Why**:
- Avoids $99/year Developer Program fee
- EdDSA provides cryptographic security for updates
- First-time users bypass Gatekeeper with right-click → Open (common for open-source apps)
- All subsequent auto-updates work seamlessly

**Trade-off**: First-time install requires user to bypass Gatekeeper warning.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    UpdateService                         │
│  - SPUStandardUpdaterController                         │
│  - Publishes canCheckForUpdates                         │
│  - checkForUpdates() for manual trigger                 │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    Sparkle Framework                     │
│  - Background check timer (86400s)                      │
│  - Downloads update if available                        │
│  - Verifies EdDSA signature                             │
│  - Installs and relaunches app                          │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│                    appcast.xml                           │
│  - Hosted at GitHub raw URL                             │
│  - Updated by CI on each release                        │
│  - Contains version, download URL, signature            │
└─────────────────────────────────────────────────────────┘
```

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| Gatekeeper warning on first install | Document in README, common for open-source apps |
| EdDSA private key leak | Store only in GitHub Secrets, never commit |
| Sparkle vulnerability | Pin to specific version, monitor for updates |
| User doesn't want auto-updates | Provide toggle in Settings |

## Migration Plan

1. Generate EdDSA key pair locally (`generate_keys`)
2. Add public key to Info.plist
3. Add private key to GitHub Secrets
4. Implement UpdateService and UI changes
5. Create initial appcast.xml (empty)
6. Set up GitHub Actions release workflow
7. Tag first release to trigger workflow

**Rollback**: Remove Sparkle dependency, revert Info.plist changes. Users on old versions continue working but won't receive updates.

## Open Questions

None - all decisions resolved during planning phase.
