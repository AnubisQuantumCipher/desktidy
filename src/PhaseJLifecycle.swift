import Foundation

// ============================================================================
// Phase J — hermetic lifecycle handoff over the Phase B recoverable migration.
// This surface accepts only the fake Phase B coordinator used by the contract
// tests; it never constructs or selects a production ServiceManagement adapter.
// ============================================================================

enum PhaseJLifecycleState: String, CaseIterable, Codable, Equatable {
    case clean
    case nonexistent
    case legacyOnly
    case dual
    case foreign
    case invalidConfiguration
    case authorizationRequired
    case interrupted
    case rollbackRequired
    case uninstallReady
    case paused
    case ledgerDegraded
    case notificationDegraded
    case undoPending
    case upgradeReady
    case downgradeRefused
    case rebootRequired
}

enum PhaseJVersionTransition: String, Codable, Equatable {
    case none
    case upgrade
    case downgrade
}

struct PhaseJLifecycleEvidence: Equatable {
    let migration: MigrationEvidence
    let migrationStage: MigrationRecoveryStage?
    let authorizationGranted: Bool
    let uninstallRequested: Bool
    let paused: Bool
    let ledgerHealthy: Bool
    let notificationsHealthy: Bool
    let undoPending: Bool
    let versionTransition: PhaseJVersionTransition
    let rebootRequired: Bool
}

enum PhaseJLifecycleClassifier {
    static func state(for evidence: PhaseJLifecycleEvidence) -> PhaseJLifecycleState {
        let migration = evidence.migration

        if !migration.targetValid { return .invalidConfiguration }
        if migration.foreignOverlap { return .foreign }
        if !evidence.authorizationGranted { return .authorizationRequired }
        if migration.rollbackMarked || evidence.migrationStage == .rollbackRequired { return .rollbackRequired }
        if migration.transactionContradictory || migration.transactionOpen || isOpenMigration(evidence.migrationStage) {
            return .interrupted
        }
        if evidence.uninstallRequested && migration.observedAppAgentPresent && migration.registrationEnabled {
            return .uninstallReady
        }
        if evidence.paused { return .paused }
        if !evidence.ledgerHealthy { return .ledgerDegraded }
        if !evidence.notificationsHealthy { return .notificationDegraded }
        if evidence.undoPending { return .undoPending }
        switch evidence.versionTransition {
        case .upgrade: return .upgradeReady
        case .downgrade: return .downgradeRefused
        case .none: break
        }
        if evidence.rebootRequired { return .rebootRequired }

        if migration.legacyCLIPresent && migration.observedAppAgentPresent { return .dual }
        if migration.observedAppAgentPresent && migration.registrationEnabled { return .clean }
        if migration.legacyCLIPresent { return .legacyOnly }
        if migration.observedAppAgentPresent { return .interrupted }
        return .nonexistent
    }

    private static func isOpenMigration(_ stage: MigrationRecoveryStage?) -> Bool {
        switch stage {
        case .prepared?, .registrationPrepared?, .serviceHealthy?, .legacyRemovalPrepared?:
            return true
        case .completed?, .rollbackRequired?, .rolledBack?, .refused?, nil:
            return false
        }
    }
}

struct PhaseJLifecycleMatrixRow: Codable, Equatable {
    let id: String
    let state: PhaseJLifecycleState
}

enum PhaseJLifecycleMatrix {
    // Stable IDs are intentionally explicit: consumers can compare artifacts
    // without depending on enum declaration order.
    static let rows: [PhaseJLifecycleMatrixRow] = [
        .init(id: "J-LC-01", state: .clean),
        .init(id: "J-LC-02", state: .nonexistent),
        .init(id: "J-LC-03", state: .legacyOnly),
        .init(id: "J-LC-04", state: .dual),
        .init(id: "J-LC-05", state: .foreign),
        .init(id: "J-LC-06", state: .invalidConfiguration),
        .init(id: "J-LC-07", state: .authorizationRequired),
        .init(id: "J-LC-08", state: .interrupted),
        .init(id: "J-LC-09", state: .rollbackRequired),
        .init(id: "J-LC-10", state: .uninstallReady),
        .init(id: "J-LC-11", state: .paused),
        .init(id: "J-LC-12", state: .ledgerDegraded),
        .init(id: "J-LC-13", state: .notificationDegraded),
        .init(id: "J-LC-14", state: .undoPending),
        .init(id: "J-LC-15", state: .upgradeReady),
        .init(id: "J-LC-16", state: .downgradeRefused),
        .init(id: "J-LC-17", state: .rebootRequired)
    ]

    static var isComplete: Bool {
        rows.count == PhaseJLifecycleState.allCases.count
            && Set(rows.map(\.state)) == Set(PhaseJLifecycleState.allCases)
            && Set(rows.map(\.id)).count == rows.count
    }
}

enum PhaseJLifecycleOperation: String, Codable, Equatable {
    case install
    case uninstall
}

enum PhaseJLifecycleMode: String, Codable, Equatable {
    case dryRun
    case apply
}

enum PhaseJLifecycleOutcome: String, Codable, Equatable {
    case planned
    case applied
    case refused
}

enum PhaseJLifecycleRefusal: String, Codable, Equatable {
    case notAppOwned
    case authorizationRequired
    case migrationPolicy
}

enum PhaseJLifecycleReceiptRetention: String, Codable, Equatable {
    case retain
}

struct PhaseJLifecycleRequest: Equatable {
    let id: String
    let operation: PhaseJLifecycleOperation
    let mode: PhaseJLifecycleMode
    let targetCanonical: String
    let ownership: ProductServiceIdentity
}

struct PhaseJLifecycleReceipt: Codable, Equatable {
    let id: String
    let requestID: String
    let operation: PhaseJLifecycleOperation
    let mode: PhaseJLifecycleMode
    let outcome: PhaseJLifecycleOutcome
    let refusal: PhaseJLifecycleRefusal?
    let stateBefore: PhaseJLifecycleState
    let observedStateAfter: PhaseJLifecycleState
    let expectedStateAfter: PhaseJLifecycleState
    let migrationStageAfter: MigrationRecoveryStage?
    let retention: PhaseJLifecycleReceiptRetention
}

final class PhaseJLifecycleReceiptLedger {
    let url: URL
    private let fm: FileManager
    private let lock = NSLock()

    init(url: URL, fm: FileManager = .default) {
        self.url = url
        self.fm = fm
    }

    func append(_ receipt: PhaseJLifecycleReceipt) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(receipt) else { return }
        let directory = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(Data("\n".utf8))
        } catch {
            return
        }
    }

    func readAll() -> [PhaseJLifecycleReceipt] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
            try? JSONDecoder().decode(PhaseJLifecycleReceipt.self, from: Data($0.utf8))
        }
    }
}

struct PhaseJLifecycleApp {
    let coordinator: FakeRecoverableMigrationCoordinator
    let service: FakeSMAdapter
    let receiptLedger: PhaseJLifecycleReceiptLedger
    let receiptID: () -> String

    func install(request: PhaseJLifecycleRequest, evidence: PhaseJLifecycleEvidence) -> PhaseJLifecycleReceipt {
        let before = PhaseJLifecycleClassifier.state(for: evidence)
        guard isAppOwned(request) else {
            return record(request: request, outcome: .refused, refusal: .notAppOwned, before: before,
                          observed: before, expected: before, stage: nil)
        }
        guard evidence.authorizationGranted else {
            return record(request: request, outcome: .refused, refusal: .authorizationRequired, before: before,
                          observed: before, expected: before, stage: nil)
        }
        guard canBeginInstall(from: evidence) else {
            return record(request: request, outcome: .refused, refusal: .migrationPolicy, before: before,
                          observed: before, expected: before, stage: nil)
        }
        if request.mode == .dryRun {
            return record(request: request, outcome: .planned, refusal: nil, before: before,
                          observed: before, expected: .interrupted, stage: nil)
        }

        let beginStage = coordinator.begin(from: MigrationPolicy.classify(evidence.migration), targetCanonical: request.targetCanonical)
        guard beginStage == .prepared else {
            return record(request: request, outcome: .refused, refusal: .migrationPolicy, before: before,
                          observed: before, expected: .interrupted, stage: beginStage)
        }
        return recordedInstall(request: request, evidence: evidence, before: before, stage: coordinator.advance())
    }

    func resumeInstall(request: PhaseJLifecycleRequest, evidence: PhaseJLifecycleEvidence) -> PhaseJLifecycleReceipt {
        let before = PhaseJLifecycleClassifier.state(for: evidence)
        guard isAppOwned(request) else {
            return record(request: request, outcome: .refused, refusal: .notAppOwned, before: before,
                          observed: before, expected: before, stage: nil)
        }
        guard evidence.authorizationGranted else {
            return record(request: request, outcome: .refused, refusal: .authorizationRequired, before: before,
                          observed: before, expected: before, stage: nil)
        }
        guard let existing = try? coordinator.store.load(),
              existing.stage == .prepared || existing.stage == .registrationPrepared
                || existing.stage == .serviceHealthy || existing.stage == .legacyRemovalPrepared else {
            return record(request: request, outcome: .refused, refusal: .migrationPolicy, before: before,
                          observed: before, expected: before, stage: nil)
        }
        if request.mode == .dryRun {
            return record(request: request, outcome: .planned, refusal: nil, before: before,
                          observed: before, expected: .interrupted, stage: existing.stage)
        }
        return recordedInstall(request: request, evidence: evidence, before: before, stage: coordinator.advance())
    }

    func uninstall(request: PhaseJLifecycleRequest, evidence: PhaseJLifecycleEvidence) -> PhaseJLifecycleReceipt {
        let before = PhaseJLifecycleClassifier.state(for: evidence)
        guard isAppOwned(request) else {
            return record(request: request, outcome: .refused, refusal: .notAppOwned, before: before,
                          observed: before, expected: before, stage: nil)
        }
        guard evidence.authorizationGranted else {
            return record(request: request, outcome: .refused, refusal: .authorizationRequired, before: before,
                          observed: before, expected: before, stage: nil)
        }
        guard before == .uninstallReady else {
            return record(request: request, outcome: .refused, refusal: .migrationPolicy, before: before,
                          observed: before, expected: before, stage: nil)
        }
        return record(request: request, outcome: .planned, refusal: nil, before: before,
                      observed: before, expected: .uninstallReady, stage: nil)
    }

    private func canBeginInstall(from evidence: PhaseJLifecycleEvidence) -> Bool {
        guard !evidence.migration.foreignOverlap,
              !evidence.migration.rollbackMarked,
              !evidence.migration.transactionOpen,
              !evidence.migration.transactionContradictory,
              evidence.migrationStage == nil else {
            return false
        }
        return MigrationPolicy.decide(state: MigrationPolicy.classify(evidence.migration), intent: .beginRegistration) == .allow
    }

    private func isAppOwned(_ request: PhaseJLifecycleRequest) -> Bool {
        request.ownership == ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)
    }

    private func recordedInstall(
        request: PhaseJLifecycleRequest,
        evidence: PhaseJLifecycleEvidence,
        before: PhaseJLifecycleState,
        stage: MigrationRecoveryStage
    ) -> PhaseJLifecycleReceipt {
        let afterEvidence = PhaseJLifecycleEvidence(
            migration: evidence.migration,
            migrationStage: stage,
            authorizationGranted: evidence.authorizationGranted,
            uninstallRequested: false,
            paused: evidence.paused,
            ledgerHealthy: evidence.ledgerHealthy,
            notificationsHealthy: evidence.notificationsHealthy,
            undoPending: evidence.undoPending,
            versionTransition: evidence.versionTransition,
            rebootRequired: evidence.rebootRequired
        )
        let observed = stage == .completed ? PhaseJLifecycleState.clean : PhaseJLifecycleClassifier.state(for: afterEvidence)
        let outcome: PhaseJLifecycleOutcome = stage == .refused ? .refused : .applied
        return record(request: request, outcome: outcome,
                      refusal: stage == .refused ? .migrationPolicy : nil,
                      before: before, observed: observed, expected: .clean, stage: stage)
    }

    private func record(
        request: PhaseJLifecycleRequest,
        outcome: PhaseJLifecycleOutcome,
        refusal: PhaseJLifecycleRefusal?,
        before: PhaseJLifecycleState,
        observed: PhaseJLifecycleState,
        expected: PhaseJLifecycleState,
        stage: MigrationRecoveryStage?
    ) -> PhaseJLifecycleReceipt {
        let receipt = PhaseJLifecycleReceipt(
            id: receiptID(),
            requestID: request.id,
            operation: request.operation,
            mode: request.mode,
            outcome: outcome,
            refusal: refusal,
            stateBefore: before,
            observedStateAfter: observed,
            expectedStateAfter: expected,
            migrationStageAfter: stage,
            retention: .retain
        )
        receiptLedger.append(receipt)
        return receipt
    }
}
