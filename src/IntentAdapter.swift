import Foundation

// ============================================================================
// Phase I — App Intent boundary adapter.
//
// This file deliberately has no AppIntents dependency, so its contract can be
// tested in a hermetic fixture. It exposes only bounded presentation values and
// delegates every authorization, precondition, mutation, receipt, and query to
// CanonicalApplicationCore.
// ============================================================================

enum CanonicalIntentPauseDuration: String, CaseIterable, Equatable {
    case fiveMinutes
    case oneHour
    case oneDay
    case indefinitely

    var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .oneHour: return 60 * 60
        case .oneDay: return 24 * 60 * 60
        case .indefinitely: return nil
        }
    }
}

enum CanonicalIntentEvidence: String, Equatable {
    case available
    case unavailable
    case completed
    case refused
    case failed
    case moved
    case movedElsewhere
    case changed
    case noEvidence
    case invalidQuery
    case ledgerUnavailable
}

enum CanonicalIntentLifecycle: String, Equatable {
    case active
    case fixture
    case notLoaded
    case unavailable
}

enum CanonicalIntentPausePresentation: String, Equatable {
    case running
    case pausedIndefinitely
    case pausedUntil
    case unreadable
}

enum CanonicalIntentHistoryIntegrity: String, Equatable {
    case valid
    case degraded
}

struct CanonicalIntentCommandOutput: Equatable {
    let evidence: CanonicalIntentEvidence
    let receiptID: String?
}

struct CanonicalIntentTidyNowOutput: Equatable {
    let evidence: CanonicalIntentEvidence
    let movedCount: Int
    let failedCount: Int
    let skippedFreshCount: Int
    let receiptID: String?
}

struct CanonicalIntentStatusOutput: Equatable {
    let evidence: CanonicalIntentEvidence
    let lifecycle: CanonicalIntentLifecycle
    let pause: CanonicalIntentPausePresentation
}

struct CanonicalIntentRecentMove: Equatable {
    let name: String?
    let category: String?
    let outcome: String
    let timestamp: String?
    let undoEligible: Bool
}

struct CanonicalIntentRecentMovesOutput: Equatable {
    let evidence: CanonicalIntentEvidence
    let integrity: CanonicalIntentHistoryIntegrity
    let entries: [CanonicalIntentRecentMove]
    let hasMore: Bool
}

struct CanonicalIntentWhereDidItGoOutput: Equatable {
    let evidence: CanonicalIntentEvidence
    let category: String?
}

struct CanonicalIntentAdapter {
    static let maximumRecentMoves = 10

    let core: CanonicalApplicationCore

    init(core: CanonicalApplicationCore) {
        self.core = core
    }

    func tidyNow() -> CanonicalIntentTidyNowOutput {
        let result = core.tidyNow()
        return CanonicalIntentTidyNowOutput(
            evidence: evidence(for: result),
            movedCount: result.moved.count,
            failedCount: result.failed.count,
            skippedFreshCount: result.skippedFresh,
            receiptID: result.receiptID
        )
    }

    func pause(_ duration: CanonicalIntentPauseDuration) -> CanonicalIntentCommandOutput {
        let result: CanonicalCommandResult
        if let seconds = duration.seconds {
            result = core.pause(for: seconds)
        } else {
            result = core.pauseIndefinitely()
        }
        return commandOutput(result)
    }

    func resume() -> CanonicalIntentCommandOutput {
        commandOutput(core.resume())
    }

    func status() -> CanonicalIntentStatusOutput {
        let lifecycle = lifecyclePresentation(core.installationStatus())
        return CanonicalIntentStatusOutput(
            evidence: lifecycle == .unavailable ? .unavailable : .available,
            lifecycle: lifecycle,
            pause: pausePresentation(core.pauseState())
        )
    }

    func recentMoves() -> CanonicalIntentRecentMovesOutput {
        let history = core.history(page: 0, limit: Self.maximumRecentMoves)
        let integrity: CanonicalIntentHistoryIntegrity
        let evidence: CanonicalIntentEvidence
        switch history.integrity {
        case .valid:
            integrity = .valid
            evidence = .available
        case .degraded:
            integrity = .degraded
            evidence = .ledgerUnavailable
        }
        return CanonicalIntentRecentMovesOutput(
            evidence: evidence,
            integrity: integrity,
            entries: history.entries.prefix(Self.maximumRecentMoves).map {
                CanonicalIntentRecentMove(
                    name: $0.originalName,
                    category: $0.category,
                    outcome: $0.receipt.outcome,
                    timestamp: $0.timestamp,
                    undoEligible: $0.undoEligible
                )
            },
            hasMore: history.hasMore
        )
    }

    func whereDidItGo(named name: String) -> CanonicalIntentWhereDidItGoOutput {
        let result = core.whereDidItGoResult(named: name)
        switch result.status {
        case .moved:
            return CanonicalIntentWhereDidItGoOutput(evidence: .moved, category: result.category)
        case .movedElsewhere:
            return CanonicalIntentWhereDidItGoOutput(evidence: .movedElsewhere, category: result.category)
        case .changed:
            return CanonicalIntentWhereDidItGoOutput(evidence: .changed, category: result.category)
        case .noEvidence:
            return CanonicalIntentWhereDidItGoOutput(evidence: .noEvidence, category: nil)
        case .invalidQuery:
            return CanonicalIntentWhereDidItGoOutput(evidence: .invalidQuery, category: nil)
        case .ledgerUnavailable:
            return CanonicalIntentWhereDidItGoOutput(evidence: .ledgerUnavailable, category: nil)
        }
    }

    private func commandOutput(_ result: CanonicalCommandResult) -> CanonicalIntentCommandOutput {
        CanonicalIntentCommandOutput(evidence: evidence(for: result), receiptID: result.receiptID)
    }

    private func evidence(for result: CanonicalCommandResult) -> CanonicalIntentEvidence {
        if result.refusal != nil { return .refused }
        switch result.outcome {
        case .completed: return .completed
        case .prepared, .failed: return .failed
        }
    }

    private func evidence(for result: CanonicalTidyNowResult) -> CanonicalIntentEvidence {
        if result.refusal != nil { return .refused }
        return result.failed.isEmpty ? .completed : .failed
    }

    private func lifecyclePresentation(_ status: CanonicalLifecycleStatus) -> CanonicalIntentLifecycle {
        switch status {
        case .active: return .active
        case .fixture: return .fixture
        case .notLoaded: return .notLoaded
        case .unavailable: return .unavailable
        }
    }

    private func pausePresentation(_ state: CanonicalPauseState) -> CanonicalIntentPausePresentation {
        switch state {
        case .running: return .running
        case .pausedIndefinitely: return .pausedIndefinitely
        case .pausedUntil: return .pausedUntil
        case .unreadable: return .unreadable
        }
    }
}

/// The bridge serializes all intent entry points. The core remains injected at
/// the application boundary and is never constructed by an intent definition.
final class DeskTidyIntentBridge: @unchecked Sendable {
    static let shared = DeskTidyIntentBridge()

    private let lock = NSLock()
    private var adapter: CanonicalIntentAdapter?

    init(adapter: CanonicalIntentAdapter? = nil) {
        self.adapter = adapter
    }

    func install(adapter: CanonicalIntentAdapter) {
        lock.lock()
        self.adapter = adapter
        lock.unlock()
    }

    func tidyNow() -> CanonicalIntentTidyNowOutput {
        withAdapter(
            unavailable: CanonicalIntentTidyNowOutput(
                evidence: .unavailable, movedCount: 0, failedCount: 0, skippedFreshCount: 0, receiptID: nil
            ),
            operation: { $0.tidyNow() }
        )
    }

    func pause(_ duration: CanonicalIntentPauseDuration) -> CanonicalIntentCommandOutput {
        withAdapter(
            unavailable: CanonicalIntentCommandOutput(evidence: .unavailable, receiptID: nil),
            operation: { $0.pause(duration) }
        )
    }

    func resume() -> CanonicalIntentCommandOutput {
        withAdapter(
            unavailable: CanonicalIntentCommandOutput(evidence: .unavailable, receiptID: nil),
            operation: { $0.resume() }
        )
    }

    func status() -> CanonicalIntentStatusOutput {
        withAdapter(
            unavailable: CanonicalIntentStatusOutput(evidence: .unavailable, lifecycle: .unavailable, pause: .unreadable),
            operation: { $0.status() }
        )
    }

    func recentMoves() -> CanonicalIntentRecentMovesOutput {
        withAdapter(
            unavailable: CanonicalIntentRecentMovesOutput(evidence: .unavailable, integrity: .degraded, entries: [], hasMore: false),
            operation: { $0.recentMoves() }
        )
    }

    func whereDidItGo(named name: String) -> CanonicalIntentWhereDidItGoOutput {
        withAdapter(
            unavailable: CanonicalIntentWhereDidItGoOutput(evidence: .unavailable, category: nil),
            operation: { $0.whereDidItGo(named: name) }
        )
    }

    private func withAdapter<Result>(unavailable: Result, operation: (CanonicalIntentAdapter) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        guard let adapter else { return unavailable }
        return operation(adapter)
    }
}
