import Foundation

// ============================================================================
//  R1B Phase 1A — pure migration state model.
//
//  Independent of ServiceManagement. Derives a typed state from explicit
//  evidence. A future app-agent label is *observed evidence only* and does
//  not widen ProductIdentity.selfLabels.
// ============================================================================

enum MigrationState: String, Equatable {
    case cliOnly
    case appOnly
    case neitherInstalled
    case dualDeskTidyPresence
    case foreignConflict
    case invalidTargetConfiguration
    case registrationIndeterminate
    case halfMigrated
    case rollbackRequired
}

enum MigrationIntent: String, Equatable {
    case beginRegistration
    case rollback
    case uninstall
}

enum MigrationDecision: Equatable {
    case allow
    case refuse

    var isRefuse: Bool {
        if case .refuse = self { return true }
        return false
    }
}

struct MigrationEvidence: Equatable {
    var targetValid: Bool
    var legacyCLIPresent: Bool
    var observedAppAgentPresent: Bool
    var foreignOverlap: Bool
    var registrationStatusKnown: Bool
    var registrationEnabled: Bool
    var transactionOpen: Bool
    var transactionContradictory: Bool
    var rollbackMarked: Bool
}

enum MigrationPolicy {
    static func classify(_ e: MigrationEvidence) -> MigrationState {
        if !e.targetValid { return .invalidTargetConfiguration }
        if e.foreignOverlap { return .foreignConflict }
        if e.rollbackMarked { return .rollbackRequired }
        if e.transactionContradictory { return .halfMigrated }
        if e.transactionOpen && !(e.legacyCLIPresent && e.observedAppAgentPresent && e.registrationStatusKnown) {
            return .halfMigrated
        }
        if e.observedAppAgentPresent && !e.registrationStatusKnown {
            return .registrationIndeterminate
        }
        if e.legacyCLIPresent && e.observedAppAgentPresent { return .dualDeskTidyPresence }
        if e.observedAppAgentPresent { return .appOnly }
        if e.legacyCLIPresent { return .cliOnly }
        return .neitherInstalled
    }

    /// Begin is eligible only from cliOnly or neitherInstalled.
    /// Rollback is the recovery path from dual/half/app/rollbackRequired.
    /// Uninstall is allowed only when no app evidence remains (or appOnly
    /// with known-absent service). Indeterminate/foreign/invalid always refuse.
    static func decide(state: MigrationState, intent: MigrationIntent) -> MigrationDecision {
        switch (state, intent) {
        case (.cliOnly, .beginRegistration), (.neitherInstalled, .beginRegistration):
            return .allow
        case (.appOnly, .rollback), (.dualDeskTidyPresence, .rollback),
             (.halfMigrated, .rollback), (.rollbackRequired, .rollback):
            return .allow
        case (.appOnly, .uninstall), (.neitherInstalled, .uninstall):
            return .allow
        default:
            return .refuse
        }
    }

    /// Production migration tests and code must not target the live Desktop.
    /// Comparison is by canonical path equality against an injected desktop
    /// or the process home Desktop when no fixture is supplied.
    static func isLiveDesktopTarget(_ targetCanonical: String, desktop: String? = nil) -> Bool {
        let desk = AuthorityGuard.canonicalize(desktop ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
        let target = AuthorityGuard.canonicalize(targetCanonical)
        if MutationInterlock.rootsEquivalent(target, desk) { return true }
        if MutationInterlock.isInsideDesktop(target.path, desktop: desk) { return true }
        return false
    }
}
