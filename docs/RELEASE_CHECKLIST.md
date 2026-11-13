# CleanJunk macOS Release Gate

**Target candidate:** v0.9.0-rc.1
**Supported:** macOS 26+, Apple Silicon arm64.
**Status:** NOT APPROVED FOR PUBLIC RELEASE until all mandatory gates are met.

## Build and automated tests

- [ ] Run the manual Actions workflow **Manual macOS 26 Build and Tests** on the candidate commit once, with publish_preview=false.
- [ ] Confirm swift test --parallel passed, including CleanupJournal, SafeTrashMover, SourceReferenceInspector, WorkspaceDependencyInspector, StorageScanner and Homebrew fixtures.
- [ ] Confirm app packaging, Info.plist, Retina icon, codesign verification, and plutil.
- [ ] Record commit SHA, workflow URL, release ZIP hash and test results.

## Real-device verification (not replaceable by a CI runner)

- [ ] Test on a clean macOS 26 Apple Silicon user profile, Light/Dark Mode and window resizing.
- [ ] Inspect accessible developer caches and verify permission failures are visibly reported.
- [ ] Check Homebrew inventory; ensure zero uninstall commands are run.
- [ ] Inspect workspaces with Node, Python, Rust and Go manifests and lockfiles.
- [ ] Verify import-analysis warnings: not-observed does NOT prove unused.
- [ ] Use disposable fixtures to move a file into Trash, verify journal, restart, restore.
- [ ] Attempt Restore to an occupied path; MUST refuse and never overwrite.
- [ ] Test symlinks, changed inode, incomplete scans, unsupported volumes and interrupted operations.
- [ ] Test several thousand files, empty disk, corrupt journal and Unicode filenames.
- [ ] VoiceOver, keyboard navigation, Reduce Motion/Transparency, display scaling.
- [ ] Test clean installation and launch under default Gatekeeper settings with the final notarized artifact.

## Signing and publication

- [ ] Obtain Apple Developer Program access and Developer ID Application certificate.
- [ ] Configure these GitHub Action secrets:
  - APPLE_DEVELOPER_ID_P12_BASE64
  - APPLE_DEVELOPER_ID_P12_PASSWORD
  - APPLE_DEVELOPER_ID_IDENTITY
  - APPSTORE_CONNECT_API_KEY_P8
  - APPSTORE_CONNECT_KEY_ID
  - APPSTORE_CONNECT_ISSUER_ID
- [ ] Run the workflow **Manual Developer ID Release** on the reviewed SHA. It signs, notarizes and staples the app, then creates a private draft Release.
- [ ] Confirm notarytool accepted the app, stapler validates and spctl accepts it.
- [ ] Confirm the draft actually contains ZIP and SHA-256 downloads, not merely a tag.
- [ ] Publish the draft ONLY after device QA and an explicit distribution decision.

## Exclusions

- No automated package removal, root helper or permanent deletion.
- No direct deletion of Docker VM disks, snapshots, SDKs or simulator state.
- No guaranteed reclaimed bytes or unused-package inference from missing imports.

Do not describe the app as publicly released or notarized before these gates are complete.
