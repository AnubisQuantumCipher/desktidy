import Darwin
import Foundation

// ============================================================================
//  Authorization file is a trust surface: one open, no symlink, regular file,
//  current-user owner, mode no wider than 0600, small size cap.
//  Bytes come from that descriptor only — never reopened by path.
// ============================================================================

enum SecureAuthFile {
    static let maxBytes = 4096

    enum Outcome: Equatable {
        case ok(Data)
        case refused(String)
    }

    static func openOnce(path: String) -> Outcome {
        var lst = stat()
        if lstat(path, &lst) != 0 {
            return .refused("authorization file unreadable")
        }
        if (lst.st_mode & S_IFMT) == S_IFLNK {
            return .refused("authorization file is a symlink")
        }
        if (lst.st_mode & S_IFMT) != S_IFREG {
            return .refused("authorization file is not a regular file")
        }
        if lst.st_uid != getuid() {
            return .refused("authorization file owner mismatch")
        }
        if (lst.st_mode & 0o077) != 0 {
            return .refused("authorization file mode wider than 0600")
        }
        if lst.st_size < 0 || lst.st_size > maxBytes {
            return .refused("authorization file oversized")
        }
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 {
            return .refused("authorization file open failed")
        }
        defer { close(fd) }
        var buf = [UInt8](repeating: 0, count: maxBytes + 1)
        let n = read(fd, &buf, buf.count)
        if n < 0 { return .refused("authorization file read failed") }
        if n > maxBytes { return .refused("authorization file oversized") }
        return .ok(Data(buf.prefix(n)))
    }
}
