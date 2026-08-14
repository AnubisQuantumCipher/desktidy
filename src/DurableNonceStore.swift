import Darwin
import Foundation

// ============================================================================
//  Durable atomic one-time nonce reservation under an authorized sacrificial
//  support root. O_CREAT|O_EXCL — existing reservation always refuses.
//  No global /tmp registry. No cleanup that permits replay.
// ============================================================================

struct NonceReservation: Equatable {
    var nonce: String
    var operation: String
    var executableSHA256: String
    var sourceCommit: String
    var rootCanonical: String
    var authorizationDigest: String
    var reservedAt: String
}

enum DurableNonceStore {
    /// Test-only hook for A→B→A. Production remains false.
    static var disableExclusivityForMutationTest = false
    static let maxNonceLen = 64
    static let nonceGrammar = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]{8,64}$")

    enum Outcome: Equatable {
        case reserved(NonceReservation)
        case refused(String)
    }

    static func normalize(_ nonce: String) -> String? {
        let range = NSRange(nonce.startIndex..<nonce.endIndex, in: nonce)
        guard nonceGrammar.firstMatch(in: nonce, options: [], range: range) != nil else { return nil }
        return nonce
    }

    static func supportRoot(canonicalSacrificial: String) -> URL {
        URL(fileURLWithPath: canonicalSacrificial, isDirectory: true)
            .appendingPathComponent(".desktidy-probe-support", isDirectory: true)
    }

    static func reserve(
        canonicalSacrificial: String,
        nonce: String,
        operation: String,
        executableSHA256: String,
        sourceCommit: String,
        authorizationDigest: String
    ) -> Outcome {
        guard let safe = normalize(nonce) else { return .refused("nonce grammar invalid") }
        let support = supportRoot(canonicalSacrificial: canonicalSacrificial)
        let nonceDir = support.appendingPathComponent("nonces", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: nonceDir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: nonceDir.path)
        } catch {
            return .refused("nonce store directory failed")
        }
        var lst = stat()
        if lstat(nonceDir.path, &lst) != 0 || (lst.st_mode & S_IFMT) == S_IFLNK {
            return .refused("nonce store path is a symlink")
        }
        let dest = nonceDir.appendingPathComponent(safe)
        if lstat(dest.path, &lst) == 0 && (lst.st_mode & S_IFMT) == S_IFLNK {
            return .refused("nonce reservation path is a symlink")
        }
        let flags = disableExclusivityForMutationTest ? (O_CREAT | O_WRONLY) : (O_CREAT | O_EXCL | O_WRONLY)
        let fd = open(dest.path, flags, 0o600)
        if fd < 0 {
            return .refused("nonce already reserved")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let rec = NonceReservation(
            nonce: safe, operation: operation, executableSHA256: executableSHA256,
            sourceCommit: sourceCommit, rootCanonical: canonicalSacrificial,
            authorizationDigest: authorizationDigest, reservedAt: iso.string(from: Date())
        )
        let line = "\(rec.nonce) \(rec.operation) \(rec.executableSHA256) \(rec.sourceCommit) \(rec.authorizationDigest) \(rec.reservedAt)\n"
        let bytes = Array(line.utf8)
        let written = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        fsync(fd)
        close(fd)
        if written != bytes.count { return .refused("nonce record write failed") }
        return .reserved(rec)
    }

    static func lookup(canonicalSacrificial: String, nonce: String) -> NonceReservation? {
        guard let safe = normalize(nonce) else { return nil }
        let dest = supportRoot(canonicalSacrificial: canonicalSacrificial)
            .appendingPathComponent("nonces", isDirectory: true)
            .appendingPathComponent(safe)
        var lst = stat()
        if lstat(dest.path, &lst) != 0 { return nil }
        if (lst.st_mode & S_IFMT) == S_IFLNK { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: dest.path)) else { return nil }
        let parts = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
        guard parts.count >= 6 else { return nil }
        return NonceReservation(
            nonce: parts[0],
            operation: parts[1],
            executableSHA256: parts[2],
            sourceCommit: parts[3],
            rootCanonical: canonicalSacrificial,
            authorizationDigest: parts[4],
            reservedAt: parts[5]
        )
    }
}
