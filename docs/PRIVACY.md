# CleanJunk Privacy

CleanJunk is a local-first macOS developer storage inspection and user-approved cleanup app.

## Information inspected

- File paths, metadata, sizes and filesystem identities in known cache roots and a selected workspace.
- Package manifests, lockfiles and selected source text to identify dependency declarations and static import references.
- Homebrew installed formulae, local dry-run output, filesystem capacity and Time Machine snapshot identifiers.

## Local storage

- Cleanup journal: original and Trash paths, file identity, timestamp, estimated size and outcome.
- Stored under ~/Library/Application Support/CleanJunk.
- No required account, remote analytics, advertising SDK or app backend.

## External processes

Homebrew is used only for read-only inventory and dry-run analysis with analytics and auto-update disabled. Third-party developer tools maintain their own privacy policies.

## User control

Deletion is never automatic or permanent. Every move requires explicit selection and confirmation. Restore uses the local operation journal and refuses existing destinations. Files in Trash still consume space until emptied separately.

Access is limited to the current macOS user and user-selected workspaces. Permission errors are not bypassed. Remove CleanJunk's local audit data via Finder after closing the app if desired; deleting logs does not restore trashed files.
