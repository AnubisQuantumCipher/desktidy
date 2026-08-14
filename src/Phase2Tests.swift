import Foundation

// ============================================================================
//  R2 Phase B gates — typed identity and fake-only migration recovery.
// ============================================================================

final class Phase2Tests {
    private var passCount = 0
    private var failCount = 0

    private func check(_ id: String, _ description: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("PASS  \(id)  \(description)")
            passCount += 1
        } else {
            print("FAIL  \(id)  \(description)\(detail.isEmpty ? "" : " — \(detail)")")
            failCount += 1
        }
    }

    func runAll() -> Bool {
        runRegistryGates()
        runRecoverableMigrationGates()
        print("PHASE2 GATES: \(passCount) passed, \(failCount) failed")
        if passCount == 0 {
            print("FAIL  summary  zero cases")
            return false
        }
        return failCount == 0
    }

    private func runRegistryGates() {
        let registry = ProductServiceRegistry.canonical
        check(
            "R01",
            "canonical registry has typed app, legacy, and observed sacrificial identities",
            registry.identity(for: .menuBarApp)?.bundleIdentifier == "com.desktidy.app"
                && registry.identity(for: .legacySorter)?.serviceLabel == "com.desktidy.sort"
                && registry.identity(for: .legacyNotifier)?.serviceLabel == "com.desktidy.notify"
                && registry.identity(for: .observedSacrificialProbe)?.serviceLabel == "com.desktidy.sacrificial"
        )
        check(
            "R02",
            "registry classification preserves trust boundaries",
            registry.classify(serviceLabel: "com.desktidy.sort", bundleIdentifier: nil, programBasename: "desktidy-sort") == .acceptedSelf(.legacySorter)
                && registry.classify(serviceLabel: "com.desktidy.sacrificial", bundleIdentifier: "com.desktidy.sacrificial-probe", programBasename: "SacrificialHelper") == .observedNonProduction(.observedSacrificialProbe)
                && registry.classify(serviceLabel: nil, bundleIdentifier: "com.desktidy.app", programBasename: "DeskTidy") == .knownBundle(.menuBarApp)
                && registry.classify(serviceLabel: "com.sicarii.desktop-autosort", bundleIdentifier: nil, programBasename: "desktop-autosort") == .foreign
                && registry.classify(serviceLabel: "com.desktidy.app.sort", bundleIdentifier: "com.desktidy.app", programBasename: "DeskTidy") == .foreign
        )
    }

    private func runRecoverableMigrationGates() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("desktidy-phase2-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let canonicalRoot = AuthorityGuard.canonicalize(root.path).path

        let store = FileMigrationRecordStore(url: root.appendingPathComponent("migration.json"))
        let service = FakeSMAdapter()
        service.statusResult = .success(.notRegistered)
        service.statusAfterRegister = .enabled
        service.observedTargetCanonical = canonicalRoot
        let legacy = FakeLegacyCLIAdapter(present: true)
        let identity = ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)!

        var coordinator = FakeRecoverableMigrationCoordinator(
            service: service,
            legacy: legacy,
            store: store,
            serviceIdentity: identity
        )
        let began = coordinator.begin(from: .cliOnly, targetCanonical: canonicalRoot)
        let prepared = coordinator.advance()
        let healthy = coordinator.advance()

        // Recreate the coordinator from the same on-disk record to prove that
        // the next action is derived from durable state rather than memory.
        coordinator = FakeRecoverableMigrationCoordinator(
            service: service,
            legacy: legacy,
            store: store,
            serviceIdentity: identity
        )
        let removalPrepared = coordinator.advance()
        let completed = coordinator.advance()

        check(
            "M01",
            "cli-only migration is health-gated, exactly-once, and restart-recoverable",
            began == .prepared
                && prepared == .registrationPrepared
                && healthy == .serviceHealthy
                && removalPrepared == .legacyRemovalPrepared
                && completed == .completed
                && service.registerCount == 1
                && legacy.removeCount == 1
                && (try? store.load())?.serviceRole == .plannedAppAgent
        )

        let rollbackURL = root.appendingPathComponent("rollback.json")
        let rollbackStore = FileMigrationRecordStore(url: rollbackURL)
        let rollbackService = FakeSMAdapter()
        rollbackService.statusResult = .success(.enabled)
        rollbackService.unregisterResult = .success(())
        rollbackService.statusAfterUnregister = .notRegistered
        rollbackService.observedTargetCanonical = canonicalRoot
        let removedLegacy = FakeLegacyCLIAdapter(present: false)
        try? rollbackStore.save(RecoverableMigrationRecord(
            schema: 1,
            id: "rollback-fixture",
            serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort",
            plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot,
            priorCLIPresent: true,
            stage: .rollbackRequired
        ))
        let rollback = FakeRecoverableMigrationCoordinator(
            service: rollbackService,
            legacy: removedLegacy,
            store: rollbackStore,
            serviceIdentity: identity
        )
        let rolledBack = rollback.recover()
        let rolledBackAgain = rollback.recover()
        check(
            "M02",
            "rollback unregisters planned service and restores only prior product CLI mode once",
            rolledBack == .rolledBack
                && rolledBackAgain == .rolledBack
                && rollbackService.unregisterCount == 1
                && removedLegacy.restoreCount == 1
                && removedLegacy.present
        )

        var duplicateRejected = false
        if let valid = try? String(contentsOf: rollbackURL, encoding: .utf8) {
            let poisoned = valid.replacingOccurrences(
                of: "\"stage\":\"rolledBack\"",
                with: "\"stage\":\"rolledBack\",\"st\\u0061ge\":\"completed\""
            )
            try? Data(poisoned.utf8).write(to: rollbackURL, options: [.atomic])
            do {
                _ = try rollbackStore.load()
            } catch {
                duplicateRejected = true
            }
        }
        check("M03", "durable migration record rejects escaped-equivalent duplicate keys", duplicateRejected)

        let existingStore = FileMigrationRecordStore(url: root.appendingPathComponent("existing.json"))
        try? existingStore.save(RecoverableMigrationRecord(
            schema: 1,
            id: "existing-transaction",
            serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort",
            plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot,
            priorCLIPresent: false,
            stage: .registrationPrepared
        ))
        let noOverwrite = FakeRecoverableMigrationCoordinator(
            service: FakeSMAdapter(),
            legacy: FakeLegacyCLIAdapter(present: false),
            store: existingStore,
            serviceIdentity: identity
        )
        let duplicateBegin = noOverwrite.begin(from: .neitherInstalled, targetCanonical: canonicalRoot)
        check(
            "M04",
            "begin refuses to overwrite an existing recoverable transaction",
            duplicateBegin == .refused && (try? existingStore.load())?.id == "existing-transaction"
        )

        let forgedIdentity = ProductServiceIdentity(
            role: .plannedAppAgent,
            bundleIdentifier: "com.desktidy.app",
            serviceLabel: "com.example.attacker",
            embeddedPlistName: "com.example.attacker.plist",
            expectedProgramBasenames: ["DeskTidyService"],
            acceptance: .plannedUnaccepted
        )
        let forged = FakeRecoverableMigrationCoordinator(
            service: FakeSMAdapter(),
            legacy: FakeLegacyCLIAdapter(present: false),
            store: FileMigrationRecordStore(url: root.appendingPathComponent("forged.json")),
            serviceIdentity: forgedIdentity
        )
        check(
            "M05",
            "migration accepts only the canonical planned identity, never a caller-forged role",
            forged.begin(from: .neitherInstalled, targetCanonical: canonicalRoot) == .refused
        )

        let targetStore = FileMigrationRecordStore(url: root.appendingPathComponent("target-mismatch.json"))
        try? targetStore.save(RecoverableMigrationRecord(
            schema: 1,
            id: "target-mismatch",
            serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort",
            plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot,
            priorCLIPresent: true,
            stage: .registrationPrepared
        ))
        let mismatchedService = FakeSMAdapter()
        mismatchedService.statusResult = .success(.enabled)
        mismatchedService.observedTargetCanonical = root.appendingPathComponent("other").path
        let guardedLegacy = FakeLegacyCLIAdapter(present: true)
        let targetGuard = FakeRecoverableMigrationCoordinator(
            service: mismatchedService,
            legacy: guardedLegacy,
            store: targetStore,
            serviceIdentity: identity
        )
        check(
            "M06",
            "healthy status without exact target binding requires rollback before legacy removal",
            targetGuard.advance() == .rollbackRequired && guardedLegacy.removeCount == 0
        )

        let driftStore = FileMigrationRecordStore(url: root.appendingPathComponent("late-drift.json"))
        try? driftStore.save(RecoverableMigrationRecord(
            schema: 1,
            id: "late-drift",
            serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort",
            plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot,
            priorCLIPresent: true,
            stage: .legacyRemovalPrepared
        ))
        let driftedService = FakeSMAdapter()
        driftedService.statusResult = .success(.notRegistered)
        driftedService.observedTargetCanonical = canonicalRoot
        let retainedLegacy = FakeLegacyCLIAdapter(present: true)
        let driftGuard = FakeRecoverableMigrationCoordinator(
            service: driftedService,
            legacy: retainedLegacy,
            store: driftStore,
            serviceIdentity: identity
        )
        check(
            "M07",
            "service health and target are revalidated immediately before legacy removal",
            driftGuard.advance() == .rollbackRequired && retainedLegacy.removeCount == 0
        )

        let concurrentStore = FileMigrationRecordStore(url: root.appendingPathComponent("concurrent.json"))
        let resultLock = NSLock()
        var concurrentResults: [MigrationRecoveryStage] = []
        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            let contender = FakeRecoverableMigrationCoordinator(
                service: FakeSMAdapter(),
                legacy: FakeLegacyCLIAdapter(present: false),
                store: concurrentStore,
                serviceIdentity: identity
            )
            let result = contender.begin(from: .neitherInstalled, targetCanonical: canonicalRoot)
            resultLock.lock()
            concurrentResults.append(result)
            resultLock.unlock()
        }
        check(
            "M08",
            "concurrent begin atomically creates exactly one transaction",
            concurrentResults.filter { $0 == .prepared }.count == 1
                && concurrentResults.filter { $0 == .refused }.count == 1
        )

        let saveFailStore = FileMigrationRecordStore(url: root.appendingPathComponent("save-fail.json"))
        try? saveFailStore.save(RecoverableMigrationRecord(
            schema: 1,
            id: "save-fail",
            serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort",
            plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot,
            priorCLIPresent: true,
            stage: .registrationPrepared
        ))
        let saveFailService = FakeSMAdapter()
        saveFailService.statusResult = .success(.notRegistered)
        saveFailService.statusAfterRegister = .enabled
        saveFailService.statusAfterUnregister = .notRegistered
        saveFailService.observedTargetCanonical = canonicalRoot
        let saveFailLegacy = FakeLegacyCLIAdapter(present: true)
        saveFailStore.failNextSaveCount = 1
        let saveFailure = FakeRecoverableMigrationCoordinator(
            service: saveFailService,
            legacy: saveFailLegacy,
            store: saveFailStore,
            serviceIdentity: identity
        )
        let failedAdvance = saveFailure.advance()
        let recoveredAfterSaveFailure = saveFailure.recover()
        check(
            "M09",
            "a state-save failure enters a recoverable rollback path",
            failedAdvance == .rollbackRequired && recoveredAfterSaveFailure == .rolledBack
        )
        let rollbackTargetStore = FileMigrationRecordStore(url: root.appendingPathComponent("rollback-target-mismatch.json"))
        try? rollbackTargetStore.save(RecoverableMigrationRecord(
            schema: 1,
            id: "rollback-target-mismatch",
            serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort",
            plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot,
            priorCLIPresent: false,
            stage: .rollbackRequired
        ))
        let rollbackTargetService = FakeSMAdapter()
        rollbackTargetService.statusResult = .success(.enabled)
        rollbackTargetService.observedTargetCanonical = root.appendingPathComponent("other").path
        let rollbackTargetGuard = FakeRecoverableMigrationCoordinator(
            service: rollbackTargetService,
            legacy: FakeLegacyCLIAdapter(present: false),
            store: rollbackTargetStore,
            serviceIdentity: identity
        )
        check(
            "M10",
            "rollback refuses to unregister when the observed target no longer matches its transaction",
            rollbackTargetGuard.recover() == .rollbackRequired && rollbackTargetService.unregisterCount == 0
        )
        let privateDirectory = root.appendingPathComponent("private-records")
        let privateStore = FileMigrationRecordStore(url: privateDirectory.appendingPathComponent("migration.json"))
        let privateRecord = RecoverableMigrationRecord(
            schema: 1,
            id: "private-record",
            serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort",
            plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot,
            priorCLIPresent: false,
            stage: .prepared
        )
        let privateCreated = (try? privateStore.createIfAbsent(privateRecord)) == true
        let parentMode = (try? FileManager.default.attributesOfItem(atPath: privateDirectory.path)[.posixPermissions] as? NSNumber)?.intValue
        let recordMode = (try? FileManager.default.attributesOfItem(atPath: privateStore.url.path)[.posixPermissions] as? NSNumber)?.intValue
        check(
            "M11",
            "migration parent and record are private from their first durable write",
            privateCreated && parentMode == 0o700 && recordMode == 0o600
        )
        let ownershipStore = FileMigrationRecordStore(url: root.appendingPathComponent("ownership.json"))
        try? ownershipStore.save(RecoverableMigrationRecord(
            schema: 1, id: "ownership-fixture", serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort", plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot, priorCLIPresent: false, stage: .rollbackRequired
        ))
        if let raw = try? String(contentsOf: ownershipStore.url, encoding: .utf8) {
            let own = "\"ownerUID\":\(Darwin.getuid())"
            try? raw.replacingOccurrences(of: own, with: "\"ownerUID\":0").write(to: ownershipStore.url, atomically: true, encoding: .utf8)
        }
        let ownershipService = FakeSMAdapter()
        ownershipService.statusResult = .success(.enabled)
        ownershipService.observedTargetCanonical = canonicalRoot
        let ownershipGuard = FakeRecoverableMigrationCoordinator(
            service: ownershipService, legacy: FakeLegacyCLIAdapter(present: false),
            store: ownershipStore, serviceIdentity: identity
        )
        check(
            "M12",
            "rollback rejects a transaction whose durable owner does not match the current user",
            ownershipGuard.recover() == .rollbackRequired && ownershipService.unregisterCount == 0
        )
        let cleanupStore = FileMigrationRecordStore(url: root.appendingPathComponent("cleanup.json"))
        cleanupStore.failAfterExclusiveCreate = true
        cleanupStore.afterExclusiveCreate = {
            try? FileManager.default.removeItem(at: cleanupStore.url)
            try? Data("replacement".utf8).write(to: cleanupStore.url)
        }
        let cleanupResult = try? cleanupStore.createIfAbsent(privateRecord)
        let replacement = try? String(contentsOf: cleanupStore.url, encoding: .utf8)
        check(
            "M13",
            "failed exclusive creation never unlinks a path replaced with another inode",
            cleanupResult == nil && replacement == "replacement"
        )
        let transitionStore = FileMigrationRecordStore(url: root.appendingPathComponent("transition.json"))
        try? transitionStore.save(RecoverableMigrationRecord(
            schema: 1, id: "transition", serviceRole: .plannedAppAgent,
            serviceLabel: "com.desktidy.app.sort", plistName: "com.desktidy.app.sort.plist",
            targetCanonical: canonicalRoot, priorCLIPresent: false, stage: .registrationPrepared
        ))
        let transitionService = FakeSMAdapter()
        transitionService.statusResult = .success(.notRegistered)
        transitionService.statusAfterRegister = .enabled
        transitionService.observedTargetCanonical = canonicalRoot
        let transitionLegacy = FakeLegacyCLIAdapter(present: false)
        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            let contender = FakeRecoverableMigrationCoordinator(
                service: transitionService, legacy: transitionLegacy,
                store: transitionStore, serviceIdentity: identity
            )
            _ = contender.advance()
        }
        check(
            "M14",
            "concurrent advances serialize service registration to exactly one mutation",
            transitionService.registerCount == 1
        )
    }
}