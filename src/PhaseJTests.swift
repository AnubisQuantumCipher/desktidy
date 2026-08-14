import Foundation

// ============================================================================
// Phase J — hermetic lifecycle, migration, and receipt-retention contracts.
// Every service adapter here is FakeSMAdapter and every path is a disposable
// temporary directory. These tests must never select a production mutator.
// ============================================================================

final class PhaseJTests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private func check(_ id: String, _ description: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("PASS  \(id)  \(description)")
            pass += 1
        } else {
            print("FAIL  \(id)  \(description)\(detail.isEmpty ? "" : " — \(detail)")")
            fail += 1
        }
    }

    func runAll() -> Bool {
        runLifecycleMatrixCompletenessContract()
        runOwnedDryRunContract()
        runOwnershipAndAuthorizationRefusalContract()
        runRestartRecoverableInstallContract()
        runUninstallAndReceiptRetentionContract()
        runLifecycleClassificationContract()
        print("PHASE J GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func temporaryDirectory(_ name: String) -> URL {
        let directory = fm.temporaryDirectory.appendingPathComponent("desktidy-phasej-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func evidence(
        targetValid: Bool = true,
        cli: Bool = false,
        app: Bool = false,
        foreign: Bool = false,
        enabled: Bool = false,
        known: Bool = true,
        transactionOpen: Bool = false,
        contradictory: Bool = false,
        rollbackMarked: Bool = false,
        stage: MigrationRecoveryStage? = nil,
        authorized: Bool = true,
        uninstallRequested: Bool = false,
        paused: Bool = false,
        ledgerHealthy: Bool = true,
        notificationsHealthy: Bool = true,
        undoPending: Bool = false,
        version: PhaseJVersionTransition = .none,
        rebootRequired: Bool = false
    ) -> PhaseJLifecycleEvidence {
        PhaseJLifecycleEvidence(
            migration: MigrationEvidence(
                targetValid: targetValid,
                legacyCLIPresent: cli,
                observedAppAgentPresent: app,
                foreignOverlap: foreign,
                registrationStatusKnown: known,
                registrationEnabled: enabled,
                transactionOpen: transactionOpen,
                transactionContradictory: contradictory,
                rollbackMarked: rollbackMarked
            ),
            migrationStage: stage,
            authorizationGranted: authorized,
            uninstallRequested: uninstallRequested,
            paused: paused,
            ledgerHealthy: ledgerHealthy,
            notificationsHealthy: notificationsHealthy,
            undoPending: undoPending,
            versionTransition: version,
            rebootRequired: rebootRequired
        )
    }

    private func app(
        _ name: String,
        service: FakeSMAdapter,
        legacy: FakeLegacyCLIAdapter,
        receiptIDPrefix: String = "J"
    ) -> (root: URL, records: FileMigrationRecordStore, receipts: PhaseJLifecycleReceiptLedger, app: PhaseJLifecycleApp) {
        let root = temporaryDirectory(name)
        let target = root.appendingPathComponent("target", isDirectory: true)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        let recordStore = FileMigrationRecordStore(url: root.appendingPathComponent("migration.json"))
        let receiptLedger = PhaseJLifecycleReceiptLedger(url: root.appendingPathComponent("phase-j-receipts.jsonl"))
        let identity = ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)!
        service.observedTargetCanonical = AuthorityGuard.canonicalize(target.path).path
        let coordinator = FakeRecoverableMigrationCoordinator(
            service: service,
            legacy: legacy,
            store: recordStore,
            serviceIdentity: identity
        )
        return (
            root,
            recordStore,
            receiptLedger,
            PhaseJLifecycleApp(
                coordinator: coordinator,
                service: service,
                receiptLedger: receiptLedger,
                receiptID: { "\(receiptIDPrefix)-\(UUID().uuidString)" }
            )
        )
    }

    private func canonicalTarget(_ root: URL) -> String {
        AuthorityGuard.canonicalize(root.appendingPathComponent("target", isDirectory: true).path).path
    }

    private func runLifecycleMatrixCompletenessContract() {
        let rows = PhaseJLifecycleMatrix.rows
        let expectedIDs = Set((1...17).map { String(format: "J-LC-%02d", $0) })
        check(
            "J01",
            "the machine-readable lifecycle matrix has one stable ID for every modeled lifecycle state",
            rows.count == PhaseJLifecycleState.allCases.count
                && Set(rows.map(\.id)) == expectedIDs
                && Set(rows.map(\.state)) == Set(PhaseJLifecycleState.allCases)
                && PhaseJLifecycleMatrix.isComplete
        )
    }

    private func runOwnedDryRunContract() {
        let service = FakeSMAdapter()
        let legacy = FakeLegacyCLIAdapter(present: true)
        let fixture = app("dry-run", service: service, legacy: legacy)
        defer { try? fm.removeItem(at: fixture.root) }
        let request = PhaseJLifecycleRequest(
            id: "J-dry-run",
            operation: .install,
            mode: .dryRun,
            targetCanonical: canonicalTarget(fixture.root),
            ownership: ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)!
        )
        let receipt = fixture.app.install(request: request, evidence: evidence(cli: true))
        check(
            "J02",
            "an owned install dry-run records the exact unchanged post-state without creating a migration or service mutation",
            receipt.outcome == .planned
                && receipt.stateBefore == .legacyOnly
                && receipt.observedStateAfter == .legacyOnly
                && receipt.expectedStateAfter == .interrupted
                && receipt.migrationStageAfter == nil
                && receipt.retention == .retain
                && service.calls.isEmpty
                && (try? fixture.records.load()) == nil
                && fixture.receipts.readAll() == [receipt]
        )
    }

    private func runOwnershipAndAuthorizationRefusalContract() {
        let service = FakeSMAdapter()
        let legacy = FakeLegacyCLIAdapter(present: true)
        let fixture = app("refusal", service: service, legacy: legacy)
        defer { try? fm.removeItem(at: fixture.root) }
        let legacyIdentity = ProductServiceRegistry.canonical.identity(for: .legacySorter)!
        let notOwned = PhaseJLifecycleRequest(
            id: "J-refuse-owner",
            operation: .install,
            mode: .apply,
            targetCanonical: canonicalTarget(fixture.root),
            ownership: legacyIdentity
        )
        let ownerRefusal = fixture.app.install(request: notOwned, evidence: evidence(cli: true))
        let canonicalIdentity = ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)!
        let ungranted = PhaseJLifecycleRequest(
            id: "J-refuse-auth",
            operation: .install,
            mode: .apply,
            targetCanonical: canonicalTarget(fixture.root),
            ownership: canonicalIdentity
        )
        let authorizationRefusal = fixture.app.install(request: ungranted, evidence: evidence(cli: true, authorized: false))
        let foreignRefusal = fixture.app.install(
            request: PhaseJLifecycleRequest(
                id: "J-refuse-foreign",
                operation: .install,
                mode: .apply,
                targetCanonical: canonicalTarget(fixture.root),
                ownership: canonicalIdentity
            ),
            evidence: evidence(cli: true, foreign: true)
        )
        check(
            "J03",
            "unowned, unauthorized, and foreign install requests are receipted refusals with no migration or service mutation",
            ownerRefusal.outcome == .refused
                && ownerRefusal.refusal == .notAppOwned
                && authorizationRefusal.outcome == .refused
                && authorizationRefusal.refusal == .authorizationRequired
                && foreignRefusal.outcome == .refused
                && foreignRefusal.refusal == .migrationPolicy
                && service.calls.isEmpty
                && (try? fixture.records.load()) == nil
                && fixture.receipts.readAll().count == 3
        )
    }

    private func runRestartRecoverableInstallContract() {
        let service = FakeSMAdapter()
        service.statusResult = .success(.notRegistered)
        service.statusAfterRegister = .enabled
        let legacy = FakeLegacyCLIAdapter(present: true)
        let fixture = app("restart", service: service, legacy: legacy)
        defer { try? fm.removeItem(at: fixture.root) }
        let identity = ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)!
        let request = PhaseJLifecycleRequest(
            id: "J-restart-install",
            operation: .install,
            mode: .apply,
            targetCanonical: canonicalTarget(fixture.root),
            ownership: identity
        )
        let started = fixture.app.install(request: request, evidence: evidence(cli: true))
        let reloadedCoordinator = FakeRecoverableMigrationCoordinator(
            service: service,
            legacy: legacy,
            store: fixture.records,
            serviceIdentity: identity
        )
        let restarted = PhaseJLifecycleApp(
            coordinator: reloadedCoordinator,
            service: service,
            receiptLedger: fixture.receipts,
            receiptID: { "J-restart-\(UUID().uuidString)" }
        )
        let registered = restarted.resumeInstall(
            request: request,
            evidence: evidence(cli: true, stage: .registrationPrepared)
        )
        let removalPrepared = restarted.resumeInstall(
            request: request,
            evidence: evidence(cli: true, stage: .serviceHealthy)
        )
        let completed = restarted.resumeInstall(
            request: request,
            evidence: evidence(cli: true, stage: .legacyRemovalPrepared)
        )
        check(
            "J04",
            "an app-owned install only advances the existing Phase B transaction and survives a restart with exact staged receipts",
            started.outcome == .applied
                && started.migrationStageAfter == .registrationPrepared
                && started.observedStateAfter == .interrupted
                && registered.migrationStageAfter == .serviceHealthy
                && removalPrepared.migrationStageAfter == .legacyRemovalPrepared
                && completed.migrationStageAfter == .completed
                && completed.observedStateAfter == .clean
                && service.registerCount == 1
                && legacy.removeCount == 1
                && fixture.receipts.readAll().count == 4
        )
    }

    private func runUninstallAndReceiptRetentionContract() {
        let service = FakeSMAdapter()
        service.statusResult = .success(.enabled)
        let legacy = FakeLegacyCLIAdapter(present: false)
        let fixture = app("uninstall", service: service, legacy: legacy)
        defer { try? fm.removeItem(at: fixture.root) }
        let identity = ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)!
        let request = PhaseJLifecycleRequest(
            id: "J-uninstall",
            operation: .uninstall,
            mode: .apply,
            targetCanonical: canonicalTarget(fixture.root),
            ownership: identity
        )
        let first = fixture.app.uninstall(request: request, evidence: evidence(app: true, enabled: true, uninstallRequested: true))
        let second = fixture.app.uninstall(request: request, evidence: evidence(app: true, enabled: true, uninstallRequested: true))
        let cliOnly = fixture.app.uninstall(request: request, evidence: evidence(cli: true, uninstallRequested: true))
        check(
            "J05",
            "app-owned uninstall is an exact non-mutating plan that retains prior lifecycle receipts and refuses legacy-only removal",
            first.outcome == .planned
                && first.stateBefore == .uninstallReady
                && first.observedStateAfter == .uninstallReady
                && first.retention == .retain
                && second.outcome == .planned
                && fixture.receipts.readAll().count == 3
                && service.registerCount == 0
                && service.unregisterCount == 0
                && cliOnly.outcome == .refused
                && cliOnly.refusal == .migrationPolicy
        )
    }

    private func runLifecycleClassificationContract() {
        let cases: [(String, PhaseJLifecycleEvidence, PhaseJLifecycleState)] = [
            ("clean", evidence(app: true, enabled: true), .clean),
            ("nonexistent", evidence(), .nonexistent),
            ("legacy", evidence(cli: true), .legacyOnly),
            ("dual", evidence(cli: true, app: true, enabled: true), .dual),
            ("foreign", evidence(cli: true, foreign: true), .foreign),
            ("configuration", evidence(targetValid: false), .invalidConfiguration),
            ("authorization", evidence(cli: true, authorized: false), .authorizationRequired),
            ("interruption", evidence(cli: true, stage: .registrationPrepared), .interrupted),
            ("rollback", evidence(cli: true, stage: .rollbackRequired), .rollbackRequired),
            ("uninstall", evidence(app: true, enabled: true, uninstallRequested: true), .uninstallReady),
            ("pause", evidence(app: true, enabled: true, paused: true), .paused),
            ("ledger", evidence(app: true, enabled: true, ledgerHealthy: false), .ledgerDegraded),
            ("notification", evidence(app: true, enabled: true, notificationsHealthy: false), .notificationDegraded),
            ("undo", evidence(app: true, enabled: true, undoPending: true), .undoPending),
            ("upgrade", evidence(app: true, enabled: true, version: .upgrade), .upgradeReady),
            ("downgrade", evidence(app: true, enabled: true, version: .downgrade), .downgradeRefused),
            ("reboot", evidence(app: true, enabled: true, rebootRequired: true), .rebootRequired)
        ]
        let classified = cases.allSatisfy { PhaseJLifecycleClassifier.state(for: $0.1) == $0.2 }
        check(
            "J06",
            "lifecycle classification models clean, absence, migration, integrity, notification, undo, version, and reboot states",
            classified,
            cases.map { "\($0.0)=\(PhaseJLifecycleClassifier.state(for: $0.1).rawValue)" }.joined(separator: ",")
        )
    }
}
