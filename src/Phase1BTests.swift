import Foundation

// ============================================================================
//  Phase 1B grant-acceptance gates. Fake/hermetic only.
//  Does not construct a production ServiceManagement adapter.
// ============================================================================

final class Phase1BTests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0
    private let commit = "d259b2b971b83ce89e34426af791422adea8e472"
    private let hashOK = String(repeating: "ab", count: 32)

    private func check(_ id: String, _ desc: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("PASS  \(id)  \(desc)"); pass += 1 }
        else { print("FAIL  \(id)  \(desc)\(detail.isEmpty ? "" : " — \(detail)")"); fail += 1 }
    }

    func runAll() -> Bool {
        DurableNonceStore.disableExclusivityForMutationTest = false
        ProductionMutationLedger.reset()
        runGrantPolicy()
        runSourceSeams()
        print("PHASE1B GATES: \(pass) passed, \(fail) failed")
        if pass == 0 { print("FAIL  summary  zero cases"); return false }
        return fail == 0
    }

    private func tmpDir(_ tag: String) -> URL {
        let u = fm.temporaryDirectory.appendingPathComponent("dt-1b-\(tag)-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func makeGrant(nonce: String = "nonce-1b01") -> PreparedMutationGrant? {
        let root = tmpDir("sac")
        let bundle = tmpDir("app").appendingPathComponent("DeskTidySacrificialProbe.app")
        try? fm.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plistDir = bundle.appendingPathComponent("Contents/Library/LaunchAgents")
        try? fm.createDirectory(at: plistDir, withIntermediateDirectories: true)
        fm.createFile(atPath: plistDir.appendingPathComponent("com.desktidy.sacrificial.plist").path, contents: Data("p".utf8))
        let id = ProbeIdentity.Measurement(
            executableURL: bundle.appendingPathComponent("Contents/MacOS/DeskTidySacrificialProbe"),
            basename: "DeskTidySacrificialProbe",
            appBundleURL: bundle,
            bundleIdentifier: "com.desktidy.sacrificial-probe",
            plistURL: plistDir.appendingPathComponent("com.desktidy.sacrificial.plist"),
            executableSHA256: hashOK)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let exp = iso.string(from: Date().addingTimeInterval(3600))
        let auth = Data("{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"\(root.path)\",\"bundleSHA256\":\"\(hashOK)\",\"sourceCommit\":\"\(commit)\",\"expiry\":\"\(exp)\",\"nonce\":\"\(nonce)\"}".utf8)
        let snap = AuthoritySnapshot(foreignOverlap: false, uninspectable: false, dualDeskTidy: false, rootCanonical: root.path)
        let desk = tmpDir("desk")
        let home = tmpDir("home")
        switch MutationBoundary.prepare(
            authBytes: auth, identity: id, compiledSourceCommit: commit,
            operation: .register, first: snap, second: snap,
            desktop: AuthorityGuard.canonicalize(desk.path),
            home: AuthorityGuard.canonicalize(home.path),
            protected: [], productionTarget: nil) {
        case .prepared(let g): return g
        case .refused: return nil
        }
    }

    private func runGrantPolicy() {
        guard let grant = makeGrant() else {
            check("B01", "hermetic grant for policy tests", false, "prepare refused")
            return
        }
        check("B01", "sacrificial plist + matching register is accepted",
              GrantedMutation.accept(grant: grant, requested: .register,
                                     plistName: GrantedMutation.sacrificialPlistName) == .accept)
        check("B02", "unregister request rejected against register grant",
              { if case .refuse(let s) = GrantedMutation.accept(grant: grant, requested: .unregister,
                                                               plistName: GrantedMutation.sacrificialPlistName) {
                  return s.contains("operation")
              }; return false }())
        check("B03", "production sort plist refused",
              { if case .refuse(let s) = GrantedMutation.accept(grant: grant, requested: .register,
                                                               plistName: "com.desktidy.sort.plist") {
                  return s.contains("sacrificial") || s.contains("protected")
              }; return false }())
        check("B04", "personal mover plist refused",
              { if case .refuse(let s) = GrantedMutation.accept(grant: grant, requested: .register,
                                                               plistName: "com.sicarii.desktop-autosort.plist") {
                  return s.contains("sacrificial") || s.contains("protected")
              }; return false }())
        check("B05", "prepare still does not construct a production adapter",
              ProductionMutationLedger.constructions == 0
                && ProductionMutationLedger.registerInvocations == 0)
    }

    private func runSourceSeams() {
        let root = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
        let probe = try? String(contentsOf: root.appendingPathComponent("probe/ProbeMain.swift"), encoding: .utf8)
        let prod = try? String(contentsOf: root.appendingPathComponent("probe/SMAdapterProduction.swift"), encoding: .utf8)
        let src = probe ?? ""
        let ad = prod ?? ""
        check("B10", "default path still stops before adapter without --commit-mutation",
              src.contains("if !args.contains(\"--commit-mutation\")")
                && src.contains("STOP_BEFORE_PRODUCTION_ADAPTER")
                && src.contains("exit(4)"))
        check("B11", "ungranted requestRegister stays disconnected",
              ad.contains("ungranted production mutation is not connected"))
        check("B12", "granted register is the only ServiceManagement register call site",
              ad.contains("try service.register()")
                && ad.contains("invokeGrantedRegister"))
        // Ungranted overload body must not call invokeGranted*
        if let ungrantedStart = ad.range(of: "func requestRegister(plistName: String) -> Result<Void, SMAdapterError>"),
           let next = ad.range(of: "func requestRegister(plistName: String, grant:") {
            let body = String(ad[ungrantedStart.lowerBound..<next.lowerBound])
            check("B13", "ungranted register overload does not invoke ServiceManagement",
                  !body.contains("invokeGranted") && !body.contains("service.register"))
        } else {
            check("B13", "ungranted register overload does not invoke ServiceManagement", false, "overloads not found")
        }
        let tests = try? String(contentsOf: root.appendingPathComponent("src/Phase1BTests.swift"), encoding: .utf8)
        let t = tests ?? ""
        check("B14", "Phase1BTests source does not construct a production mutator",
              !t.contains("Prod" + "uctionSMAdapter") && !t.contains("SMApp" + "Service"))
    }
}
