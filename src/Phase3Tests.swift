import Foundation

// ============================================================================
//  Phase 3 identity-registry and migration-architecture gates. Fake only.
// ============================================================================

final class Phase3Tests {
    private var pass = 0
    private var fail = 0

    private func check(_ id: String, _ desc: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("PASS  \(id)  \(desc)"); pass += 1 }
        else { print("FAIL  \(id)  \(desc)\(detail.isEmpty ? "" : " — \(detail)")"); fail += 1 }
    }

    func runAll() -> Bool {
        runRegistry()
        runMigrationBounds()
        print("PHASE3 GATES: \(pass) passed, \(fail) failed")
        if pass == 0 { print("FAIL  summary  zero cases"); return false }
        return fail == 0
    }

    private func runRegistry() {
        check("R01", "production self-labels remain the CLI pair",
              ProductIdentity.selfLabels == ["com.desktidy.sort", "com.desktidy.notify"])
        check("R02", "observed sacrificial label is not a production self-label",
              !ProductIdentity.selfLabels.contains(ServiceIdentityRegistry.sacrificialObservedLabel))
        check("R03", "ProductIdentity.selfLabels come from the registry",
              ProductIdentity.selfLabels == ServiceIdentityRegistry.productionSelfLabels)
        check("R04", "configured vs observed disagreement is refused",
              ServiceIdentityRegistry.disagreement(
                configured: "com.desktidy.app.sort",
                observed: "com.desktidy.sacrificial") != nil)
        check("R05", "matching configured/observed identity is accepted",
              ServiceIdentityRegistry.disagreement(
                configured: "com.desktidy.sacrificial",
                observed: "com.desktidy.sacrificial") == nil)
        check("R06", "personal labels are never mutation targets",
              ServiceIdentityRegistry.isNeverTarget("com.sicarii.desktop-autosort")
                && ServiceIdentityRegistry.isNeverTarget("com.sicarii.desktop-autosort-notify"))
        check("R07", "registry records sacrificial observation class as observedOnce",
              ServiceIdentityRegistry.record(role: .sacrificialProbe).observation == .observedOnce)
        check("R08", "menu-bar bundle is not an accepted agent self-label",
              !ProductIdentity.selfLabels.contains("com.desktidy.app"))
    }

    private func runMigrationBounds() {
        let fm = FileManager.default
        let sac = fm.temporaryDirectory.appendingPathComponent("dt-p3-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: sac, withIntermediateDirectories: true)
        let fakeDesk = fm.temporaryDirectory.appendingPathComponent("dt-p3-desk-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: fakeDesk, withIntermediateDirectories: true)

        check("M01", "fixture Desktop-equivalent target is refused",
              MigrationPolicy.isLiveDesktopTarget(fakeDesk.path, desktop: fakeDesk.path))
        check("M02", "disjoint sacrificial target is not treated as Desktop",
              !MigrationPolicy.isLiveDesktopTarget(sac.path, desktop: fakeDesk.path))

        let fake = FakeSMAdapter()
        fake.statusResult = .success(.notRegistered)
        fake.registerResult = .success(())
        let orch = MigrationOrchestrator(adapter: fake)
        let ev = MigrationEvidence(
            targetValid: true, legacyCLIPresent: false, observedAppAgentPresent: false,
            foreignOverlap: false, registrationStatusKnown: true, registrationEnabled: false,
            transactionOpen: false, transactionContradictory: false, rollbackMarked: false)
        let ctx = InterlockContext(
            isSacrificialProbeExecutable: true, requestedOperation: .register,
            plistName: "com.desktidy.sacrificial", actualBundleSHA256: String(repeating: "ab", count: 32),
            actualSourceCommit: "d259b2b971b83ce89e34426af791422adea8e472", now: Date(),
            usedNonces: [], foreignOverlap: false,
            desktopCanonical: AuthorityGuard.canonicalize(fakeDesk.path), sacrificialExists: true)
        let liveDesk = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path
        let txDesk = orch.attempt(
            intent: .beginRegistration, evidence: ev, authData: nil, context: ctx,
            plistName: "com.desktidy.sacrificial",
            sourceCommit: "d259b2b971b83ce89e34426af791422adea8e472",
            bundleHash: String(repeating: "ab", count: 32),
            targetCanonical: liveDesk, priorCLIPresent: false)
        check("M03", "orchestrator refuses a live Desktop production-migration target",
              txDesk.outcome == .refused && fake.registerCount == 0)

        let txPersonal = orch.attempt(
            intent: .beginRegistration, evidence: ev, authData: nil, context: ctx,
            plistName: "com.sicarii.desktop-autosort.plist",
            sourceCommit: "d259b2b971b83ce89e34426af791422adea8e472",
            bundleHash: String(repeating: "ab", count: 32),
            targetCanonical: sac.path, priorCLIPresent: false)
        check("M04", "orchestrator refuses personal-mover plist",
              txPersonal.outcome == .refused && fake.registerCount == 0)

        let txUnknown = orch.attempt(
            intent: .beginRegistration, evidence: ev, authData: nil, context: ctx,
            plistName: "com.desktidy.app.sort.plist",
            sourceCommit: "d259b2b971b83ce89e34426af791422adea8e472",
            bundleHash: String(repeating: "ab", count: 32),
            targetCanonical: sac.path, priorCLIPresent: false)
        check("M05", "unobserved production app-agent plist is not a known identity",
              txUnknown.outcome == .refused && fake.registerCount == 0)

        check("M06", "only cliOnly or neitherInstalled may begin",
              MigrationPolicy.decide(state: .cliOnly, intent: .beginRegistration) == .allow
                && MigrationPolicy.decide(state: .neitherInstalled, intent: .beginRegistration) == .allow
                && MigrationPolicy.decide(state: .dualDeskTidyPresence, intent: .beginRegistration) == .refuse
                && MigrationPolicy.decide(state: .appOnly, intent: .beginRegistration) == .refuse)

        check("M07", "rollback never targets the personal mover",
              ServiceIdentityRegistry.isNeverTarget("com.sicarii.desktop-autosort")
                && MigrationPolicy.decide(state: .appOnly, intent: .rollback) == .allow)
    }
}
