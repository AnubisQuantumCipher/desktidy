import Foundation

// ============================================================================
//  Append-only schema-versioned migration transaction (not a movement receipt).
//  Simulated transitions only. No real launchd/Login Items mutation.
// ============================================================================

enum MigrationOutcome: String, Equatable {
    case succeeded
    case rejected
    case indeterminate
    case refused
    case rolledBack
    case rollbackFailed
}

struct MigrationTransaction: Equatable {
    var schema: Int = 1
    var id: String
    var sourceCommit: String
    var bundleHash: String
    var targetCanonical: String
    var priorCLIPresent: Bool
    var intendedPlistName: String
    var adapterStatusBefore: String
    var adapterStatusAfter: String
    var outcome: MigrationOutcome
    var rollbackRequired: Bool
    var preparedAt: String
    var loginItemsObserved: Bool = false
    var fdaObserved: Bool = false
    var rebootObserved: Bool = false
}

final class MigrationLedger {
    private(set) var records: [MigrationTransaction] = []
    func append(_ t: MigrationTransaction) { records.append(t) }
}

/// Orchestrates a simulated register/unregister using a fake adapter only.
/// The second pre-call check is load-bearing (A→B→A target).
struct MigrationOrchestrator {
    let adapter: ServiceManagementAdapting
    var skipSecondPreCallCheck = false   // production false; A→B→A flips this

    func attempt(
        intent: MigrationIntent,
        evidence: MigrationEvidence,
        evidenceAtCall: MigrationEvidence? = nil,
        authData: Data?,
        context: InterlockContext,
        plistName: String,
        sourceCommit: String,
        bundleHash: String,
        targetCanonical: String,
        priorCLIPresent: Bool
    ) -> MigrationTransaction {
        let iso = ISO8601DateFormatter()
        func rec(_ outcome: MigrationOutcome, before: String, after: String, rollback: Bool) -> MigrationTransaction {
            MigrationTransaction(
                id: UUID().uuidString, sourceCommit: sourceCommit, bundleHash: bundleHash,
                targetCanonical: targetCanonical, priorCLIPresent: priorCLIPresent,
                intendedPlistName: plistName, adapterStatusBefore: before,
                adapterStatusAfter: after, outcome: outcome, rollbackRequired: rollback,
                preparedAt: iso.string(from: Date())
            )
        }

        let state = MigrationPolicy.classify(evidence)
        if MigrationPolicy.decide(state: state, intent: intent) == .refuse {
            return rec(.refused, before: "unprobed", after: "unprobed", rollback: false)
        }

        let beforeStatus = adapter.status(plistName: plistName)
        let beforeStr = describe(beforeStatus)

        if let authData {
            switch MutationInterlock.evaluate(authData: authData, context: context) {
            case .refuse:
                return rec(.refused, before: beforeStr, after: beforeStr, rollback: false)
            case .permit:
                break
            }
        } else if intent == .beginRegistration || intent == .rollback {
            return rec(.refused, before: beforeStr, after: beforeStr, rollback: false)
        }

        let callEvidence = evidenceAtCall ?? evidence
        if !skipSecondPreCallCheck {
            let late = MigrationPolicy.classify(callEvidence)
            if late != state || callEvidence.foreignOverlap != evidence.foreignOverlap
                || !callEvidence.targetValid || callEvidence.foreignOverlap {
                if MigrationPolicy.decide(state: late, intent: intent) == .refuse
                    || late != state || callEvidence.foreignOverlap {
                    return rec(.refused, before: beforeStr, after: beforeStr, rollback: false)
                }
            }
            if callEvidence.targetValid != evidence.targetValid {
                return rec(.refused, before: beforeStr, after: beforeStr, rollback: false)
            }
        }

        switch intent {
        case .beginRegistration:
            let result = adapter.requestRegister(plistName: plistName)
            let after = adapter.status(plistName: plistName)
            switch (result, after) {
            case (.failure, _):
                return rec(.rejected, before: beforeStr, after: describe(after), rollback: false)
            case (.success, .success(.unknown)):
                return rec(.indeterminate, before: beforeStr, after: describe(after), rollback: true)
            case (.success, .success(let st)) where st == .enabled || st == .requiresApproval:
                if evidence.legacyCLIPresent {
                    return rec(.refused, before: beforeStr, after: describe(after), rollback: true)
                }
                return rec(.succeeded, before: beforeStr, after: describe(after), rollback: false)
            case (.success, .success), (.success, .failure):
                return rec(.indeterminate, before: beforeStr, after: describe(after), rollback: true)
            }
        case .rollback:
            let result = adapter.requestUnregister(plistName: plistName)
            let after = adapter.status(plistName: plistName)
            switch result {
            case .failure:
                return rec(.rollbackFailed, before: beforeStr, after: describe(after), rollback: true)
            case .success:
                if case .success(.unknown) = after {
                    return rec(.indeterminate, before: beforeStr, after: describe(after), rollback: true)
                }
                if case .failure = after {
                    return rec(.indeterminate, before: beforeStr, after: describe(after), rollback: true)
                }
                return rec(.rolledBack, before: beforeStr, after: describe(after), rollback: false)
            }
        case .uninstall:
            if state == .registrationIndeterminate {
                return rec(.refused, before: beforeStr, after: beforeStr, rollback: false)
            }
            return rec(.succeeded, before: beforeStr, after: beforeStr, rollback: false)
        }
    }

    private func describe(_ r: Result<SMAdapterStatus, SMAdapterError>) -> String {
        switch r {
        case .success(let s):
            switch s {
            case .enabled: return "enabled"
            case .requiresApproval: return "requiresApproval"
            case .notRegistered: return "notRegistered"
            case .notFound: return "notFound"
            case .unknown(let x): return "unknown:\(x)"
            }
        case .failure(let e):
            return "error:\(e)"
        }
    }
}
