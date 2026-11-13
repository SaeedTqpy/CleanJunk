# CleanJunk Security Model

## Trust boundaries

The app runs under the current user with no root helper. Untrusted workspaces may contain symlinks, unusual names, oversized files, and rapidly changing directory entries.

## Enforced controls

1. No automatic cleanup, permanent delete or privileged execution.
2. Every requested move has a durable write-ahead journal entry before filesystem mutation.
3. Candidates require a recognized allowed root, complete scan, and matching device/inode/type identity.
4. Parent directories are opened component-by-component without following symlinks (O_NOFOLLOW).
5. Operations check source identity through directory descriptors.
6. Same-volume renameatx_np with RENAME_EXCL refuses destination overwrite atomically.
7. Restore is allowed only for recorded, matching files in the current user's Trash; collision fails closed.
8. Docker virtual disks, SDK images, simulators and archived signed apps are inspect-only.
9. Homebrew never executes uninstall or mutating cleanup commands.
10. Incomplete scans are explicitly marked, and package usage classification never authorizes uninstall.

## Known risks

No general POSIX syscall atomically compares a source's inode and renames it as one operation. A malicious process writing to the same source parent can race the final identity check. This is manual cleanup for a normal developer-owned Mac, not a hostile shared filesystem.

Finder's Put Back metadata may be absent because CleanJunk performs a descriptor-relative rename into Trash. Use CleanJunk's own journaled Restore action, which may refuse external-volume, missing or altered files.

Source import detection is heuristic; an absent import does NOT prove unused. APFS clone sharing makes allocated sizes estimates rather than guaranteed savings. Time Machine snapshots are read-only diagnostics.

Every public release must pass macOS 26 device QA, Developer ID signing and Apple notarization.
