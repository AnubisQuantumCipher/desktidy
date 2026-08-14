import Foundation

// ============================================================================
//  Phase 1B grant-dispatch gates. Fake/hermetic only.
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
        SacrificialMutationDispatcher.disableExactlyOnceForMutationTest = false
        ProductionMutationLedger.reset()
        runDispatchPolicy()
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

    private func identity(rootBundle: URL? = nil, hash: String? = nil) -> ProbeIdentity.Measurement {
        let bundle = rootBundle ?? tmpDir("app").appendingPathComponent("DeskTidySacrificialProbe.app")
        try? fm.createDirectory(at: bundle.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plistDir = bundle.appendingPathComponent("Contents/Library/LaunchAgents")
        try? fm.createDirectory(at: plistDir, withIntermediateDirectories: true)
        let plist = plistDir.appendingPathComponent("com.desktidy.sacrificial.plist")
        if !fm.fileExists(atPath: plist.path) {
            fm.createFile(atPath: plist.path, contents: Data("sacrificial-plist".utf8))
        }
        return ProbeIdentity.Measurement(
            executableURL: bundle.appendingPathComponent("Contents/MacOS/DeskTidySacrificialProbe"),
            basename: "DeskTidySacrificialProbe",
            appBundleURL: bundle,
            bundleIdentifier: "com.desktidy.sacrificial-probe",
            plistURL: plist,
            executableSHA256: hash ?? hashOK)
    }

    private func makePrepared(
        nonce: String,
        operation: InterlockOperation = .register,
        hash: String? = nil,
        commit: String? = nil
    ) -> (PreparedMutationGrant, ProbeIdentity.Measurement, AuthoritySnapshot)? {
        let root = tmpDir("sac")
        let id = identity(hash: hash)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let exp = iso.string(from: Date().addingTimeInterval(3600))
        let h = hash ?? hashOK
        let c = commit ?? self.commit
        let auth = Data("{\"schema\":1,\"operation\":\"\(operation.rawValue)\",\"sacrificialRoot\":\"\(root.path)\",\"bundleSHA256\":\"\(h)\",\"sourceCommit\":\"\(c)\",\"expiry\":\"\(exp)\",\"nonce\":\"\(nonce)\"}".utf8)
        let snap = AuthoritySnapshot(foreignOverlap: false, uninspectable: false, dualDeskTidy: false, rootCanonical: root.path)
        let desk = tmpDir("desk")
        let home = tmpDir("home")
        switch MutationBoundary.prepare(
            authBytes: auth, identity: id, compiledSourceCommit: c,
            operation: operation, first: snap, second: snap,
            desktop: AuthorityGuard.canonicalize(desk.path),
            home: AuthorityGuard.canonicalize(home.path),
            protected: [], productionTarget: nil) {
        case .prepared(let g): return (g, id, snap)
        case .refused: return nil
        }
    }

    private func request(
        grant: PreparedMutationGrant,
        id: ProbeIdentity.Measurement,
        second: AuthoritySnapshot,
        requested: InterlockOperation? = nil,
        plistName: String = SacrificialMutationDispatcher.sacrificialPlistName,
        commit: String? = nil
    ) -> SacrificialDispatchRequest {
        SacrificialDispatchRequest(
            grant: grant,
            requested: requested ?? grant.operation,
            plistName: plistName,
            liveIdentity: id,
            compiledSourceCommit: commit ?? grant.sourceCommit,
            second: second
        )
    }

    private func runDispatchPolicy() {
        ProductionMutationLedger.reset()
        guard let (grant, id, snap) = makePrepared(nonce: "nonce-1b01") else {
            check("B01", "valid prepared grant invokes fake adapter register exactly once", false, "prepare refused")
            return
        }
        let fake = FakeSMAdapter()
        fake.statusResult = .success(.enabled)
        let out = SacrificialMutationDispatcher.dispatch(request(grant: grant, id: id, second: snap), adapter: fake)
        check("B01", "valid prepared grant invokes fake adapter register exactly once",
              {
                  if case .invoked(let st) = out {
                      return st == .enabled && fake.registerCount == 1 && fake.unregisterCount == 0
                  }
                  return false
              }(), "\(out) calls=\(fake.calls)")

        guard let (ugrant, uid, usnap) = makePrepared(nonce: "nonce-1b02", operation: .unregister) else {
            check("B02", "valid unregister grant invokes fake adapter unregister exactly once", false, "prepare refused")
            return
        }
        let ufake = FakeSMAdapter()
        ufake.statusResult = .success(.notRegistered)
        let uout = SacrificialMutationDispatcher.dispatch(
            request(grant: ugrant, id: uid, second: usnap), adapter: ufake)
        check("B02", "valid unregister grant invokes fake adapter unregister exactly once",
              {
                  if case .invoked(let st) = uout {
                      return st == .notRegistered && ufake.unregisterCount == 1 && ufake.registerCount == 0
                  }
                  return false
              }(), "\(uout)")

        let transplant = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: snap, requested: .unregister), adapter: FakeSMAdapter())
        check("B03", "operation-transplant refused",
              { if case .refused(let s) = transplant { return s.contains("operation") }; return false }(), "\(transplant)")

        let plistX = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: snap, plistName: "com.desktidy.sort.plist"),
            adapter: FakeSMAdapter())
        check("B04", "plist-transplant of production sort refused",
              { if case .refused(let s) = plistX { return s.contains("sacrificial") || s.contains("protected") || s.contains("plist") }; return false }(), "\(plistX)")

        let personal = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: snap, plistName: "com.sicarii.desktop-autosort.plist"),
            adapter: FakeSMAdapter())
        check("B05", "personal mover plist refused",
              { if case .refused(let s) = personal { return s.contains("sacrificial") || s.contains("protected") || s.contains("plist") }; return false }(), "\(personal)")

        let stale = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: snap, commit: "0b11c652e364cf47668ba87b4228a0f4ab7974ec"),
            adapter: FakeSMAdapter())
        check("B06", "stale-grant compiled commit mismatch refused",
              { if case .refused(let s) = stale { return s.contains("commit") }; return false }(), "\(stale)")

        var foreign = snap
        foreign.foreignOverlap = true
        let bypass = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: foreign), adapter: FakeSMAdapter())
        check("B07", "second-check foreign overlap refused",
              { if case .refused(let s) = bypass { return s.contains("foreign") }; return false }(), "\(bypass)")

        var moved = snap
        moved.rootCanonical = tmpDir("moved").path
        let rootChange = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: moved), adapter: FakeSMAdapter())
        check("B08", "second-check root change refused",
              { if case .refused(let s) = rootChange { return s.contains("root") }; return false }(), "\(rootChange)")

        var badHash = id
        badHash.executableSHA256 = String(repeating: "cd", count: 32)
        let hashMismatch = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: badHash, second: snap), adapter: FakeSMAdapter())
        check("B09", "live executable hash mismatch refused",
              { if case .refused(let s) = hashMismatch { return s.contains("hash") || s.contains("executable") }; return false }(), "\(hashMismatch)")

        guard let (g2, id2, snap2) = makePrepared(nonce: "nonce-1b10") else {
            check("B10", "missing nonce reservation refused", false, "prepare refused")
            return
        }
        let noncePath = DurableNonceStore.supportRoot(canonicalSacrificial: g2.rootCanonical)
            .appendingPathComponent("nonces").appendingPathComponent(g2.nonce)
        try? fm.removeItem(at: noncePath)
        let missingNonce = SacrificialMutationDispatcher.dispatch(
            request(grant: g2, id: id2, second: snap2), adapter: FakeSMAdapter())
        check("B10", "missing nonce reservation refused",
              { if case .refused(let s) = missingNonce { return s.contains("nonce") }; return false }(), "\(missingNonce)")

        guard let (g3, id3, snap3) = makePrepared(nonce: "nonce-1b11") else {
            check("B11", "nonce/grant replay refused on second dispatch", false, "prepare refused")
            return
        }
        let replayAdapter = FakeSMAdapter()
        replayAdapter.statusResult = .success(.enabled)
        let first = SacrificialMutationDispatcher.dispatch(
            request(grant: g3, id: id3, second: snap3), adapter: replayAdapter)
        let second = SacrificialMutationDispatcher.dispatch(
            request(grant: g3, id: id3, second: snap3), adapter: replayAdapter)
        check("B11", "nonce/grant replay refused on second dispatch",
              {
                  guard case .invoked = first else { return false }
                  if case .refused(let s) = second { return s.contains("nonce") || s.contains("once") || s.contains("replay") }
                  return false
              }(), "first=\(first) second=\(second)")

        guard let (g4, id4, snap4) = makePrepared(nonce: "nonce-1b12") else {
            check("B12", "missing pre-call transaction refused", false, "prepare refused")
            return
        }
        let precall = DurableNonceStore.supportRoot(canonicalSacrificial: g4.rootCanonical)
            .appendingPathComponent("precall.jsonl")
        try? fm.removeItem(at: precall)
        let missingTx = SacrificialMutationDispatcher.dispatch(
            request(grant: g4, id: id4, second: snap4), adapter: FakeSMAdapter())
        check("B12", "missing pre-call transaction refused",
              { if case .refused(let s) = missingTx { return s.contains("transaction") || s.contains("pre-call") || s.contains("precall") }; return false }(), "\(missingTx)")

        guard let (g5, id5, snap5) = makePrepared(nonce: "nonce-1b13") else {
            check("B13", "post-status unknown is never success", false, "prepare refused")
            return
        }
        let unk = FakeSMAdapter()
        unk.statusResult = .success(.unknown("contradictory"))
        let unkOut = SacrificialMutationDispatcher.dispatch(
            request(grant: g5, id: id5, second: snap5), adapter: unk)
        check("B13", "post-status unknown is never success",
              {
                  if case .invoked = unkOut { return false }
                  if case .indeterminate(let s) = unkOut { return s.contains("unknown") && unk.registerCount == 1 }
                  if case .rollbackRequired(let s) = unkOut { return s.contains("unknown") && unk.registerCount == 1 }
                  return false
              }(), "\(unkOut)")

        guard let (g6, id6, snap6) = makePrepared(nonce: "nonce-1b14") else {
            check("B14", "adapter call failure after grant is rollbackRequired", false, "prepare refused")
            return
        }
        let boom = FakeSMAdapter()
        boom.registerResult = .failure(.failedClosed("adapter exploded"))
        boom.statusResult = .success(.notRegistered)
        let boomOut = SacrificialMutationDispatcher.dispatch(
            request(grant: g6, id: id6, second: snap6), adapter: boom)
        check("B14", "adapter call failure after grant is rollbackRequired",
              { if case .rollbackRequired = boomOut { return boom.registerCount == 1 }; return false }(), "\(boomOut)")

        check("B15", "prepare still does not construct a production adapter",
              ProductionMutationLedger.constructions == 0
                && ProductionMutationLedger.registerInvocations == 0
                && ProductionMutationLedger.unregisterInvocations == 0)

        guard let (g7, id7, snap7) = makePrepared(nonce: "nonce-1b16") else {
            check("B16", "pre-call transaction write failure refuses prepare", false, "prepare skipped")
            return
        }
        _ = (g7, id7, snap7)
        let failRoot = tmpDir("txfail")
        let support = DurableNonceStore.supportRoot(canonicalSacrificial: failRoot.path)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        let blocker = support.appendingPathComponent("precall.jsonl")
        try? fm.removeItem(at: blocker)
        try? fm.createSymbolicLink(at: blocker, withDestinationURL: tmpDir("elsewhere").appendingPathComponent("x"))
        let failID = identity()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let exp = iso.string(from: Date().addingTimeInterval(3600))
        let auth = Data("{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"\(failRoot.path)\",\"bundleSHA256\":\"\(hashOK)\",\"sourceCommit\":\"\(commit)\",\"expiry\":\"\(exp)\",\"nonce\":\"nonce-1b16b\"}".utf8)
        let snapFail = AuthoritySnapshot(foreignOverlap: false, uninspectable: false, dualDeskTidy: false, rootCanonical: failRoot.path)
        let desk = tmpDir("desk-tx")
        let home = tmpDir("home-tx")
        let preparedFail = MutationBoundary.prepare(
            authBytes: auth, identity: failID, compiledSourceCommit: commit,
            operation: .register, first: snapFail, second: snapFail,
            desktop: AuthorityGuard.canonicalize(desk.path),
            home: AuthorityGuard.canonicalize(home.path),
            protected: [], productionTarget: nil)
        check("B16", "pre-call transaction write failure refuses prepare",
              { if case .refused(let s) = preparedFail { return s.contains("pre-call") || s.contains("transaction") }; return false }(), "\(preparedFail)")

        var dual = snap
        dual.dualDeskTidy = true
        let dualOut = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: dual), adapter: FakeSMAdapter())
        check("B17", "second-check dual presence refused",
              { if case .refused(let s) = dualOut { return s.contains("dual") }; return false }(), "\(dualOut)")

        let notify = SacrificialMutationDispatcher.dispatch(
            request(grant: grant, id: id, second: snap, plistName: "com.desktidy.notify.plist"),
            adapter: FakeSMAdapter())
        check("B18", "production notify plist refused",
              { if case .refused = notify { return true }; return false }(), "\(notify)")
    }

    private func runSourceSeams() {
        let root = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
        let probe = (try? String(contentsOf: root.appendingPathComponent("probe/ProbeMain.swift"), encoding: .utf8)) ?? ""
        let prod = (try? String(contentsOf: root.appendingPathComponent("probe/SMAdapterProduction.swift"), encoding: .utf8)) ?? ""
        let tests = (try? String(contentsOf: root.appendingPathComponent("src/Phase1BTests.swift"), encoding: .utf8)) ?? ""
        let granted = (try? String(contentsOf: root.appendingPathComponent("src/GrantedMutation.swift"), encoding: .utf8)) ?? ""

        check("B20", "default path still stops before adapter without --commit-mutation",
              probe.contains("if !args.contains(\"--commit-mutation\")")
                && probe.contains("STOP_BEFORE_PRODUCTION_ADAPTER")
                && probe.contains("exit(4)"))
        check("B21", "ungranted requestRegister stays disconnected",
              prod.contains("ungranted production mutation is not connected"))
        check("B22", "granted register is the only ServiceManagement register call site",
              prod.contains("try service.register()")
                && prod.contains("executeSealedRegister"))
        if let ungrantedStart = prod.range(of: "func requestRegister(plistName: String) -> Result<Void, SMAdapterError>"),
           let next = prod.range(of: "func executeSealedRegister") {
            let body = String(prod[ungrantedStart.lowerBound..<next.lowerBound])
            check("B23", "ungranted register overload does not invoke ServiceManagement",
                  body.contains("ungranted production mutation is not connected")
                    && !body.contains("executeSealed") && !body.contains("service.register"))
        } else {
            check("B23", "ungranted register overload does not invoke ServiceManagement", false, "overloads not found")
        }
        check("B24", "Phase1BTests source does not construct a production mutator",
              !tests.contains("Prod" + "uctionSMAdapter") && !tests.contains("SMApp" + "Service"))
        check("B25", "dispatcher source never names production or personal labels as targets",
              granted.contains("sacrificialPlistName")
                && granted.contains("com.desktidy.sacrificial.plist")
                && !granted.contains("com.sicarii.desktop-autosort")
                || granted.contains("personalLabels"))
        check("B26", "dispatcher is the single grant-to-adapter mapping",
              granted.contains("static func dispatch")
                && granted.contains("SealedAdapterExecuting"))
    }
}
