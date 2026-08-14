import Foundation

// ============================================================================
//  Phase 1A.1 measured-evidence and grant-preparation gates.
//  Fake providers only. Does not construct a production ServiceManagement adapter.
// ============================================================================

final class Phase1A1Tests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private let commit = "e14c13fd35f45b875d0880ef15d28dd1d0d653ee"
    private let hashOK = String(repeating: "ab", count: 32)

    private func check(_ id: String, _ desc: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("PASS  \(id)  \(desc)"); pass += 1 }
        else { print("FAIL  \(id)  \(desc)\(detail.isEmpty ? "" : " — \(detail)")"); fail += 1 }
    }

    func runAll() -> Bool {
        DurableNonceStore.disableExclusivityForMutationTest = false
        ProductionMutationLedger.reset()
        runIdentityAndPrepare()
        runAuthFile()
        runNonce()
        runLedger()
        print("PHASE1A1 GATES: \(pass) passed, \(fail) failed")
        if pass == 0 { print("FAIL  summary  zero cases"); return false }
        return fail == 0
    }

    private func tmpDir(_ tag: String) -> URL {
        let u = fm.temporaryDirectory.appendingPathComponent("dt-1a1-\(tag)-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func identity(hash: String? = nil, name: String = "DeskTidySacrificialProbe",
                          bid: String = "com.desktidy.sacrificial-probe",
                          app: URL? = nil, exe: URL? = nil, plistOK: Bool = true) -> ProbeIdentity.Measurement {
        let bundle = app ?? tmpDir("app").appendingPathComponent("DeskTidySacrificialProbe.app")
        try? fm.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plistDir = bundle.appendingPathComponent("Contents/Library/LaunchAgents")
        try? fm.createDirectory(at: plistDir, withIntermediateDirectories: true)
        let plist = plistDir.appendingPathComponent("com.desktidy.sacrificial.plist")
        if plistOK { fm.createFile(atPath: plist.path, contents: Data("plist".utf8)) }
        let exec = exe ?? bundle.appendingPathComponent("Contents/MacOS/\(name)")
        return ProbeIdentity.Measurement(
            executableURL: exec, basename: name, appBundleURL: bundle,
            bundleIdentifier: bid, plistURL: plist, executableSHA256: hash ?? hashOK)
    }

    private func auth(root: String, hash: String? = nil, commit: String? = nil,
                      nonce: String = "nonce-ok1", op: String = "register") -> Data {
        let exp = iso.string(from: Date().addingTimeInterval(3600))
        let h = hash ?? hashOK
        let c = commit ?? self.commit
        return Data("{\"schema\":1,\"operation\":\"\(op)\",\"sacrificialRoot\":\"\(root)\",\"bundleSHA256\":\"\(h)\",\"sourceCommit\":\"\(c)\",\"expiry\":\"\(exp)\",\"nonce\":\"\(nonce)\"}".utf8)
    }

    private func snap(_ root: String, foreign: Bool = false, unknown: Bool = false, dual: Bool = false) -> AuthoritySnapshot {
        AuthoritySnapshot(foreignOverlap: foreign, uninspectable: unknown, dualDeskTidy: dual, rootCanonical: root)
    }

    private func prepare(auth: Data, id: ProbeIdentity.Measurement, root: String,
                         first: AuthoritySnapshot? = nil, second: AuthoritySnapshot? = nil,
                         commit: String? = nil) -> MutationBoundary.Outcome {
        let desk = tmpDir("desk")
        let home = tmpDir("home")
        return MutationBoundary.prepare(
            authBytes: auth, identity: id, compiledSourceCommit: commit ?? self.commit,
            operation: .register,
            first: first ?? snap(root), second: second ?? snap(root),
            desktop: AuthorityGuard.canonicalize(desk.path),
            home: AuthorityGuard.canonicalize(home.path),
            protected: [], productionTarget: nil)
    }

    private func runIdentityAndPrepare() {
        let root = tmpDir("sac")
        let id = identity()

        let z = String(repeating: "0", count: 64)
        let r1 = prepare(auth: auth(root: root.path, hash: z), id: identity(hash: z), root: root.path)
        check("E01", "zero placeholder hash refused",
              { if case .refused = r1 { return true }; return false }(), "\(r1)")

        let r2b = prepare(auth: auth(root: root.path, commit: "0b11c652e364cf47668ba87b4228a0f4ab7974ec", nonce: "nonce-e02"),
                          id: id, root: root.path, commit: self.commit)
        check("E02", "stale Phase 0 commit refused against current compiled identity",
              { if case .refused = r2b { return true }; return false }(), "\(r2b)")

        let copied = identity(name: "copied-probe")
        let meas = ProbeIdentity.measureRunning(executableURL: copied.executableURL, bundle: nil)
        check("E03", "copied/renamed executable refused as sacrificial",
              { if case .refused = meas { return true }; return false }(), "\(meas)")

        let missing = tmpDir("gone")
        try? fm.removeItem(at: missing)
        check("E04", "nonexistent root snapshot fails closed",
              { if case .failed = ProductionAuthoritySnapshot.live.snapshot(rootPath: missing.path) { return true }; return false }())

        let fileRoot = tmpDir("files").appendingPathComponent("notdir")
        fm.createFile(atPath: fileRoot.path, contents: Data("x".utf8))
        check("E05", "regular file rejected as sacrificial root",
              { if case .failed = ProductionAuthoritySnapshot.live.snapshot(rootPath: fileRoot.path) { return true }; return false }())

        let r6 = prepare(auth: auth(root: root.path), id: id, root: root.path,
                         first: snap(root.path), second: snap(root.path, foreign: true))
        check("E06", "foreign overlap on second observation refused",
              { if case .refused(let s) = r6 { return s.contains("foreign") }; return false }(), "\(r6)")

        let r7 = prepare(auth: auth(root: root.path), id: id, root: root.path,
                         first: snap(root.path), second: snap(root.path, unknown: true))
        check("E07", "unknown/uninspectable authority refused",
              { if case .refused(let s) = r7 { return s.contains("uninspectable") }; return false }(), "\(r7)")

        let wrongHash = String(repeating: "cd", count: 32)
        let rHash = prepare(auth: auth(root: root.path, hash: wrongHash), id: id, root: root.path)
        check("E16", "correct-length wrong executable hash refused",
              { if case .refused = rHash { return true }; return false }(), "\(rHash)")

        let short = prepare(auth: auth(root: root.path), id: id, root: root.path, commit: "e14c13f")
        check("E17", "short SHA compiled identity refused",
              { if case .refused = short { return true }; return false }(), "\(short)")

        let dual = prepare(auth: auth(root: root.path), id: id, root: root.path,
                           first: snap(root.path), second: snap(root.path, dual: true))
        check("E18", "dual DeskTidy presence refused",
              { if case .refused = dual { return true }; return false }(), "\(dual)")

        let changed = prepare(auth: auth(root: root.path), id: id, root: root.path,
                              first: snap(root.path), second: snap(tmpDir("other").path))
        check("E19", "root changed between observations refused",
              { if case .refused = changed { return true }; return false }(), "\(changed)")

        let ok = prepare(auth: auth(root: root.path, nonce: "nonce-e20"), id: id, root: root.path)
        check("E20", "valid hermetic prepare yields grant",
              { if case .prepared = ok { return true }; return false }(), "\(ok)")
        let log = DurableNonceStore.supportRoot(canonicalSacrificial: root.path)
            .appendingPathComponent("precall.jsonl")
        check("E21", "append-only pre-call transaction recorded",
              fm.fileExists(atPath: log.path), log.path)
    }

    private func runAuthFile() {
        let dir = tmpDir("auth")
        let path = dir.appendingPathComponent("auth.json")
        let body = auth(root: tmpDir("sac").path)
        try? body.write(to: path)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)

        switch SecureAuthFile.openOnce(path: path.path) {
        case .ok(let d): check("A01", "0600 regular auth opens once", d == body)
        case .refused(let r): check("A01", "0600 regular auth opens once", false, r)
        }

        let link = dir.appendingPathComponent("auth.link")
        try? fm.removeItem(at: link)
        try? fm.createSymbolicLink(at: link, withDestinationURL: path)
        check("E10", "auth symlink refused",
              { if case .refused = SecureAuthFile.openOnce(path: link.path) { return true }; return false }())

        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
        check("E11", "auth mode 0644 refused",
              { if case .refused = SecureAuthFile.openOnce(path: path.path) { return true }; return false }())
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)

        let big = dir.appendingPathComponent("big.json")
        try? Data(repeating: 0x61, count: SecureAuthFile.maxBytes + 10).write(to: big)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: big.path)
        check("A02", "oversized auth refused",
              { if case .refused = SecureAuthFile.openOnce(path: big.path) { return true }; return false }())

        // substitution after open: original bytes retained
        switch SecureAuthFile.openOnce(path: path.path) {
        case .ok(let first):
            try? Data("{\"schema\":1}".utf8).write(to: path)
            check("E12", "open-once retains original bytes after path substitution",
                  first == body && first != Data("{\"schema\":1}".utf8))
        case .refused(let r):
            check("E12", "open-once retains original bytes after path substitution", false, r)
        }
    }

    private func runNonce() {
        let root = tmpDir("nonce-root")
        let first = DurableNonceStore.reserve(
            canonicalSacrificial: AuthorityGuard.canonicalize(root.path).path,
            nonce: "nonce-rep1", operation: "register",
            executableSHA256: hashOK, sourceCommit: commit, authorizationDigest: "aa")
        check("N01", "first nonce reservation succeeds",
              { if case .reserved = first { return true }; return false }(), "\(first)")
        let replay = DurableNonceStore.reserve(
            canonicalSacrificial: AuthorityGuard.canonicalize(root.path).path,
            nonce: "nonce-rep1", operation: "register",
            executableSHA256: hashOK, sourceCommit: commit, authorizationDigest: "aa")
        check("E08", "nonce replay across store instances refused",
              { if case .refused = replay { return true }; return false }(), "\(replay)")

        let raceRoot = tmpDir("nonce-race")
        let canon = AuthorityGuard.canonicalize(raceRoot.path).path
        var wins = 0
        var losses = 0
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            switch DurableNonceStore.reserve(
                canonicalSacrificial: canon, nonce: "nonce-race1", operation: "register",
                executableSHA256: hashOK, sourceCommit: commit, authorizationDigest: "bb") {
            case .reserved: lock.lock(); wins += 1; lock.unlock()
            case .refused: lock.lock(); losses += 1; lock.unlock()
            }
        }
        check("E09", "concurrent nonce reservation has exactly one winner",
              wins == 1 && losses == 7, "wins=\(wins) losses=\(losses)")
    }

    private func runLedger() {
        ProductionMutationLedger.reset()
        let root = tmpDir("led")
        _ = prepare(auth: auth(root: root.path, nonce: "nonce-led1"), id: identity(), root: root.path)
        check("E14", "prepare does not construct a production adapter",
              ProductionMutationLedger.constructions == 0
                && ProductionMutationLedger.registerInvocations == 0
                && ProductionMutationLedger.unregisterInvocations == 0,
              "c=\(ProductionMutationLedger.constructions) r=\(ProductionMutationLedger.registerInvocations)")
        check("S11", "retained second-precall foreign ID still refused at prepare",
              { if case .refused = prepare(auth: auth(root: root.path, nonce: "nonce-s11"), id: identity(),
                                           root: root.path, first: snap(root.path),
                                           second: snap(root.path, foreign: true)) { return true }; return false }())
        check("S12", "retained second-precall target-change ID still refused",
              { if case .refused = prepare(auth: auth(root: root.path, nonce: "nonce-s12"), id: identity(),
                                           root: root.path, first: snap(root.path),
                                           second: snap(tmpDir("mut").path)) { return true }; return false }())
    }
}
