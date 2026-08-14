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
//  of the menu-bar app. It contains NO mutating operations: no moveItem,
//  no removeItem, no bootstrap/bootout, no writes to the ledger.
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
        let env = ProcessInfo.processInfo.environment
        let home = fm.homeDirectoryForCurrentUser

        // --- watched target: installed plist env > DESKTIDY_TARGET_DIR > default
        let agentsDir: URL = {
            if let d = env["DESKTIDY_AGENTS_DIR"], !d.isEmpty {
                return URL(fileURLWithPath: (d as NSString).expandingTildeInPath, isDirectory: true)
            }
            return home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        }()
        var target: String
        var targetSource: String
        if let fromPlist = installedTarget(agentsDir: agentsDir) {
            target = fromPlist; targetSource = "installed plist"
        } else if let t = env["DESKTIDY_TARGET_DIR"], !t.isEmpty {
            target = (t as NSString).expandingTildeInPath; targetSource = "environment"
        } else {
            target = home.appendingPathComponent(Config.targetDirName).path; targetSource = "default"
        }
        var isDir: ObjCBool = false
        let targetExists = fm.fileExists(atPath: target, isDirectory: &isDir) && isDir.boolValue
        let canonical = targetExists ? AuthorityGuard.canonicalize(target).path : nil

        // --- authority (the R0 guard, unmodified)
        let guardian = AuthorityGuard()
        let decision = guardian.evaluate(rootPath: target)

        // --- product agent state (same probe mechanism, self labels)
        let (records, _) = guardian.relevantMovers(for: AuthorityGuard.canonicalize(target))
        let selfRecord = records.first { $0.isSelf && $0.label == "com.desktidy.sort" }
        let productState = selfRecord?.state ?? .notLoaded
        let productLoaded = productState == .running || productState == .loadedIdle

        // --- ledger health
        let appDir: URL = {
            if let a = env["DESKTIDY_APP_DIR"], !a.isEmpty {
                return URL(fileURLWithPath: (a as NSString).expandingTildeInPath, isDirectory: true)
            }
            return home.appendingPathComponent("Library/Application Support/DeskTidy", isDirectory: true)
        }()
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
        if !targetExists {
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

    /// Watched target recorded in the installed product plist, if any.
    private static func installedTarget(agentsDir: URL) -> String? {
        let plist = agentsDir.appendingPathComponent("com.desktidy.sort.plist")
        guard let data = FileManager.default.contents(atPath: plist.path),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any],
              let envDict = dict["EnvironmentVariables"] as? [String: String],
              let t = envDict["DESKTIDY_TARGET_DIR"], !t.isEmpty else { return nil }
        return t
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
        target: \(r.watchedTarget) (exists: \(r.targetExists))
        product agent: \(r.productAgentState)
        effective mover: \(r.effectiveMoverLabel ?? "unprovable")\(r.effectiveMoverProgram.map { " (\($0))" } ?? "")
        foreign movers: \(r.foreignMovers.isEmpty ? "none" : r.foreignMovers.joined(separator: ", "))
        ledger: \(r.ledger)
        suggestions file present: \(r.suggestionsPresent)
        version: \(r.moverVersion)
        """
    }
}
