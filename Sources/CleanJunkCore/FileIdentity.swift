import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Lightweight identity captured at scan time. An inode match does not by itself
/// eliminate TOCTOU races; a descriptor-based cleanup engine is still required.
public struct FileIdentity: Codable, Hashable, Sendable {
    public let device: UInt64
    public let inode: UInt64
    public let fileType: UInt32

    public init(device: UInt64, inode: UInt64, fileType: UInt32) {
        self.device = device
        self.inode = inode
        self.fileType = fileType
    }

    /// lstat does not follow the final symlink. Symlinks and special files are forbidden.
    public static func capture(at url: URL) -> FileIdentity? {
        let path = url.standardizedFileURL.path
        var information = stat()
        guard lstat(path, &information) == 0 else { return nil }

        let kind = UInt32(information.st_mode) & UInt32(S_IFMT)
        guard kind == UInt32(S_IFREG) || kind == UInt32(S_IFDIR) else { return nil }

        return FileIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino),
            fileType: kind
        )
    }
}
