# CleanJunk

**Developer-aware disk inspection and carefully controlled cleanup for macOS.**

CleanJunk is a native Mac utility built with **SwiftUI + AppKit** and macOS 26 **Liquid Glass** APIs. It helps developers discover storage used by caches, generated project directories and installed Homebrew packages—without pretending that “old” automatically means “safe to delete.”

> **Repository status:** Main contains the earlier developer-preview foundation. The expanded **0.9.0 release candidate** is developed in [Pull Request #6](https://github.com/SaeedTqpy/CleanJunk/pull/6) and has **not** passed final macOS validation or been published as a notarized release. **Use test data.** For the detailed documentation and new features, read the [0.9.0 developer guide](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/README.md). [راهنمای فارسی](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/docs/README.fa.md)

---

## Interface gallery

| Overview | Space Explorer |
|:--:|:--:|
| ![Illustrative CleanJunk Overview concept](docs/previews/overview.svg) | ![Illustrative CleanJunk Space Explorer concept](docs/previews/explorer.svg) |
| Packages | System Data |
| ![Illustrative CleanJunk Packages concept](docs/previews/packages.svg) | ![Illustrative CleanJunk System Data concept](docs/previews/system-data.svg) |

**Authenticity:** These are **design concept illustrations, NOT actual screenshots**. They show the intended visual language for the 0.9.0 interface. Real captures from a running app have not yet been supplied. See [Capture authentic app screenshots](#capture-authentic-app-screenshots).

## Features

| Feature | Main branch (developer preview) | 0.9.0 release-candidate branch |
|---|---|---|
| Native macOS UI | SwiftUI/AppKit with Liquid Glass controls | Extended UI and System Data page |
| Storage inspection | Xcode build artifacts, user caches, package caches and logs | Also classifies more SDK/simulator/Cargo/Go/uv locations |
| Developer workspaces | Opt-in search for generated project folders | Adds project manifest and npm lockfile inventory |
| Dependency inspection | Homebrew installed inventory and autoremove dry-run | Adds bounded JS/TS import evidence and Python/Rust/Go project discovery |
| Cleanup | Manual confirmation and move to Trash | Adds durable write-ahead journal, verified same-volume no-overwrite moves and guarded Restore |
| History | Local JSON record of Trash operations | Explicit interrupted-operation statuses and recovery |
| Distribution | Ad-hoc-signed development build, no notarization | Documented manual Apple release pipeline; not executed |

**Not supported in either branch:** automatic uninstall, root-level cleanup, guaranteed APFS reclaimable space, direct deletion of Docker virtual disks or Time Machine snapshots, and claiming a dependency is “unused” just because no import was observed.

## Requirements

- macOS **26+** and Apple Silicon for the GitHub preview build.
- For compiling locally: Xcode **26**, Swift **6.2**, macOS 26 SDK.
- A paid **Apple Developer account is not needed** to build or privately test an ad-hoc-signed developer preview.
- A broadly distributed **notarized** macOS app requires an Apple Developer ID and notarization; this is not yet configured.
- The repository is currently **private**; to use it, another person must be granted GitHub access by the owner.

## Installation without Apple Developer or local Xcode

The project provides a GitHub Actions workflow that is **manual-only**. **No workflow runs on each commit or pull request.**

1. Open [Actions](https://github.com/SaeedTqpy/CleanJunk/actions).
2. Select **Manual macOS 26 Build and Tests**.
3. Click **Run workflow** and select a reviewed branch. The **feat/dependency-intelligence-and-scan-v2** branch contains the advanced 0.9.0 work; it is still awaiting validation.
4. Switch **publish_preview** on only when you need a downloadable test ZIP. The single macOS job runs tests, builds, packages, verifies the checksum, then uploads a prerelease **only if all validation succeeds**.
5. Find the matching prerelease in [Releases](https://github.com/SaeedTqpy/CleanJunk/releases). Download its ZIP and SHA-256 file.
6. From the download folder, check the archive:

~~~bash
cd ~/Downloads
shasum -a 256 -c CleanJunk-macos26-arm64.zip.sha256
~~~

7. Extract the archive and move the app to **Applications**. Run it only after reviewing its provenance.

**macOS Gatekeeper:** These previews are ad-hoc signed, not Apple notarized. Apple may prevent launching them. Do not globally disable Gatekeeper. If you personally built the app, verified its checksum and trust it, consult Apple's [per-app Open Anyway guidance](https://support.apple.com/en-us/102445).

**Important:** A Git tag does not guarantee an installable asset exists. Only a successful manual build with **publish_preview** enabled produces a downloadable preview.

## Compile from source

From a macOS 26 machine with Xcode 26:

~~~bash
git clone https://github.com/SaeedTqpy/CleanJunk.git
cd CleanJunk

# Switch to the advanced developer candidate if you want its features:
git switch feat/dependency-intelligence-and-scan-v2

# Validate and package:
swift test --parallel
bash scripts/package-app.sh release
open dist/CleanJunk.app
~~~

The packaging script generates a .app bundle, ZIP and SHA-256 checksum in **dist/**. The advanced branch also includes an original Retina app icon and an interactive screenshot-capture tool.

For a fast local-only source check:

~~~bash
bash scripts/check-core.sh
~~~

This does **not** invoke GitHub Actions.

## How to use

1. **Overview:** Let the read-only scan finish, then inspect the reported categories, estimates and errors.
2. **Space Explorer:** Search and filter individual artifacts. Reveal uncertain items in Finder rather than deleting on size alone.
3. **Developer Caches:** Choose a development folder and inspect generated directories. The 0.9.0 branch also offers manifest and source-import evidence.
4. **Packages:** Review Homebrew formulae and the native Homebrew **autoremove dry-run**. The application will **not** automatically uninstall any package.
5. **Review cleanup:** Only approve specific files you understand. Items move to Trash; free disk space is not reclaimed until Trash is emptied.
6. **Activity:** View previous operations. The advanced branch implements guarded Restore and unresolved-operation detection.

**Use disposable test folders first.** Even rebuildable caches can affect active applications and offline development.

## Safety and limitations

CleanJunk is designed around **inspect first, change only after confirmation**. The main-branch baseline includes path-policy validation and user-confirmed Trash moves but does not yet include the stronger journaled, descriptor-relative cleanup that exists in PR #6. The release-candidate branch itself still requires actual Mac integration testing.

- Never remove Docker.raw, simulator user data, Xcode archives, SDK images or APFS snapshots using ordinary recursive file deletion.
- Do not infer package safety from its age, installation date or absence of a static import.
- Scanner size reports are **estimates**: APFS clones, shared blocks, sparse files and backups make actual free-space recovery difficult to predict.
- The project runs as the current macOS user, without a privileged root helper.
- A complete build, package, safe cleanup and restore workflow must be verified on physical macOS hardware before a production release is described as ready.

The detailed threat model and release gates are in the candidate branch: [Security Model](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/docs/SECURITY_MODEL.md) · [Release Checklist](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/docs/RELEASE_CHECKLIST.md).

## Project structure

~~~text
CleanJunk/
├── Package.swift                  Swift Package Manager project
├── Sources/CleanJunkApp/          Native SwiftUI/AppKit application
├── Sources/CleanJunkCore/         Scanners, policies and package inventory
├── Tests/CleanJunkCoreTests/      Test fixtures and regressions
├── scripts/
│   ├── package-app.sh             macOS app + ZIP packaging
│   ├── check-core.sh              Swift source type-check
│   └── capture-screenshots.sh     Genuine app window screenshots
├── docs/
│   ├── previews/                  Clearly labeled SVG concepts
│   └── screenshots/               Instructions for actual macOS captures
└── .github/workflows/macos.yml    Strictly manual macOS validation
~~~

The feature branch adds more sources, a journal, a system diagnostics page, and dedicated manual Developer ID/notarization workflow. See its full [source map](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/README.md#project-structure).

## Capture authentic app screenshots

Run the app on macOS 26, navigate to the requested page, and execute:

~~~bash
bash scripts/capture-screenshots.sh
~~~

The script interactively captures the actual CleanJunk window, one view at a time: Overview, Space Explorer, Packages, and System Data. It saves PNGs in **docs/screenshots/**, **without uploading or committing anything**.

**Privacy warning:** The app can show usernames, package lists, home directories and proprietary project names. Use a disposable test profile or redact screenshots before publishing. Read the [screenshot guide](docs/screenshots/README.md). The gallery above will be replaced with genuine images after they have been captured and verified.

## Troubleshooting

| Symptom | Recommended step |
|---|---|
| No release ZIP | Check whether the manual workflow succeeded with publish_preview=true. No ZIP exists for an unbuilt commit |
| “Unidentified developer” | Verify the source and SHA-256 and consult Apple Gatekeeper documentation; never disable security for all apps |
| Build requires macOS 26 SDK | Install Xcode 26 or use the manual GitHub workflow |
| Homebrew not detected | This inspector checks /opt/homebrew/bin/brew and /usr/local/bin/brew |
| Partial scan | Permissions or safety limits prevent complete measurement; inspect rather than remove |
| A dependency appears unused | No static import is not proof of unused; do not delete based on this claim |
| No screenshot PNGs | Actual UI images require running the app on a Mac; current assets are explicitly labeled concepts |

## Contributing, privacy and license

For complete release-candidate guidance, see [README 0.9.0](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/README.md), [Contributing](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/CONTRIBUTING.md) and [Privacy](https://github.com/SaeedTqpy/CleanJunk/blob/feat/dependency-intelligence-and-scan-v2/docs/PRIVACY.md).

**No open-source license is granted at present.** Access to a private repository does not by itself authorize redistribution or commercial use. The owner must add an explicit LICENSE and choose repository visibility before community redistribution can be offered.

---

**CleanJunk is a local-first developer tool, not a promise that every large file should be deleted.**
