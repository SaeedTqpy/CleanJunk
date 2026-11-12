# CleanJunk

**CleanJunk is a native macOS 26+ developer storage intelligence app.** SwiftUI + AppKit, real system Liquid Glass controls, a conservative filesystem scanner, Homebrew inventory, and explicit per-item Trash review.

> **Project status:** active development. The foundation and automated tests are checked in. macOS CI and on-device validation must pass before any production release.

## Included

- **Overview**: measured footprints by category, risk controls, scan completeness information.
- **Space Explorer**: real filesystem inspection of selected cache roots, per-artifact estimated allocated size, filters, Finder reveal and explicit multi-select.
- **Developer workspaces**: opt-in folder picker; detects nested generated directories (node_modules, .venv, .next, .gradle, target etc.). Does not remove source files.
- **Homebrew inventory**: reads brew info --json=v2 --installed, reports installed-on-request intent, dependency counts, and displays brew autoremove --dry-run results. **Never calls brew uninstall or autoremove without --dry-run.**
- **Safe cleanup**: per-item review, policy validation, symbolic-link rejection and move-to-Trash (never rm -rf). Protected Docker virtual disks and Xcode Archives are inspect-only.
- **Audit trail**: local JSON activity log (atomic writes) in ~/Library/Application Support/CleanJunk.
- **Native design**: NavigationSplitView sidebar, SwiftUI Table, GlassEffectContainer, glass buttons, SF Symbols, dark/light and accessibility-aware system materials.

## Build (no local Xcode required)

GitHub Actions uses **macos-26**. On every push or pull request, the workflow runs Swift tests, builds the SwiftPM executable and packages an ad-hoc-signed **CleanJunk.app** into a ZIP artifact. Actions artifacts can be downloaded from the workflow run.

Locally with Xcode 26 toolchain on a macOS 26 machine:

    swift test
    bash scripts/package-app.sh release
    open dist/CleanJunk.app

Requires macOS 26+. The ad-hoc signature is for local testing only; it is **not** Developer ID signing or Apple notarization. Gatekeeper may block downloaded test artifacts. Public release requires Developer ID and notarization.

## Security policy

1. **Read-only scan first**. A scan never deletes anything.
2. Cleanup acts only on explicit selections and verifies location, risk category, allowed scan root and symbolic-link resolution again immediately beforehand.
3. Finder Trash is used; users recover via Finder. Emptying Trash is out of scope, and space is not promised as reclaimed until Trash is emptied.
4. Docker virtual disks, Xcode archives and system folders never enter the deletion path.
5. Homebrew is informational only. It is unsafe to call an installed package unused solely because it is old or has no Homebrew dependents: tools outside Homebrew may still need it.
6. APFS clone sharing, hard links and sparse files make displayed allocated-size totals **estimates**. Incomplete scans are marked, and the scan covers known user paths rather than pretending to measure the whole macOS System Data category.
7. No blanket privileged execution, filesystem access outside user-approved scope, telemetry or backend.

**Known limitations before production release:** process cancellation and timeouts, dependency adapters beyond Homebrew, race-resistant filesystem operations, database-backed operation log and recovery workflow, APFS clone-aware accounting, hard-link deduplication, privilege/permission/accessibility tests, UI testing, profiling, notarization and distribution.

## Source map

- Sources/CleanJunkCore — file scan policies, scanner, Homebrew inspector and removal engine
- Sources/CleanJunkApp — native macOS interface and app state
- Tests/CleanJunkCoreTests — safety and scanner regression tests
- scripts/package-app.sh — .app and ZIP packaging
- .github/workflows/macos.yml — macOS 26 CI

## Safety notes for contributors

Do not add direct deletion of Docker.raw, virtual machine volumes, databases, Homebrew Cellar, Xcode archives, system caches or arbitrary user directories. Adding a cleanup adapter requires a documented classification policy, proof of recoverability and fixture-based tests.
