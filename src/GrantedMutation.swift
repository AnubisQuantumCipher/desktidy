import Darwin
import Foundation

// ============================================================================
//  Phase 1B sacrificial dispatcher. A prepared grant is necessary but not
//  sufficient. Automated tests use FakeSMAdapter only. The production
//  adapter may invoke SMAppService only after this dispatcher accepts.
// ============================================================================

protocol SealedAdapterExecuting: AnyObject {
    func executeSealedRegister(plistName: String) -> Result<Void, SMAdapterError>
    func executeSealedUnregister(plistName: String) -> Result<Void, SMAdapterError>
    func status(plistName: String) -> Result<SMAdapterStatus, SMAdapterError>
}

extension FakeSMAdapter: SealedAdapterExecuting {
    func executeSealedRegister(plistName: String) -> Result<Void, SMAdapterError> {
        requestRegister(plistName: plistName)
    }
    func executeSealedUnregister(plistName: String) -> Result<Void, SMAdapterError> {
        requestUnregister(plistName: plistName)
    }
}

struct SacrificialDispatchRequest: Equatable {
    var grant: PreparedMutationGrant
    var requested: InterlockOperation
    var plistName: String
    var liveIdentity: ProbeIdentity.Measurement
    var compiledSourceCommit: String
    var second: AuthoritySnapshot
}

enum PostcallTransactionLog {
    static func append(grant: PreparedMutationGrant, result: String, status: String) {
        let support = DurableNonceStore.supportRoot(canonicalSacrificial: grant.rootCanonical)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let dest = support.appendingPathComponent("postcall.jsonl")
        var lst = stat()
        if lstat(dest.path, &lst) == 0 && (lst.st_mode & S_IFMT) == S_IFLNK { return }
        let fd = open(dest.path, O_CREAT | O_APPEND | O_WRONLY | O_NOFOLLOW, 0o600)
        if fd < 0 { return }
        defer { close(fd) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let tid = SacrificialMutationDispatcher.transactionID(for: grant)
        let line = "\(tid) \(grant.nonce) \(grant.operation.rawValue) \(result) \(status) \(iso.string(from: Date()))\n"
        let bytes = Array(line.utf8)
        _ = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        fsync(fd)
    }
}

enum SacrificialMutationDispatcher {
    static let sacrificialPlistName = "com.desktidy.sacrificial.plist"

    /// Test-only hook for A→B→A. Production remains false.
    static var disableExactlyOnceForMutationTest = false

    enum Outcome: Equatable {
        case invoked(SMAdapterStatus)
        case refused(String)
        case rollbackRequired(String)
        case indeterminate(String)
    }

    static func transactionID(for grant: PreparedMutationGrant) -> String {
        MutationBoundary.digest(Data(
            "\(grant.nonce)|\(grant.operation.rawValue)|\(grant.authorizationDigest)|\(grant.rootCanonical)|\(grant.executableSHA256)|\(grant.sourceCommit)".utf8
        ))
    }

    static func dispatch(
        _ request: SacrificialDispatchRequest,
        adapter: SealedAdapterExecuting
    ) -> Outcome {
        switch accept(request) {
        case .refuse(let reason):
            return .refused(reason)
        case .accept:
            break
        }
        switch consumeOnce(grant: request.grant) {
        case .refuse(let reason):
            return .refused(reason)
        case .accept:
            break
        }

        let plist = sacrificialPlistName
        let call: Result<Void, SMAdapterError>
        switch request.grant.operation {
        case .register:
            call = adapter.executeSealedRegister(plistName: plist)
        case .unregister:
            call = adapter.executeSealedUnregister(plistName: plist)
        }

        let status = adapter.status(plistName: plist)
        let statusText: String
        switch status {
        case .success(let s): statusText = String(describing: s)
        case .failure(let e): statusText = "error:\(e)"
        }

        switch call {
        case .failure(let err):
            PostcallTransactionLog.append(grant: request.grant, result: "adapter_failed", status: statusText)
            return .rollbackRequired("adapter failed: \(err)")
        case .success:
            switch status {
            case .failure(let err):
                PostcallTransactionLog.append(grant: request.grant, result: "status_failed", status: statusText)
                return .rollbackRequired("post-call status failed: \(err)")
            case .success(.unknown(let raw)):
                PostcallTransactionLog.append(grant: request.grant, result: "status_unknown", status: raw)
                return .indeterminate("post-call status unknown")
            case .success(let s):
                PostcallTransactionLog.append(grant: request.grant, result: "invoked", status: statusText)
                return .invoked(s)
            }
        }
    }

    private enum Gate: Equatable {
        case accept
        case refuse(String)
    }

    private static func accept(_ request: SacrificialDispatchRequest) -> Gate {
        let grant = request.grant
        if request.requested != grant.operation {
            return .refuse("grant operation does not match requested mutation")
        }
        if request.plistName != sacrificialPlistName || grantPlistForbidden(request.plistName) {
            return .refuse("plist is not the sacrificial probe plist")
        }
        if grant.executableSHA256 == String(repeating: "0", count: 64) {
            return .refuse("grant executable hash is the zero placeholder")
        }
        if grant.executableSHA256 != request.liveIdentity.executableSHA256 {
            return .refuse("live executable hash does not match grant")
        }
        if grant.sourceCommit.count != 40 || !MutationInterlock.isCommitHex(grant.sourceCommit) {
            return .refuse("grant source commit is not a 40-hex SHA")
        }
        if grant.sourceCommit != request.compiledSourceCommit {
            return .refuse("compiled source commit does not match grant")
        }
        if request.second.rootCanonical != grant.rootCanonical {
            return .refuse("sacrificial root changed between grant and dispatch")
        }
        if request.second.foreignOverlap {
            return .refuse("foreign mover on sacrificial root")
        }
        if request.second.uninspectable {
            return .refuse("authority evidence uninspectable")
        }
        if request.second.dualDeskTidy {
            return .refuse("dual DeskTidy presence")
        }
        if request.liveIdentity.plistURL.lastPathComponent != sacrificialPlistName {
            return .refuse("embedded plist identity is not sacrificial")
        }
        if !FileManager.default.fileExists(atPath: request.liveIdentity.plistURL.path) {
            return .refuse("embedded sacrificial plist missing")
        }
        switch DurableNonceStore.lookup(canonicalSacrificial: grant.rootCanonical, nonce: grant.nonce) {
        case .none:
            return .refuse("nonce reservation missing")
        case .some(let rec):
            if rec.operation != grant.operation.rawValue
                || rec.executableSHA256 != grant.executableSHA256
                || rec.sourceCommit != grant.sourceCommit
                || rec.authorizationDigest != grant.authorizationDigest {
                return .refuse("nonce reservation does not match grant")
            }
        }
        if !PrecallTransactionLog.contains(grant: grant) {
            return .refuse("pre-call transaction missing")
        }
        return .accept
    }

    private static func grantPlistForbidden(_ plistName: String) -> Bool {
        let label = plistName.replacingOccurrences(of: ".plist", with: "")
        if MutationInterlock.personalLabels.contains(label) { return true }
        if ProductIdentity.selfLabels.contains(label) { return true }
        if plistName.contains("desktop-autosort") { return true }
        if plistName.contains("com.desktidy.sort") { return true }
        if plistName.contains("com.desktidy.notify") { return true }
        return plistName != sacrificialPlistName
    }

    private static func consumeOnce(grant: PreparedMutationGrant) -> Gate {
        let support = DurableNonceStore.supportRoot(canonicalSacrificial: grant.rootCanonical)
        let dir = support.appendingPathComponent("dispatched", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        } catch {
            return .refuse("dispatch marker directory failed")
        }
        let dest = dir.appendingPathComponent(grant.nonce)
        var lst = stat()
        if lstat(dest.path, &lst) == 0 && (lst.st_mode & S_IFMT) == S_IFLNK {
            return .refuse("dispatch marker path is a symlink")
        }
        let flags = disableExactlyOnceForMutationTest
            ? (O_CREAT | O_WRONLY)
            : (O_CREAT | O_EXCL | O_WRONLY)
        let fd = open(dest.path, flags, 0o600)
        if fd < 0 {
            return .refuse("nonce already dispatched (replay)")
        }
        let line = Array("\(transactionID(for: grant))\n".utf8)
        _ = line.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        fsync(fd)
        close(fd)
        return .accept
    }
}
