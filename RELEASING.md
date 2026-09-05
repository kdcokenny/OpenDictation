# Releasing

Pull requests build an unsigned Release app through `make ci`. No signing credentials are available to pull request jobs. Maintainers can also run `make dmg` to create an ad hoc signed DMG for local testing. Neither path publishes an update.

Pushing a `v<version>` tag starts `.github/workflows/release.yml`. The workflow builds from scratch, verifies the bundled resources, creates `OpenDictation.dmg`, signs it for Sparkle, stages a draft GitHub release, updates `appcast.xml`, and then publishes the release.

## Required Sparkle secret

The repository already contains the Sparkle public key in `OpenDictation/App/Info.plist`. Store its matching private key as the `SPARKLE_PRIVATE_KEY` GitHub Actions secret. The tag workflow stops before building if this secret is absent. A published update without a Sparkle signature would be unusable and must not enter the appcast.

Generate a new key pair only when deliberately rotating the update key:

```bash
brew install --cask sparkle
generate_keys
```

Changing the public key requires a migration plan for installed copies of the app. Do not replace it as part of a routine release.

## Optional Developer ID signing and notarization

Configure all of these GitHub Actions secrets to ship a Developer ID signed and notarized DMG:

- `DEVELOPER_ID_CERTIFICATE_P12`: base64-encoded Developer ID Application certificate and private key
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: password for the exported P12 file
- `DEVELOPER_ID_APPLICATION`: full signing identity, such as `Developer ID Application: Example, Inc. (TEAMID)`
- `APPLE_ID`: Apple account used by `notarytool`
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for that account
- `APPLE_TEAM_ID`: Apple Developer team ID

Encode the P12 file without line breaks:

```bash
base64 < DeveloperIDApplication.p12 | tr -d '\n'
```

The workflow treats this set as all or nothing and fails if only some values are configured. When none are configured, it uses an ad hoc signature, skips notarization, and labels the GitHub release accordingly. That DMG is suitable for testing, but macOS will not treat it as an identified and notarized distribution.

## Publish a version

Run the full local check, tag the commit on `main`, and push the tag:

```bash
make ci
git tag v1.2.0
git push origin v1.2.0
```

Use a SemVer prerelease suffix such as `v1.2.0-beta.1` when appropriate. After the workflow finishes, verify the GitHub release asset, its signing note, and the new `appcast.xml` entry.

The tagged commit must be in the current `main` history. Commits added to `main` after the tag was created do not invalidate the release.
