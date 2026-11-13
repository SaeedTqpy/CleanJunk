# Security Policy

## Supported status

CleanJunk is release-candidate source for macOS 26+, not a validated or notarized public distribution. Treat the current developer preview as **test software**.

## Reporting vulnerabilities

Avoid publicly posting exploitation details, destructive reproduction instructions, sensitive files or credentials. If GitHub private vulnerability reporting is enabled for the repository, use GitHub's **Security → Report a vulnerability** workflow. Otherwise, contact the repository owner privately through an established channel and provide a minimal, redacted reproduction.

The project owner will review reported issues; no formal response-time SLA is currently promised.

## Sensitive areas

- Filesystem path verification and descriptor-relative Trash/Restore operations.
- Symlink and directory race conditions.
- Package-manifest parsing and bounded subprocess execution.
- Journal corruption, filesystem permissions and interrupted operations.
- User-selected directories and screenshot privacy.

## Design guarantees and limitations

See [the security model](docs/SECURITY_MODEL.md). The app should never execute a silent or permanent cleanup. Folder access and file identities must be verified before mutation. APFS storage estimates must not be represented as guaranteed free-space savings. No unused-library inference should authorize removal.

## Version policy

Only versions explicitly labeled by the owner as supported and validated should be used to clean important data. There is currently no claim of general availability or notarized public release.
