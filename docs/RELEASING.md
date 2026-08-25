# Releasing cbNP

Maintainer notes for cutting a release. Building and running the app for development is covered in the [README](../README.md).

## Cutting a release

Bump the version, commit it, then release:

```bash
scripts/bump-version.sh 4.1.0
git commit -am 'chore: bump version to 4.1.0'
scripts/release.sh
```

The two steps are separate on purpose. `bump-version.sh` edits tracked source (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, across every build configuration so Debug and Release cannot drift). `release.sh` only reads the committed version, and refuses to run against a dirty tree or an existing tag, so a published binary always corresponds to a commit.

`release.sh` builds unsigned and then re-signs the bundle, so the free personal team set in the Xcode project keeps working for local development without conflicting with the Developer ID identity used for distribution. Nested code inside `mediaremote_adapter` is signed before the enclosing bundle, which notarization requires.

## Signing credentials

`release.sh` needs two one-time credentials:

1. A **Developer ID Application** certificate for the LOGAMES team (`D793768BHW`): Xcode > Settings > Accounts > LOGAMES > Manage Certificates > **+** > Developer ID Application.
2. A notarytool keychain profile, using an [app-specific password](https://appleid.apple.com):

   ```bash
   xcrun notarytool store-credentials cbNP-notary \
     --apple-id <apple-id> --team-id D793768BHW --password <app-specific-password>
   ```

   Override the profile name with `NOTARY_PROFILE` if you use a different one.

Until both are in place, `release.sh` stops at its identity check, and published builds stay development-signed and unnotarized — which is what the Gatekeeper note in the README describes.

## Building a DMG by hand

Build a Release `.app`, stage it next to an `/Applications` shortcut, and run `hdiutil create -format UDZO`.

## After publishing

The README's download link points at a versioned release asset (`cbNP-<version>.dmg`), so it has to be updated on every release. Switching it to a `/releases/latest/download/` URL would make it self-maintaining, but only once releases ship the image under the unversioned name `cbNP.dmg`.
