# Releasing

Open Dictation uses [Sparkle](https://sparkle-project.org/) for automatic updates.

## One-Time Setup (Maintainers)

1. Generate an EdDSA key pair:
   ```bash
   brew install --cask sparkle
   generate_keys
   ```

2. Copy the public key to `OpenDictation/App/Info.plist`:
   ```xml
   <key>SUPublicEDKey</key>
   <string>YOUR_PUBLIC_KEY_HERE</string>
   ```

3. Add the private key to GitHub Secrets as `SPARKLE_PRIVATE_KEY`

## Creating a Release

1. Tag the release:
   ```bash
   git tag v0.2.0-alpha
   git push origin v0.2.0-alpha
   ```

2. The GitHub Actions workflow will:
   - Build the app
   - Create a signed DMG
   - Update `appcast.xml`
   - Create a GitHub Release

Users will receive the update automatically (or can check manually via the menu bar).
