# Contributing to CleanJunk

CleanJunk is a macOS-native storage diagnostics project with potentially destructive operations. **File safety, clear permission boundaries and correct risk descriptions are required for any contribution.**

## Repository access and license

The repository is currently private and does not grant an open-source license. Please obtain the owner's permission before redistribution or sharing source. Use issues and pull requests only if you have access.

## Development setup

- macOS 26+, Xcode 26 / Swift 6.2 for compiling the whole macOS app.
- No Apple Developer Program membership is needed to build or run local ad-hoc-signed previews.
- Clone the repository, work on a feature branch, and run the local checks:

~~~bash
swift test --parallel
bash scripts/check-core.sh
~~~

A fully packaged test app can be built with:

~~~bash
bash scripts/package-app.sh release
~~~

### GitHub Actions policy

**Do not add push-triggered, PR-triggered, scheduled or post-commit macOS builds.** Runner minutes are intentionally conserved. CI is manual-only; a maintainer should run one macOS 26 validation workflow after a reviewed batch of changes. Publishing developer ZIPs is an explicit, separate workflow input.

## Safety review requirements

All changes that touch scanning or cleanup should include:

1. A documented allowlist/denied-location policy and a clear risk classification.
2. Tests for symlinks, changed inode, permissions, partial scans, race windows and path collisions.
3. No unrestricted recursive deletion, privileged execution, shell interpolation of project metadata or direct deletion of SDKs, Docker volumes or Time Machine snapshots.
4. A way to explain uncertainty to the user. “Not imported” is not proof of “unused.”
5. Tests demonstrating that a failed cleanup leaves the user data intact and an unresolved operation visible.
6. No automatic cleanup, no background agent and no changes to the trusted cleanup policy without review.

## UI changes

Use SwiftUI and AppKit native controls and macOS 26 Liquid Glass APIs. Keep content surfaces legible; do not apply translucent effects to every table row. Support keyboard navigation, VoiceOver, dark/light mode, Reduce Motion and Reduce Transparency.

## Pull requests

Describe purpose, user impact, testing performed, safety implications, screenshots if genuinely captured, and any migration concerns. Mark unverified changes as such. Never attach private user paths, credentials or proprietary customer data.

## Docs and images

README and screenshots must correspond to the checked-in implementation. Keep design mockups labeled. Capture actual screenshots with **scripts/capture-screenshots.sh** on a Mac, after checking for identifying data.

See [Security Model](docs/SECURITY_MODEL.md) and [Release Checklist](docs/RELEASE_CHECKLIST.md).
