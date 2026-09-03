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

`release.sh` needs no credentials and no network access. It builds Release, checks that the built app reports the expected version, stages it next to an `/Applications` shortcut, and packages `cbNP-<version>.dmg` with `hdiutil create -format UDZO`. It then mounts the finished image and re-checks the version and signature of the copy inside it, so a bad copy fails here rather than on someone else's Mac. Publishing is left to you: the script prints the `git tag` and `gh release create` commands.

## Signing

The app is signed by the Xcode project's own automatic **Apple Development** identity, which also applies `App.entitlements`. There is no separate distribution identity and no re-signing step, so local development builds and release builds cannot disagree about signing.

That means releases are **development-signed and not notarized**. Notarization would require a Developer ID Application certificate, which this project does not have. The consequence is on the user's side: macOS blocks the first launch, and the Gatekeeper note in the README is the instructions for getting past it. Keep that note in place for as long as this is how releases ship.

## After publishing

The README's download link points at a versioned release asset (`cbNP-<version>.dmg`), so it has to be updated on every release. Switching it to a `/releases/latest/download/` URL would make it self-maintaining, but only once releases ship the image under an unversioned name.
