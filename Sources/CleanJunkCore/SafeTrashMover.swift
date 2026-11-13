import Foundation
import Darwin

/// Same-volume, descriptor-relative transfer to the user's Trash.
/// Symlinked parent components and destination overwrite are refused.
///
/// Limit: POSIX cannot atomically compare the inode to an expected identity
/// AND rename the name in one syscall. Other processes writing the same parent
/// can still race the last identity check, so deletion is never unattended.
public enum SafeTrashMover {
    public static func move(_ item: ScanItem, home: URL, workspace: URL? = nil) throws -> URL {
        try ScanPolicy.validateRemoval(item, home: home, workspace: workspace)
        guard let expected = item.identity, item.isTrashEligible else {
            throw CleanJunkError.forbiddenPath
        }
        let sourceURL = URL(fileURLWithPath: item.path).standardizedFileURL
        let sourceParent = sourceURL.deletingLastPathComponent()
        let trashURL = home.standardizedFileURL.appendingPathComponent(".Trash", isDirectory: true)

        // The Trash directory may not exist in a newly created test home.
        // Refuse a symlink: opening the directory chain below checks each component.
        if !FileManager.default.fileExists(atPath: trashURL.path) {
            try FileManager.default.createDirectory(at: trashURL,
                                                    withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }

        let fromFD = try openVerifiedDirectory(sourceParent)
        defer { close(fromFD) }
        let toFD = try openVerifiedDirectory(trashURL)
        defer { close(toFD) }

        var fromFolder = stat()
        var toFolder = stat()
        guard fstat(fromFD, &fromFolder) == 0,
              fstat(toFD, &toFolder) == 0,
              fromFolder.st_dev == toFolder.st_dev else {
            throw CleanJunkError.unsupportedOperation // Cross-volume moves are not allowed.
        }

        let name = sourceURL.lastPathComponent
        var original = stat()
        let statResult = name.withCString { fstatat(fromFD, $0, &original, AT_SYMLINK_NOFOLLOW) }
        guard statResult == 0 else { throw CleanJunkError.pathChanged }
        let kind = UInt32(original.st_mode) & UInt32(S_IFMT)
        let actual = FileIdentity(device: UInt64(original.st_dev),
                                  inode: UInt64(original.st_ino), fileType: kind)
        guard actual == expected else { throw CleanJunkError.pathChanged }

        // UUID prefix prevents name collisions. RENAME_EXCL enforces no overwrite
        // atomically on supported macOS filesystems; failure means no move.
        let newName = "CleanJunk-" + UUID().uuidString + "-" + String(name.prefix(110))
        let renameResult = name.withCString { fromName in
            newName.withCString { toName in
                renameatx_np(fromFD, fromName, toFD, toName, 0x00000004)
            }
        }
        guard renameResult == 0 else {
            let code = errno
            if code == EEXIST { throw CleanJunkError.alreadyExists }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                          userInfo: [NSLocalizedDescriptionKey:
                            "Atomic move into Trash was declined by the filesystem (errno \(code))."])
        }

        // The file was moved on the same volume; inode is expected to be stable.
        // If a post-move check fails, do NOT attempt an unsafe automatic rollback.
        let resultURL = trashURL.appendingPathComponent(newName)
        guard FileIdentity.capture(at: resultURL) == expected else {
            throw CleanJunkError.pathChanged
        }
        return resultURL
    }

    private static func openVerifiedDirectory(_ path: URL) throws -> Int32 {
        let standardized = path.standardizedFileURL
        guard standardized.path.hasPrefix("/") else { throw CleanJunkError.forbiddenPath }

        var descriptor = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CleanJunkError.forbiddenPath }
        for component in standardized.pathComponents.dropFirst() {
            if component.isEmpty || component == "." || component == ".." || component == "/" {
                close(descriptor)
                throw CleanJunkError.forbiddenPath
            }
            let child = component.withCString { name in
                openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            close(descriptor)
            guard child >= 0 else {
                throw CleanJunkError.pathChanged
            }
            descriptor = child
        }
        return descriptor
    }
}
