import Foundation

// ============================================================================
//  Multi-factor mutation interlock — the only path that may invoke a
//  production register/unregister adapter. Phase 1A tests the parser/policy
//  only. No valid live authorization file is created here.
// ============================================================================

enum InterlockOperation: String, Equatable {
    case register
    case unregister
}

struct InterlockAuthorization: Equatable {
    var operation: InterlockOperation
    var sacrificialRoot: String
    var bundleSHA256: String
    var sourceCommit: String
    var expiry: Date
    var nonce: String
}

struct InterlockContext: Equatable {
    var isSacrificialProbeExecutable: Bool
    var requestedOperation: InterlockOperation
    var plistName: String
    var actualBundleSHA256: String
    var actualSourceCommit: String
    var now: Date
    var usedNonces: Set<String>
    var foreignOverlap: Bool
    var desktopCanonical: CanonicalPath
    var sacrificialExists: Bool
}

enum InterlockDecision: Equatable {
    case permit(InterlockAuthorization)
    case refuse(String)
}

enum MutationInterlock {
    static let personalLabels: Set<String> = [
        "com.sicarii.desktop-autosort",
        "com.sicarii.desktop-autosort-notify",
    ]
    static let requiredKeys: Set<String> = [
        "schema", "operation", "sacrificialRoot", "bundleSHA256", "sourceCommit", "expiry", "nonce",
    ]
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    enum AuthParse: Equatable {
        case ok(InterlockAuthorization)
        case failed(String)
    }

    static func parseAuthorization(_ data: Data) -> AuthParse {
        switch StrictJSONObject.parse(data) {
        case .failed(let r): return .failed(r)
        case .ok(let obj):
            let keys = Set(obj.keys)
            if keys != requiredKeys { return .failed("authorization key set mismatch") }
            guard case .integer(let schema) = obj["schema"], schema == 1 else {
                return .failed("authorization schema invalid")
            }
            guard case .string(let opRaw) = obj["operation"],
                  let op = InterlockOperation(rawValue: opRaw) else {
                return .failed("authorization operation invalid")
            }
            guard case .string(let root) = obj["sacrificialRoot"], !root.isEmpty else {
                return .failed("authorization sacrificialRoot invalid")
            }
            guard case .string(let hash) = obj["bundleSHA256"], isSHA256Hex(hash) else {
                return .failed("authorization bundleSHA256 invalid")
            }
            guard case .string(let commit) = obj["sourceCommit"], isCommitHex(commit) else {
                return .failed("authorization sourceCommit invalid")
            }
            guard case .string(let expRaw) = obj["expiry"], let expiry = iso.date(from: expRaw) else {
                return .failed("authorization expiry invalid")
            }
            guard case .string(let nonce) = obj["nonce"], !nonce.isEmpty else {
                return .failed("authorization nonce invalid")
            }
            return .ok(InterlockAuthorization(
                operation: op, sacrificialRoot: root, bundleSHA256: hash.lowercased(),
                sourceCommit: commit.lowercased(), expiry: expiry, nonce: nonce
            ))
        }
    }

    static func evaluate(authData: Data, context: InterlockContext) -> InterlockDecision {
        if !context.isSacrificialProbeExecutable {
            return .refuse("not the sacrificial probe executable")
        }
        if personalLabels.contains(context.plistName) {
            return .refuse("personal mover label is never a mutation target")
        }
        switch parseAuthorization(authData) {
        case .failed(let r): return .refuse(r)
        case .ok(let auth):
            if auth.operation != context.requestedOperation {
                return .refuse("authorization operation mismatch")
            }
            if auth.bundleSHA256 != context.actualBundleSHA256.lowercased() {
                return .refuse("authorization bundle hash mismatch")
            }
            if auth.sourceCommit != context.actualSourceCommit.lowercased() {
                return .refuse("authorization source commit mismatch")
            }
            if auth.expiry <= context.now { return .refuse("authorization expired") }
            if context.usedNonces.contains(auth.nonce) { return .refuse("authorization nonce reused") }
            if context.foreignOverlap { return .refuse("foreign mover on sacrificial root") }
            if !context.sacrificialExists { return .refuse("sacrificial root missing") }
            let rootCanon = AuthorityGuard.canonicalize(auth.sacrificialRoot)
            if rootsEquivalent(rootCanon, context.desktopCanonical) {
                return .refuse("sacrificial root is Desktop")
            }
            if isInsideDesktop(auth.sacrificialRoot, desktop: context.desktopCanonical) {
                return .refuse("sacrificial root is inside Desktop")
            }
            return .permit(auth)
        }
    }

    static func isSHA256Hex(_ s: String) -> Bool {
        s.count == 64 && s.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }
    static func isCommitHex(_ s: String) -> Bool {
        (s.count == 40 || s.count == 64) && s.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    static func rootsEquivalent(_ a: CanonicalPath, _ b: CanonicalPath) -> Bool { a == b }

    static func isInsideDesktop(_ path: String, desktop: CanonicalPath) -> Bool {
        var url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if AuthorityGuard.canonicalize(url.path) == desktop { return true }
        }
        return false
    }
}
