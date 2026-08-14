import Foundation

// ============================================================================
//  R1A — One read-only effective-state truth, shared by the CLI and the
//  menu-bar app.
//
//  Everything here is DERIVED from evidence, never guessed:
//    • movement authority   → the R0 AuthorityGuard (never duplicated);
//    • product agent state  → launchd probes (live or fixture) for our labels;
//    • watched target       → the installed product plist's environment, else
//                             DESKTIDY_TARGET_DIR, else the default — and the
//                             directory must actually exist to count;
//    • ledger health        → ReceiptLedger.verifyChain on the real file.
//
//  A plist existing on disk is not "running". An API existing is not "works".
//  Every unprovable input degrades the overall state — never upgrades it.
//
//  This file (plus Config/Authority/Receipts) is the complete dependency set
//  of the menu-bar app. It performs no file mutations, no service (un)loading,
//  and no ledger writes — enforced by a comment-stripping CI grep.
// ============================================================================

/// Overall product state, strictly ordered fail-closed:
/// ambiguity dominates conflict dominates ledger damage dominates paused
/// dominates running. Only `runningHealthy` may ever render as healthy.
enum OverallState: String, Codable {
    case runningHealthy      // DeskTidy is the sole authority, loaded, ledger sane
    case pausedNotLoaded     // no conflict, but DeskTidy's agent isn't loaded
    case foreignConflict     // another authority owns the root — we must not run
    case degradedLedger      // movement history integrity cannot be trusted
    case ambiguous           // authority/target unprovable — fail closed
}

enum LedgerHealth: Codable, Equatable {
    case valid(receiptCount: Int)
    case absent                       // no ledger yet — normal for a fresh install
    case invalid(reason: String)
}

struct EffectiveStateReport: Codable {
    var schema: Int = 1
    var generatedAt: String
    var overall: OverallState
    var overallReason: String
    var watchedTarget: String
    var watchedTargetCanonical: String?
    var targetExists: Bool
    var targetSource: String               // nativeConfig | installedPlist | environment | defaultDesktop
    var targetResolution: String           // resolved | invalid
    var productAgentLoaded: Bool
    var productAgentState: String          // running | loadedIdle | notLoaded | stale | uninspectable
    var effectiveMoverLabel: String?       // provable mover of this root, if any
    var effectiveMoverProgram: String?
    var foreignMovers: [String]            // labels sharing the root (conflict evidence)
    var ambiguityReason: String?
    var ledger: String                     // "valid(N)" | "absent" | "invalid: reason"
    var ledgerReceiptCount: Int
    var suggestionsPresent: Bool           // smart-triage suggestions file exists (display-only)
    var moverVersion: String
}

enum EffectiveState {

    /// The single derivation. `now` is injectable for deterministic tests.
    static func compute() -> EffectiveStateReport {
        let fm = FileManager.default

        // --- watched target: one resolver shared with the movement engine
        let resolution = TargetResolver.resolve()
        let target: String
        let targetSource: String
        let targetExists: Bool
        let canonical: String?
        let invalidReason: String?
        switch resolution {
        case .resolved(let path, let source, let exists):
            target = path
            targetSource = source.rawValue
            targetExists = exists
            canonical = exists ? AuthorityGuard.canonicalize(path).path : nil
            invalidReason = nil
        case .invalid(let reason, let source, let attempted):
            target = attempted ?? ""
            targetSource = source.rawValue
            targetExists = false
            canonical = nil
            invalidReason = reason
        }

        // --- authority (the R0 guard, unmodified). Invalid target selection
        // never falls back to a live default root for the probe.
        let guardian = AuthorityGuard()
        let decision: AuthorityDecision
        if let invalidReason {
            decision = .ambiguous(reason: invalidReason, records: [])
        } else {
            decision = guardian.evaluate(rootPath: target)
        }

        // --- product agent state (same probe mechanism, self labels)
        let selfRecord: MoverRecord?
        if invalidReason == nil {
            let (records, _) = guardian.relevantMovers(for: AuthorityGuard.canonicalize(target))
            selfRecord = records.first { $0.isSelf && $0.label == "com.desktidy.sort" }
        } else {
            selfRecord = nil
        }
        let productState = selfRecord?.state ?? .notLoaded
        let productLoaded = productState == .running || productState == .loadedIdle

        // --- ledger health
        let appDir = DeskTidyPaths.appDirectory()
        let ledger = ReceiptLedger(appDirectory: appDir)
        let ledgerHealth: LedgerHealth
        if !fm.fileExists(atPath: ledger.ledgerURL.path) {
            ledgerHealth = .absent
        } else if let problem = ledger.verifyChain() {
            ledgerHealth = .invalid(reason: problem)
        } else {
            ledgerHealth = .valid(receiptCount: ledger.readAll().receipts.count)
        }

        // --- effective mover: only when provable from live evidence
        var moverLabel: String?
        var moverProgram: String?
        var foreign: [String] = []
        switch decision {
        case .conflict(let movers):
            foreign = movers.map { $0.label }
            if let live = movers.first(where: { $0.state == .running }) ?? movers.first {
                moverLabel = live.label; moverProgram = live.programPath
            }
        case .sole, .soleWithStale:
            if productLoaded { moverLabel = "com.desktidy.sort"; moverProgram = selfRecord?.programPath }
        case .ambiguous:
            break   // unprovable — leave nil rather than guess
        }

        // --- overall, strictly fail-closed
        var overall: OverallState
        var reason: String
        var ambiguity: String?
        if let invalidReason {
            overall = .ambiguous
            reason = "target resolution failed (\(targetSource): \(invalidReason))"
            ambiguity = invalidReason
        } else if !targetExists {
            overall = .ambiguous
            reason = "watched target does not exist (\(targetSource): \(target))"
            ambiguity = reason
        } else {
            switch decision {
            case .ambiguous(let why, _):
                overall = .ambiguous
                reason = "movement authority unprovable: \(why)"
                ambiguity = why
            case .conflict:
                overall = .foreignConflict
                reason = "another authority owns this root: \(foreign.joined(separator: ", "))"
            case .sole, .soleWithStale:
                if case .invalid(let why) = ledgerHealth {
                    overall = .degradedLedger
                    reason = "receipt ledger failed verification: \(why)"
                } else if productLoaded {
                    overall = .runningHealthy
                    reason = "DeskTidy is the sole movement authority for this root"
                } else {
                    overall = .pausedNotLoaded
                    reason = "no conflicting authority, and DeskTidy's agent is not loaded"
                }
            }
        }

        let ledgerString: String
        let ledgerCount: Int
        switch ledgerHealth {
        case .valid(let n): ledgerString = "valid(\(n))"; ledgerCount = n
        case .absent:       ledgerString = "absent";      ledgerCount = 0
        case .invalid(let why): ledgerString = "invalid: \(why)"; ledgerCount = 0
        }

        let suggestions = targetExists && fm.fileExists(
            atPath: URL(fileURLWithPath: target)
                .appendingPathComponent(Config.folderInbox)
                .appendingPathComponent("SMART_TRIAGE_SUGGESTIONS.md").path)

        let iso = ISO8601DateFormatter()
        return EffectiveStateReport(
            generatedAt: iso.string(from: Date()),
            overall: overall,
            overallReason: reason,
            watchedTarget: target,
            watchedTargetCanonical: canonical,
            targetExists: targetExists,
            targetSource: targetSource,
            targetResolution: invalidReason == nil ? "resolved" : "invalid",
            productAgentLoaded: productLoaded,
            productAgentState: productState.rawValue,
            effectiveMoverLabel: moverLabel,
            effectiveMoverProgram: moverProgram,
            foreignMovers: foreign,
            ambiguityReason: ambiguity,
            ledger: ledgerString,
            ledgerReceiptCount: ledgerCount,
            suggestionsPresent: suggestions,
            moverVersion: DeskTidyVersion.string
        )
    }

    // ------------------------------------------------------------------ UI mapping
    // The menu-bar presentation derives from the report ONLY through these
    // pure functions, so fail-closed rendering is testable without a GUI.

    static func menuBarSymbol(for overall: OverallState) -> String {
        switch overall {
        case .runningHealthy:  return "tray.full"
        case .pausedNotLoaded: return "pause.circle"
        case .foreignConflict: return "exclamationmark.triangle"
        case .degradedLedger:  return "exclamationmark.triangle"
        case .ambiguous:       return "questionmark.circle"
        }
    }

    static func statusLine(for report: EffectiveStateReport) -> String {
        switch report.overall {
        case .runningHealthy:  return "Active — sole authority for \(shortPath(report.watchedTarget))"
        case .pausedNotLoaded: return "Paused — agent not loaded"
        case .foreignConflict: return "Conflict — \(report.foreignMovers.joined(separator: ", ")) owns this folder"
        case .degradedLedger:  return "Attention — receipt ledger failed verification"
        case .ambiguous:       return "Unknown — \(report.ambiguityReason ?? "state unprovable")"
        }
    }

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Bounded plain-text diagnostic for the copy action. No file contents.
    static func diagnostic(_ r: EffectiveStateReport) -> String {
        """
        DeskTidy effective state (\(r.generatedAt))
        overall: \(r.overall.rawValue) — \(r.overallReason)
        target: \(r.watchedTarget) (exists: \(r.targetExists), source: \(r.targetSource), resolution: \(r.targetResolution))
        product agent: \(r.productAgentState)
        effective mover: \(r.effectiveMoverLabel ?? "unprovable")\(r.effectiveMoverProgram.map { " (\($0))" } ?? "")
        foreign movers: \(r.foreignMovers.isEmpty ? "none" : r.foreignMovers.joined(separator: ", "))
        ledger: \(r.ledger)
        suggestions file present: \(r.suggestionsPresent)
        version: \(r.moverVersion)
        """
    }
}
