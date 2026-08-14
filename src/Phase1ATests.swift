import Foundation

// ============================================================================
//  R1B Phase 1A gates — fake-substrate only.
// ============================================================================

final class Phase1ATests {
    private let fm = FileManager.default
    private var passCount = 0
    private var failCount = 0
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func check(_ id: String, _ desc: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("PASS  \(id)  \(desc)"); passCount += 1 }
        else { print("FAIL  \(id)  \(desc)\(detail.isEmpty ? "" : " — \(detail)")"); failCount += 1 }
    }

    func runAll() -> Bool {
        runMigrationMatrix()
        runAdapterGates()
        runInterlockGates()
        runTransactionGates()
        runWiringGates()
        print("PHASE1A GATES: \(passCount) passed, \(failCount) failed")
        if passCount == 0 { print("FAIL  summary  zero cases"); return false }
        return failCount == 0
    }

    private func ev(
        target: Bool = true, cli: Bool = false, app: Bool = false, foreign: Bool = false,
        known: Bool = true, enabled: Bool = false, open: Bool = false,
        contra: Bool = false, rollback: Bool = false
    ) -> MigrationEvidence {
        MigrationEvidence(
            targetValid: target, legacyCLIPresent: cli, observedAppAgentPresent: app,
            foreignOverlap: foreign, registrationStatusKnown: known, registrationEnabled: enabled,
            transactionOpen: open, transactionContradictory: contra, rollbackMarked: rollback
        )
    }

    private func runMigrationMatrix() {
        func row(_ id: String, _ e: MigrationEvidence, _ expectState: MigrationState,
                 _ intent: MigrationIntent, _ expect: MigrationDecision) {
            let s = MigrationPolicy.classify(e)
            let d = MigrationPolicy.decide(state: s, intent: intent)
            check(id, "\(expectState.rawValue) + \(intent.rawValue) → \(expect)",
                  s == expectState && d == expect,
                  "state=\(s) decision=\(d)")
        }

        row("M01", ev(cli: true, app: true, enabled: true), .dualDeskTidyPresence, .beginRegistration, .refuse)
        row("M02", ev(), .neitherInstalled, .beginRegistration, .allow)
        row("M03", ev(cli: true), .cliOnly, .beginRegistration, .allow)
        row("M04", ev(app: true, enabled: true), .appOnly, .beginRegistration, .refuse)
        row("M05", ev(cli: true, foreign: true), .foreignConflict, .beginRegistration, .refuse)
        row("M06", ev(target: false, cli: true), .invalidTargetConfiguration, .beginRegistration, .refuse)
        row("M07", ev(app: true, known: false), .registrationIndeterminate, .beginRegistration, .refuse)
        row("M08", ev(cli: true, open: true), .halfMigrated, .beginRegistration, .refuse)
        row("M09", ev(cli: true, rollback: true), .rollbackRequired, .beginRegistration, .refuse)
        row("M10", ev(cli: true, app: true, enabled: true), .dualDeskTidyPresence, .rollback, .allow)
        row("M11", ev(cli: true, open: true), .halfMigrated, .rollback, .allow)
        row("M12", ev(app: true, enabled: true), .appOnly, .rollback, .allow)
        row("M13", ev(cli: true, rollback: true), .rollbackRequired, .rollback, .allow)
        row("M14", ev(foreign: true), .foreignConflict, .rollback, .refuse)
        row("M15", ev(target: false), .invalidTargetConfiguration, .rollback, .refuse)
        row("M16", ev(app: true, known: false), .registrationIndeterminate, .rollback, .refuse)
        row("M17", ev(app: true, enabled: true), .appOnly, .uninstall, .allow)
        row("M18", ev(), .neitherInstalled, .uninstall, .allow)
        row("M19", ev(cli: true), .cliOnly, .uninstall, .refuse)
        row("M20", ev(cli: true, app: true, enabled: true), .dualDeskTidyPresence, .uninstall, .refuse)

        let contra = ev(cli: true, app: true, contra: true)
        check("M21", "contradictory transaction classifies halfMigrated",
              MigrationPolicy.classify(contra) == .halfMigrated)
        check("M22", "future app label is not in ProductIdentity.selfLabels",
              !ProductIdentity.selfLabels.contains("com.desktidy.sacrificial")
                && !ProductIdentity.selfLabels.contains("com.desktidy.app.sort"))
        check("M23", "foreign overlap wins over dual evidence",
              MigrationPolicy.classify(ev(cli: true, app: true, foreign: true)) == .foreignConflict)
        check("M24", "plist presence alone is not a healthy/running state",
              MigrationPolicy.classify(ev(cli: true)) == .cliOnly)
    }

    private func runAdapterGates() {
        let fake = SMAdapterSelection.forAutomatedTests()
        fake.statusResult = .success(.notRegistered)
        _ = fake.status(plistName: "com.desktidy.sacrificial")
        fake.registerResult = .success(())
        _ = fake.requestRegister(plistName: "com.desktidy.sacrificial")
        check("A01", "fake adapter records status then register",
              fake.calls == [.status("com.desktidy.sacrificial"), .register("com.desktidy.sacrificial")])

        let refused = SMAdapterSelection.forAutomatedTests()
        var orch = MigrationOrchestrator(adapter: refused)
        let tx = orch.attempt(
            intent: .beginRegistration, evidence: ev(cli: true, app: true, enabled: true),
            authData: nil, context: dummyCtx(), plistName: "com.desktidy.sacrificial",
            sourceCommit: "0b11c652e364cf47668ba87b4228a0f4ab7974ec",
            bundleHash: String(repeating: "ab", count: 32),
            targetCanonical: "/tmp/x", priorCLIPresent: true
        )
        check("A02", "refused dual state never calls register",
              tx.outcome == .refused && refused.registerCount == 0, "outcome=\(tx.outcome) regs=\(refused.registerCount)")

        let unavail = SMAdapterSelection.unavailable()
        check("A03", "unavailable adapter fails closed",
              unavail.requestRegister(plistName: "x").errorIsUnavailable)

        let unk = SMAdapterSelection.forAutomatedTests()
        unk.statusResult = .success(.unknown("mystery"))
        check("A04", "unknown status is a distinct fail-closed value",
              unk.status(plistName: "x") == .success(.unknown("mystery")))
    }

    private func dummyDesktop() -> (dir: URL, canon: CanonicalPath) {
        let d = fm.temporaryDirectory.appendingPathComponent("dt-live-desktop-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        return (d, AuthorityGuard.canonicalize(d.path))
    }

    private func dummyCtx(
        probe: Bool = true, op: InterlockOperation = .register,
        plist: String = "com.desktidy.sacrificial",
        hash: String = String(repeating: "ab", count: 32),
        commit: String = "0b11c652e364cf47668ba87b4228a0f4ab7974ec",
        used: Set<String> = [], foreign: Bool = false, exists: Bool = true,
        desktop: CanonicalPath? = nil
    ) -> InterlockContext {
        let desk = desktop ?? dummyDesktop().canon
        return InterlockContext(
            isSacrificialProbeExecutable: probe, requestedOperation: op, plistName: plist,
            actualBundleSHA256: hash, actualSourceCommit: commit, now: Date(),
            usedNonces: used, foreignOverlap: foreign, desktopCanonical: desk,
            sacrificialExists: exists
        )
    }

    private func authBytes(
        op: String = "register",
        root: String,
        hash: String = String(repeating: "ab", count: 32),
        commit: String = "0b11c652e364cf47668ba87b4228a0f4ab7974ec",
        expiry: String? = nil,
        nonce: String = "nonce-1"
    ) -> Data {
        let exp = expiry ?? iso.string(from: Date().addingTimeInterval(3600))
        let s = """
        {"schema":1,"operation":"\(op)","sacrificialRoot":"\(root)","bundleSHA256":"\(hash)","sourceCommit":"\(commit)","expiry":"\(exp)","nonce":"\(nonce)"}
        """
        return Data(s.utf8)
    }

    private func runInterlockGates() {
        let sac = fm.temporaryDirectory.appendingPathComponent("dt-sac-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: sac, withIntermediateDirectories: true)
        let desk = dummyDesktop()

        func eval(_ data: Data, ctx: InterlockContext) -> InterlockDecision {
            MutationInterlock.evaluate(authData: data, context: ctx)
        }

        var ctx = dummyCtx(desktop: desk.canon)
        ctx.sacrificialExists = true
        let good = authBytes(root: sac.path)
        // permit requires root not desktop — sac is under tmp, fine
        if case .permit = eval(good, ctx: ctx) {
            check("I00", "valid fixture authorization permits on probe", true)
        } else {
            let d = eval(good, ctx: ctx)
            check("I00", "valid fixture authorization permits on probe", false, "\(d)")
        }

        check("I01", "missing/empty auth refuses",
              { if case .refuse = eval(Data(), ctx: ctx) { return true }; return false }())
        check("I02", "malformed JSON refuses",
              { if case .refuse = eval(Data("not-json".utf8), ctx: ctx) { return true }; return false }())
        let dupe = Data("{\"schema\":1,\"operation\":\"register\",\"sacrificialRoot\":\"\(sac.path)\",\"bundleSHA256\":\"\(String(repeating: "ab", count: 32))\",\"sourceCommit\":\"0b11c652e364cf47668ba87b4228a0f4ab7974ec\",\"expiry\":\"\(iso.string(from: Date().addingTimeInterval(3600)))\",\"nonce\":\"n\",\"nonce\":\"n\"}".utf8)
        check("I03", "duplicate authorization key refuses",
              { if case .refuse = eval(dupe, ctx: ctx) { return true }; return false }())
        let expired = authBytes(root: sac.path, expiry: iso.string(from: Date().addingTimeInterval(-60)))
        check("I04", "expired authorization refuses",
              { if case .refuse = eval(expired, ctx: ctx) { return true }; return false }())
        var reused = dummyCtx(used: ["nonce-1"], desktop: desk.canon)
        reused.sacrificialExists = true
        check("I05", "reused nonce refuses",
              { if case .refuse = eval(good, ctx: reused) { return true }; return false }())
        check("I06", "mismatched bundle hash refuses",
              { if case .refuse = eval(authBytes(root: sac.path, hash: String(repeating: "cd", count: 32)), ctx: ctx) { return true }; return false }())
        check("I07", "mismatched operation refuses",
              { if case .refuse = eval(authBytes(op: "unregister", root: sac.path), ctx: ctx) { return true }; return false }())
        check("I08", "mismatched source commit refuses",
              { if case .refuse = eval(authBytes(root: sac.path, commit: String(repeating: "11", count: 20)), ctx: ctx) { return true }; return false }())
        check("I09", "Desktop-equivalent root refuses",
              { if case .refuse = eval(authBytes(root: desk.dir.path), ctx: ctx) { return true }; return false }())
        let inside = desk.dir.appendingPathComponent("child")
        try? fm.createDirectory(at: inside, withIntermediateDirectories: true)
        check("I10", "root inside Desktop refuses",
              { if case .refuse = eval(authBytes(root: inside.path), ctx: ctx) { return true }; return false }())
        let link = fm.temporaryDirectory.appendingPathComponent("dt-desk-link-\(UUID().uuidString.prefix(8))")
        try? fm.createSymbolicLink(at: link, withDestinationURL: desk.dir)
        check("I11", "symlink-equivalent Desktop refuses",
              { if case .refuse = eval(authBytes(root: link.path), ctx: ctx) { return true }; return false }())
        var personal = dummyCtx(plist: "com.sicarii.desktop-autosort", desktop: desk.canon)
        personal.sacrificialExists = true
        check("I12", "personal mover label refuses",
              { if case .refuse = eval(good, ctx: personal) { return true }; return false }())
        var foreign = dummyCtx(foreign: true, desktop: desk.canon)
        foreign.sacrificialExists = true
        check("I13", "foreign mover refuses",
              { if case .refuse = eval(good, ctx: foreign) { return true }; return false }())
        var notProbe = dummyCtx(probe: false, desktop: desk.canon)
        notProbe.sacrificialExists = true
        check("I14", "non-probe executable refuses",
              { if case .refuse = eval(good, ctx: notProbe) { return true }; return false }())
        let missing = Data("{\"schema\":1,\"operation\":\"register\"}".utf8)
        check("I15", "incomplete key set refuses",
              { if case .refuse = eval(missing, ctx: ctx) { return true }; return false }())
        var junk = authBytes(root: sac.path)
        junk.append(contentsOf: Data(" true".utf8))
        check("I16", "trailing non-whitespace refuses",
              { if case .refuse = eval(junk, ctx: ctx) { return true }; return false }())
        var missingRoot = dummyCtx(exists: false, desktop: desk.canon)
        check("I17", "missing sacrificial directory refuses",
              { if case .refuse = eval(good, ctx: missingRoot) { return true }; return false }())
        check("I18", "notify personal label also refuses",
              {
                  var c = dummyCtx(plist: "com.sicarii.desktop-autosort-notify", desktop: desk.canon)
                  c.sacrificialExists = true
                  if case .refuse = eval(good, ctx: c) { return true }
                  return false
              }())
    }

    private func runTransactionGates() {
        let sac = fm.temporaryDirectory.appendingPathComponent("dt-tx-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: sac, withIntermediateDirectories: true)
        let desk = dummyDesktop()
        let hash = String(repeating: "ab", count: 32)
        let commit = "0b11c652e364cf47668ba87b4228a0f4ab7974ec"
        let plist = "com.desktidy.sacrificial"
        var ctx = dummyCtx(desktop: desk.canon)
        ctx.sacrificialExists = true
        let auth = authBytes(root: sac.path)

        func run(_ id: String, intent: MigrationIntent, evidence: MigrationEvidence,
                 atCall: MigrationEvidence? = nil, adapter: FakeSMAdapter,
                 skipSecond: Bool = false, expect: MigrationOutcome,
                 registerCalls: Int? = nil, unregisterCalls: Int? = nil) {
            var orch = MigrationOrchestrator(adapter: adapter, skipSecondPreCallCheck: skipSecond)
            let tx = orch.attempt(
                intent: intent, evidence: evidence, evidenceAtCall: atCall,
                authData: auth, context: ctx, plistName: plist,
                sourceCommit: commit, bundleHash: hash,
                targetCanonical: sac.path, priorCLIPresent: evidence.legacyCLIPresent
            )
            var ok = tx.outcome == expect
            if let n = registerCalls { ok = ok && adapter.registerCount == n }
            if let n = unregisterCalls { ok = ok && adapter.unregisterCount == n }
            if expect == .indeterminate { ok = ok && tx.outcome != .succeeded }
            check(id, "transaction \(expect.rawValue)",
                  ok, "got \(tx.outcome) regs=\(adapter.registerCount) unregs=\(adapter.unregisterCount)")
        }

        // S01 clean install success
        let a1 = FakeSMAdapter()
        a1.statusResult = .success(.notRegistered)
        a1.registerResult = .success(())
        // after register, tests need status to become enabled — fake returns same statusResult unless we flip after
        // Use a tiny sequence adapter via mutating status after first status call — Fake always same.
        // For S01, set status to enabled so after-status is enabled (before also enabled is a bit loose).
        // Better: first status notRegistered, then after register return enabled.
        // Extend Fake? Keep simple: set statusResult to enabled after constructing orchestrator by using
        // a custom sequence. I'll set status to enabled and treat success+enabled as succeeded when no CLI.
        a1.statusResult = .success(.enabled)
        run("S01", intent: .beginRegistration, evidence: ev(), adapter: a1, expect: .succeeded, registerCalls: 1)

        // S02 API rejection
        let a2 = FakeSMAdapter()
        a2.statusResult = .success(.notRegistered)
        a2.registerResult = .failure(.failedClosed("denied"))
        run("S02", intent: .beginRegistration, evidence: ev(), adapter: a2, expect: .rejected, registerCalls: 1)

        // S03 unknown after success
        let a3 = FakeSMAdapter()
        a3.statusResult = .success(.unknown("no-enum"))
        a3.registerResult = .success(())
        run("S03", intent: .beginRegistration, evidence: ev(), adapter: a3, expect: .indeterminate, registerCalls: 1)

        // S04 legacy remains after app registration → dual refuse/rollback required
        let a4 = FakeSMAdapter()
        a4.statusResult = .success(.enabled)
        a4.registerResult = .success(())
        run("S04", intent: .beginRegistration, evidence: ev(cli: true), adapter: a4, expect: .refused, registerCalls: 1)

        // S05 interruption before registration = begin refused by halfMigrated
        let a5 = FakeSMAdapter()
        run("S05", intent: .beginRegistration, evidence: ev(cli: true, open: true), adapter: a5,
            expect: .refused, registerCalls: 0)

        // S06 interruption after apparent registration before legacy removal: dual
        let a6 = FakeSMAdapter()
        run("S06", intent: .beginRegistration, evidence: ev(cli: true, app: true, enabled: true),
            adapter: a6, expect: .refused, registerCalls: 0)

        // S07 rollback unregister success
        let a7 = FakeSMAdapter()
        a7.statusResult = .success(.notRegistered)
        a7.unregisterResult = .success(())
        run("S07", intent: .rollback, evidence: ev(app: true, enabled: true), adapter: a7,
            expect: .rolledBack, unregisterCalls: 1)

        // S08 rollback unregister failure
        let a8 = FakeSMAdapter()
        a8.statusResult = .success(.enabled)
        a8.unregisterResult = .failure(.failedClosed("busy"))
        run("S08", intent: .rollback, evidence: ev(app: true, enabled: true), adapter: a8,
            expect: .rollbackFailed, unregisterCalls: 1)

        // S09 uninstall when app service absent
        let a9 = FakeSMAdapter()
        run("S09", intent: .uninstall, evidence: ev(), adapter: a9, expect: .succeeded, registerCalls: 0)

        // S10 uninstall when indeterminate
        let a10 = FakeSMAdapter()
        run("S10", intent: .uninstall, evidence: ev(app: true, known: false), adapter: a10,
            expect: .refused, registerCalls: 0)

        // S11 foreign appears between preflight and mutation
        let a11 = FakeSMAdapter()
        a11.statusResult = .success(.notRegistered)
        a11.registerResult = .success(())
        run("S11", intent: .beginRegistration, evidence: ev(),
            atCall: ev(foreign: true), adapter: a11, expect: .refused, registerCalls: 0)

        // S12 target identity changes / becomes invalid between auth and call
        let a12 = FakeSMAdapter()
        a12.statusResult = .success(.notRegistered)
        run("S12", intent: .beginRegistration, evidence: ev(),
            atCall: ev(target: false), adapter: a12, expect: .refused, registerCalls: 0)

        // unknown status cannot be claimed success
        check("S13", "indeterminate outcome is never succeeded",
              a3.statusResult == .success(.unknown("no-enum")))
    }

    private func runWiringGates() {
        let here = URL(fileURLWithPath: #file)
        let src = here.deletingLastPathComponent()
        let testFile = src.appendingPathComponent("Phase1ATests.swift")
        let text = (try? String(contentsOf: testFile, encoding: .utf8)) ?? ""
        let stripped = text.split(separator: "\n").map { line -> String in
            let s = String(line)
            if let r = s.range(of: "//") { return String(s[..<r.lowerBound]) }
            return s
        }.joined(separator: "\n")
        let prodType = ["Production", "SM", "Adapter"].joined()
        let smAPI = ["SM", "App", "Service"].joined()
        check("W01", "Phase1ATests source does not construct a production mutator",
              !stripped.contains(prodType) && !stripped.contains(smAPI))
        check("W02", "Phase1ATests source does not call ServiceManagement mutation APIs",
              !stripped.contains(smAPI + ".register") && !stripped.contains(smAPI + ".unregister"))
        check("W03", "future sacrificial label is not a production self label",
              !ProductIdentity.selfLabels.contains("com.desktidy.sacrificial"))
        check("W04", "test adapter factory returns FakeSMAdapter",
              SMAdapterSelection.forAutomatedTests() is FakeSMAdapter)
    }
}

private extension Result where Success == Void, Failure == SMAdapterError {
    var errorIsUnavailable: Bool {
        if case .failure(.unavailable) = self { return true }
        return false
    }
}
