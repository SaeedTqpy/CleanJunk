# Full Mac Intelligence — Deep File Inventory

## Purpose

The early CleanJunk scanner only measured a limited number of known cache roots. **Full Mac Intelligence** is a separate, comprehensive, read-only filesystem indexer that attempts to enumerate **every accessible file and folder** on the requested scope, including hidden files, application bundles, app containers, language runtimes, installed tools and package caches.

This is not equivalent to unrestricted access to the entire Mac. macOS privacy permissions (TCC), System Integrity Protection (SIP), other users' data, protected app-group containers, encrypted volumes and inaccessible mount points can block access. The scanner reports those exclusions; it does not claim 100% coverage or attempt to bypass the operating system.

## What the engine does

1. Scans the root volume (/) or an explicitly selected folder/volume.
2. Does not follow symbolic links; inventories symlinks as links, not their targets.
3. Does not skip the contents of .app bundles or hidden directories.
4. Uses lstat for metadata; does not read personal file bodies, passwords, photos or database contents.
5. Stores each scanned entry in a private SQLite metadata index and pages results in groups of 150.
6. Uses stat block counts for approximate on-disk allocation, avoiding duplicate hard-link counting. APFS clones may still share blocks; allocations do not equal reclaimable space.
7. Records skipped/mounted paths, filesystem errors and partial scans.
8. Allows case-insensitive path search, categorization, evidence inspection and streaming CSV export.
9. Uses a temporary SQLite index and replaces the previous completed index only after a scan finishes.
10. Cancels safely, checks for low free space, and refuses to interpret an unfinished index as complete.

Default technical limits are **10 million entries** or **30 minutes** per scan, whichever comes first. Reaching either limit is reported as incomplete, not as success. Extremely large disks may require scoped scans; indexing large filesystems takes significant time and creates an on-disk metadata database.

## Risk and package detection

Every indexed record receives:
- An ownership hint (application bundle, package name, bundle ID, toolchain or unknown).
- A storage category (application cache/data, developer cache, installed package, system, user content, diagnostics, other).
- A rule-based recommendation with explanation:
  - **Rebuildable — ask first:** recognized generated caches (npm, pip, uv, Go, Cargo downloads, Xcode DerivedData). May still be in use.
  - **Review with app owner:** ordinary application caches, some generated project dependencies and diagnostics. Avoid removing active data.
  - **Preserve:** system components, app bundles, application support and containers with important state, user documents, cloud storage, SDKs, simulator data, installed package binaries.
  - **Unknown — do not remove:** insufficient evidence for an accurate decision.

Recommendations do **not** authorize file deletion. The Full Mac Intelligence page is **read-only**. An explicit action links users to CleanJunk's separately allowlisted Space Explorer cleanup, where existing inode checks, write-ahead journal, user confirmation, and guarded Trash/Restore still apply.

Package detection includes:
- Homebrew formula and cask inventory in the existing Packages page.
- Read-only installer receipts via macOS pkgutil.
- Per-file attribution for known Homebrew Cellar paths, Node.js node_modules, Python site-packages, Cargo, virtual environments, Gradle and SDKs.
- Previously implemented project manifest discovery and static JS/TS import evidence.

**Installer receipts are historical metadata and do not guarantee installed files still exist.** Files found under package directories do not prove whether they are actually required. Lack of a static import does not justify uninstalling software. Application-specific caches may be protected by TCC even when paths are visible.

## Privacy and permissions

The SQLite index is stored under:

    ~/Library/Application Support/CleanJunk/deep-storage-v1.sqlite

It contains file paths and metadata, which may reveal account names or private project names. It never stores actual file contents. The app requests standard user read permissions; access can be expanded by manually granting Full Disk Access under:

    System Settings → Privacy & Security → Full Disk Access

**Full Disk Access is not root and does not bypass SIP, app-group protections or APFS snapshot storage.** User consent is never simulated or bypassed.

Database and directory permissions are restricted to the current user. Users may remove the local index in Finder after closing CleanJunk. A CSV export may expose private filenames; do not upload it without reviewing it.

## Storage categories that are NOT ordinary files

macOS System Data is not one path. APFS local Time Machine snapshots, purgeable blocks, shared clones, snapshots of other volumes, and firmware/system allocations cannot be comprehensively attributed by a user-mode directory walk. The separate read-only System Data page reports available capacity and Time Machine snapshot identifiers, but does not delete snapshots or promise a byte-for-byte match to macOS Storage Settings.

## Validation requirements

- Run Swift unit tests and the macOS 26 build only when a reviewed batch is ready.
- Test 100K and 1M file directories, SQLite search and CSV export performance.
- Test permission denial, symbolic links, duplicate hard links, sparse/APFS-cloned files, other users, app containers, and mounted volumes on a real Mac.
- Verify that classification of app databases, cloud files, credentials, VMs, SDKs and real project source is conservative.
- Confirm a canceled scan preserves the previous completed SQLite index.
- Test VoiceOver, keyboard-only browsing, UI scrolling and progress cancellation.
- No automatic cleanup from this index.

For public distribution, code-signing and Apple notarization requirements remain separate; an ad-hoc developer preview can be built without a paid Apple Developer Program account.
