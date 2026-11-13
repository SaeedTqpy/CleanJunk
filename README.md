# CleanJunk

**CleanJunk is a native macOS 26+ developer storage intelligence app.** SwiftUI + AppKit, real system Liquid Glass controls, a conservative filesystem scanner, Homebrew inventory, and explicit per-item Trash review.

> **Project status:** v0.9.0 release-candidate source. Build + device QA, notarization and signing have NOT been validated for this new branch. Do not publish until docs/RELEASE_CHECKLIST.md is satisfied.

## Included

- **Overview**: measured footprints by category, risk controls, scan completeness information.
- **Space Explorer**: real filesystem inspection of selected cache roots, per-artifact estimated allocated size, filters, Finder reveal and explicit multi-select.
- **Developer workspaces**: opt-in folder picker; detects generated directories (node_modules, .venv, .next, .gradle, target etc.) without touching source files. A read-only project inventory discovers Node.js, Python, Rust and Go manifests. Node.js direct dependency declarations and npm lockfile entry counts are parsed; Python/Rust/Go dependency resolution is **not yet implemented**. On-demand JS/TS import evidence is supported and explicitly distinguishes observed / not observed / unknown; this is NOT proof that a dependency can be uninstalled.
- **Homebrew inventory**: reads brew info --json=v2 --installed, reports installed-on-request intent, dependency counts, and displays brew autoremove --dry-run results. **Never calls brew uninstall or autoremove without --dry-run.**
- **Safe cleanup**: explicit review, complete scan + device/inode verification, directory descriptors opened without following symlinks, same-volume no-overwrite atomic rename into the user's Trash, durable write-ahead journal, and guarded restoration without replacing originals. Protected Docker virtual disks, simulator data, SDKs and Xcode archives remain inspect-only. A hostile concurrent writer can still race the final identity check; no unattended cleanup.
- **System Data diagnostics**: read-only filesystem capacity, local Time Machine snapshot list, and explicit caveats: neither snapshot count nor listed cache sizes equal the macOS System Data category.
- **Audit trail**: versioned local write-ahead operations journal (atomic writes) and history under ~/Library/Application Support/CleanJunk. Interrupted operations are shown as unresolved, not success.
- **Native design**: NavigationSplitView sidebar, SwiftUI Table, GlassEffectContainer, glass buttons, SF Symbols, original generated Retina app icon, Light/Dark Mode and native accessibility-aware materials.

## Build (no local Xcode required)

**GitHub Actions is manual-only.** Pushes and pull requests do not run CI. To validate a batch of changes, open Actions → **Manual macOS 26 Build and Tests** → Run workflow. Leave `publish_preview` **off** for tests and packaging only; turn it on only when a downloadable ad-hoc-signed ZIP and SHA-256 file are intentionally required. Preview releases avoid the exhausted Actions artifact quota, but publishing still uses macOS runner minutes. No workflow has been run for changes added after the initial tested foundation.

For rapid local checks that consume **zero GitHub Actions minutes**, run:

    bash scripts/check-core.sh

Locally with the Xcode 26 toolchain on a macOS 26 machine:

    bash scripts/check-core.sh --test
    swift test
    bash scripts/package-app.sh release
    open dist/CleanJunk.app

For public distribution, configure the six Apple signing secrets documented in docs/RELEASE_CHECKLIST.md, then run the separate **Manual Developer ID Release** workflow. It creates a private draft release only after successful Developer ID signing, Apple notarization, and stapling. An Apple Developer Program membership is required for the certificate. There is no unattended release.

Requires macOS 26+. The ad-hoc signature is for local testing only; it is **not** Developer ID signing or Apple notarization. Gatekeeper may block downloaded test artifacts. Public release requires Developer ID and notarization.

## Security policy

1. **Read-only scan first**. A scan never deletes anything.
2. Every move requires explicit selection and confirmation, is journaled before mutation, and uses verified directory descriptors and renameatx_np(RENAME_EXCL) to prohibit destination overwrites. This narrows but cannot eliminate source-entry races.
3. Moves are directed into the current user's Trash, never permanently deleted. The app's own guarded Restore is supported; Finder Put Back metadata might not be available. Emptying Trash is out of scope, and no disk space is promised as reclaimed until then.
4. Docker virtual disks, Simulator device data, SDK installations, Xcode archives and system folders never enter the deletion path.
5. Homebrew is informational only. It is unsafe to call an installed package unused solely because it is old or has no Homebrew dependents: tools outside Homebrew may still need it.
6. APFS clone sharing, hard links and sparse files make displayed allocated-size totals **estimates**. Incomplete scans are marked, and the scan covers known user paths rather than pretending to measure the whole macOS System Data category.
7. No blanket privileged execution, filesystem access outside user-approved scope, telemetry or backend.

**Known limitations before production release:** persistent history uses atomic JSON rather than SQLite, external-volume cleanup is intentionally refused, no exhaustive dependency graph or automated uninstall, static import searches can miss dynamic usage, scanner performance/permission QA remains outstanding, APFS clone-aware size reporting is not implemented, accessibility and physical Mac tests remain outstanding, Apple Developer ID and notarization are not yet configured. See docs/SECURITY_MODEL.md and docs/RELEASE_CHECKLIST.md.

## Source map

- Sources/CleanJunkCore — file scan policies, scanner, Homebrew inspector and removal engine
- Sources/CleanJunkApp — native macOS interface and app state
- Tests/CleanJunkCoreTests — safety and scanner regression tests
- scripts/package-app.sh and scripts/generate-icon.swift — macOS app/ZIP + original icns packaging
- .github/workflows/macos.yml — manual-only macOS 26 build/test workflow
- .github/workflows/release.yml — manual-only Developer ID/notarytool signing, verification and draft release
- docs/ — privacy, security threat model and mandatory release QA gates

## Safety notes for contributors

Do not add direct deletion of Docker.raw, virtual machine volumes, databases, Homebrew Cellar, Xcode archives, system caches or arbitrary user directories. Adding a cleanup adapter requires a documented classification policy, proof of recoverability and fixture-based tests.
