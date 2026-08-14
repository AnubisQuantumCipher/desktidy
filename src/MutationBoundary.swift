import CryptoKit
import Darwin
import Foundation

// ============================================================================
//  Sealed prepared grant. Produced only after secure auth open, measured
//  identity, two root/authority observations, policy permit, and atomic nonce
//  reservation. Phase 1A.1 stops here — no production adapter call.
// ============================================================================

struct PreparedMutationGrant: Equatable {
    let operation: InterlockOperation
    let executableSHA256: String
    let sourceCommit: String
    let rootCanonical: String
    let nonce: String
    let authorizationDigest: String
    fileprivate init(operation: InterlockOperation, executableSHA256: String,
                     sourceCommit: String, rootCanonical: String, nonce: String,
                     authorizationDigest: String) {
        self.operation = operation
        self.executableSHA256 = executableSHA256
        self.sourceCommit = sourceCommit
        self.rootCanonical = rootCanonical
        self.nonce = nonce
        self.authorizationDigest = authorizationDigest
    }
}

struct AuthoritySnapshot: Equatable {
    var foreignOverlap: Bool
    var uninspectable: Bool
    var dualDeskTidy: Bool
    var rootCanonical: String
}

enum AuthoritySnapResult: Equatable {
    case ok(AuthoritySnapshot)
    case failed(String)
}

protocol AuthoritySnapshotProviding {
    func snapshot(rootPath: String) -> AuthoritySnapResult
}

enum PrecallTransactionLog {
    enum Outcome: Equatable {
        case recorded
        case refused(String)
    }

    static func append(grant: PreparedMutationGrant) -> Outcome {
        let support = DurableNonceStore.supportRoot(canonicalSacrificial: grant.rootCanonical)
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
        } catch {
            return .refused("pre-call transaction directory failed")
        }
        let dest = support.appendingPathComponent("precall.jsonl")
        var lst = stat()
        if lstat(dest.path, &lst) == 0 && (lst.st_mode & S_IFMT) == S_IFLNK {
            return .refused("pre-call transaction path is a symlink")
        }
        let fd = open(dest.path, O_CREAT | O_APPEND | O_WRONLY | O_NOFOLLOW, 0o600)
        if fd < 0 { return .refused("pre-call transaction open failed") }
        defer { close(fd) }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let tid = SacrificialMutationDispatcher.transactionID(for: grant)
        let line = "\(tid) \(grant.nonce) \(grant.operation.rawValue) \(grant.executableSHA256) \(grant.sourceCommit) \(grant.authorizationDigest) \(iso.string(from: Date()))\n"
        let bytes = Array(line.utf8)
        let written = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
        if written != bytes.count { return .refused("pre-call transaction write failed") }
        fsync(fd)
        return .recorded
    }

    static func contains(grant: PreparedMutationGrant) -> Bool {
        let dest = DurableNonceStore.supportRoot(canonicalSacrificial: grant.rootCanonical)
            .appendingPathComponent("precall.jsonl")
        var lst = stat()
        if lstat(dest.path, &lst) != 0 { return false }
        if (lst.st_mode & S_IFMT) == S_IFLNK { return false }
        guard let data = try? Data(contentsOf: dest) else { return false }
        let tid = SacrificialMutationDispatcher.transactionID(for: grant)
        let needle = "\(tid) \(grant.nonce) \(grant.operation.rawValue) \(grant.executableSHA256)"
        return String(decoding: data, as: UTF8.self).contains(needle)
    }
}

enum MutationBoundary {
    enum Outcome: Equatable {
        case prepared(PreparedMutationGrant)
        case refused(String)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func prepare(
        authBytes: Data,
        identity: ProbeIdentity.Measurement,
        compiledSourceCommit: String,
        operation: InterlockOperation,
        first: AuthoritySnapshot,
        second: AuthoritySnapshot,
        desktop: CanonicalPath,
        home: CanonicalPath,
        protected: [CanonicalPath],
        productionTarget: CanonicalPath?,
        now: Date = Date()
    ) -> Outcome {
        if compiledSourceCommit.count != 40 || !MutationInterlock.isCommitHex(compiledSourceCommit) {
            return .refused("compiled source commit is not a 40-hex SHA")
        }
        if identity.executableSHA256 == String(repeating: "0", count: 64) {
            return .refused("executable hash is the zero placeholder")
        }
        if first.rootCanonical != second.rootCanonical {
            return .refused("sacrificial root changed between observations")
        }
        if first.foreignOverlap || second.foreignOverlap {
            return .refused("foreign mover on sacrificial root")
        }
        if first.uninspectable || second.uninspectable {
            return .refused("authority evidence uninspectable")
        }
        if first.dualDeskTidy || second.dualDeskTidy {
            return .refused("dual DeskTidy presence")
        }
        let root = AuthorityGuard.canonicalize(first.rootCanonical)
        if MutationInterlock.rootsEquivalent(root, desktop) {
            return .refused("sacrificial root is Desktop")
        }
        if MutationInterlock.isInsideDesktop(first.rootCanonical, desktop: desktop) {
            return .refused("sacrificial root is inside Desktop")
        }
        if MutationInterlock.rootsEquivalent(root, home) {
            return .refused("sacrificial root is home directory")
        }
        if root.path == "/" { return .refused("sacrificial root is /") }
        if let parent = URL(fileURLWithPath: desktop.path).deletingLastPathComponent().path as String? {
            if MutationInterlock.rootsEquivalent(root, AuthorityGuard.canonicalize(parent)) {
                return .refused("sacrificial root is parent of Desktop")
            }
        }
        for p in protected {
            if MutationInterlock.rootsEquivalent(root, p) {
                return .refused("sacrificial root equals a protected target")
            }
            if MutationInterlock.isInsideDesktop(first.rootCanonical, desktop: p) {
                return .refused("sacrificial root is inside a protected target")
            }
            let protParent = URL(fileURLWithPath: p.path).deletingLastPathComponent().path
            if MutationInterlock.rootsEquivalent(root, AuthorityGuard.canonicalize(protParent)) {
                return .refused("sacrificial root is parent of a protected target")
            }
        }
        if let prod = productionTarget, MutationInterlock.rootsEquivalent(root, prod) {
            return .refused("sacrificial root is the production DeskTidy target")
        }

        var ctx = InterlockContext(
            isSacrificialProbeExecutable: true,
            requestedOperation: operation,
            plistName: "com.desktidy.sacrificial.plist",
            actualBundleSHA256: identity.executableSHA256,
            actualSourceCommit: compiledSourceCommit,
            now: now,
            usedNonces: [],
            foreignOverlap: false,
            desktopCanonical: desktop,
            sacrificialExists: true
        )
        ctx.authorityUninspectable = false
        ctx.dualDeskTidyPresence = false
        switch MutationInterlock.evaluate(authData: authBytes, context: ctx) {
        case .refuse(let r): return .refused(r)
        case .permit(let auth):
            let nonce = DurableNonceStore.reserve(
                canonicalSacrificial: first.rootCanonical,
                nonce: auth.nonce,
                operation: auth.operation.rawValue,
                executableSHA256: identity.executableSHA256,
                sourceCommit: compiledSourceCommit,
                authorizationDigest: digest(authBytes)
            )
            switch nonce {
            case .refused(let r): return .refused(r)
            case .reserved(let rec):
                let grant = PreparedMutationGrant(
                    operation: auth.operation,
                    executableSHA256: identity.executableSHA256,
                    sourceCommit: compiledSourceCommit,
                    rootCanonical: first.rootCanonical,
                    nonce: rec.nonce,
                    authorizationDigest: rec.authorizationDigest
                )
                switch PrecallTransactionLog.append(grant: grant) {
                case .refused(let r): return .refused(r)
                case .recorded:
                    return .prepared(grant)
                }
            }
        }
    }
}
