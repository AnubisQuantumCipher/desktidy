import Foundation

// ============================================================================
//  R0 — Single movement authority per canonical watched root.
//
//  Exactly one agent may move entries out of a watched root. Before DeskTidy
//  sets up agents or performs any movement pass, this guard:
//    1. canonicalizes the watched root (symlinks resolved + device/inode ID);
//    2. enumerates every launchd agent plist in the user's agents directory
//       and classifies the ones whose WatchPaths/QueueDirectories overlap the
//       same canonical root;
//    3. distinguishes running / loaded-idle / installed-not-loaded / stale /
//       uninspectable states;
//    4. REFUSES to proceed when any non-DeskTidy authority could move entries
//       from the same root, and FAILS CLOSED when authority is ambiguous.
//
//  The guard never mutates launchd state. Takeover/migration is deliberately
//  not implemented here — see docs/R0_AUTHORITY_AND_RECEIPTS.md.
//
//  Testability: the agents directory can be overridden with
//  DESKTIDY_AGENTS_DIR, and launchd load-state can be supplied from a JSON
//  fixture file via DESKTIDY_LAUNCHD_STATE_FILE ({"label": "running" |
//  "loaded" | "not-loaded"}). With a fixture present, no live launchctl
//  query is made, so hostile controls run hermetically.
// ============================================================================

enum MoverLoadState: String, Codable {
    case running            // loaded in launchd and has a live process
    case loadedIdle         // loaded in launchd, no process right now
    case notLoaded          // plist on disk, not in the launchd domain
    case stale              // plist on disk but its executable is missing
    case uninspectable      // plist unreadable/undecodable — cannot classify
}

struct MoverRecord {
    let label: String
    let plistPath: String
    let watchedPaths: [String]      // canonicalized
    let programPath: String?
    let state: MoverLoadState
    let isSelf: Bool                // one of DeskTidy's own agents
}

enum AuthorityDecision {
    case sole                                  // we are the only authority
    case soleWithStale([MoverRecord])          // only stale remnants share the root
    case conflict([MoverRecord])               // a live/installable foreign authority shares the root
    case ambiguous(reason: String, records: [MoverRecord]) // cannot prove — fail closed
}

struct CanonicalPath: Equatable {
    let path: String                 // realpath()-resolved absolute path
    let dev: UInt64?                 // st_dev when stat succeeds
    let ino: UInt64?                 // st_ino when stat succeeds

    static func == (a: CanonicalPath, b: CanonicalPath) -> Bool {
        if let ad = a.dev, let ai = a.ino, let bd = b.dev, let bi = b.ino {
            return ad == bd && ai == bi
        }
        return a.path == b.path
    }
}

final class AuthorityGuard {
    /// DeskTidy's own agent labels — never counted as foreign authorities.
    static let selfLabels: Set<String> = ["com.desktidy.sort", "com.desktidy.notify"]

    let agentsDir: URL
    private let fixtureStates: [String: String]?   // label -> state, from fixture file

    init() {
        let env = ProcessInfo.processInfo.environment
        let fm = FileManager.default
        if let d = env["DESKTIDY_AGENTS_DIR"], !d.isEmpty {
            agentsDir = URL(fileURLWithPath: (d as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            agentsDir = fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        }
        if let f = env["DESKTIDY_LAUNCHD_STATE_FILE"], !f.isEmpty,
           let data = fm.contents(atPath: (f as NSString).expandingTildeInPath),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            fixtureStates = dict
        } else if let f = env["DESKTIDY_LAUNCHD_STATE_FILE"], !f.isEmpty {
            // A fixture was requested but is unreadable: that is itself
            // ambiguity — surface it rather than silently probing live launchd.
            fixtureStates = [:]
        } else {
            fixtureStates = nil
        }
    }

    /// Explicit-injection initializer for tests.
    init(agentsDir: URL, fixtureStates: [String: String]?) {
        self.agentsDir = agentsDir
        self.fixtureStates = fixtureStates
    }

    // -- canonicalization ----------------------------------------------------
    static func canonicalize(_ path: String) -> CanonicalPath {
        let expanded = (path as NSString).expandingTildeInPath
        var resolved = expanded
        if let rp = realpath(expanded, nil) {
            resolved = String(cString: rp)
            free(rp)
        }
        var st = stat()
        if stat(resolved, &st) == 0 {
            return CanonicalPath(path: resolved, dev: UInt64(st.st_dev), ino: UInt64(st.st_ino))
        }
        return CanonicalPath(path: resolved, dev: nil, ino: nil)
    }

    // -- launchd state -------------------------------------------------------
    private func loadState(label: String, programExists: Bool) -> MoverLoadState {
        if let fixtures = fixtureStates {
            switch fixtures[label] {
            case "running":    return .running
            case "loaded":     return .loadedIdle
            case "not-loaded": return programExists ? .notLoaded : .stale
            case nil:          return programExists ? .notLoaded : .stale
            default:           return .uninspectable
            }
        }
        // Live probe (read-only): `launchctl print gui/<uid>/<label>`.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "gui/\(getuid())/\(label)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
        } catch {
            return .uninspectable
        }
        if p.terminationStatus != 0 {
            return programExists ? .notLoaded : .stale
        }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if text.contains("state = running") { return .running }
        return .loadedIdle
    }

    // -- enumeration ---------------------------------------------------------
    /// All agent plists whose watch paths overlap the given canonical root.
    func relevantMovers(for root: CanonicalPath) -> (records: [MoverRecord], unreadable: [String]) {
        let fm = FileManager.default
        var records: [MoverRecord] = []
        var unreadable: [String] = []

        let plists: [URL]
        do {
            plists = try fm.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "plist" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            // Cannot even list the agents directory: ambiguous by definition.
            return ([], [agentsDir.path])
        }

        for plist in plists {
            guard let data = fm.contents(atPath: plist.path),
                  let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = obj as? [String: Any] else {
                unreadable.append(plist.path)
                continue
            }
            let label = (dict["Label"] as? String) ?? plist.deletingPathExtension().lastPathComponent
            var watched: [String] = []
            for key in ["WatchPaths", "QueueDirectories"] {
                if let arr = dict[key] as? [String] { watched.append(contentsOf: arr) }
            }
            guard !watched.isEmpty else { continue }   // not a path-watching agent
            let canonWatched = watched.map { AuthorityGuard.canonicalize($0) }
            guard canonWatched.contains(where: { $0 == root }) else { continue }

            var program: String? = dict["Program"] as? String
            if program == nil, let args = dict["ProgramArguments"] as? [String] {
                // First argument that looks like an executable path (skip interpreters' flags).
                program = args.first
                if program == "/bin/bash" || program == "/bin/sh" || program == "/bin/zsh",
                   args.count > 1 { program = args[1] }
            }
            let programExists = program.map { fm.fileExists(atPath: $0) } ?? false
            let state = loadState(label: label, programExists: programExists)
            records.append(MoverRecord(
                label: label,
                plistPath: plist.path,
                watchedPaths: canonWatched.map { $0.path },
                programPath: program,
                state: state,
                isSelf: AuthorityGuard.selfLabels.contains(label)
            ))
        }
        return (records, unreadable)
    }

    // -- decision ------------------------------------------------------------
    func evaluate(rootPath: String) -> AuthorityDecision {
        let root = AuthorityGuard.canonicalize(rootPath)
        let (records, unreadable) = relevantMovers(for: root)

        if !unreadable.isEmpty {
            return .ambiguous(
                reason: "unreadable agent definition(s): \(unreadable.joined(separator: ", "))",
                records: records
            )
        }
        let foreign = records.filter { !$0.isSelf }
        if foreign.contains(where: { $0.state == .uninspectable }) {
            return .ambiguous(reason: "foreign agent state could not be inspected", records: foreign)
        }
        // Anything loaded, running, or merely installed-but-unloaded CAN move
        // entries (now, or at next login). Only provably stale remnants
        // (plist present, executable gone, not loaded) do not block.
        let live = foreign.filter { $0.state == .running || $0.state == .loadedIdle || $0.state == .notLoaded }
        if !live.isEmpty { return .conflict(live) }
        let stale = foreign.filter { $0.state == .stale }
        return stale.isEmpty ? .sole : .soleWithStale(stale)
    }

    // -- reporting -----------------------------------------------------------
    /// Exit codes: 0 = sole authority (possibly with stale remnants),
    /// 2 = conflict, 3 = ambiguous (fail closed).
    func diagnose(rootPath: String, json: Bool) -> Int32 {
        let root = AuthorityGuard.canonicalize(rootPath)
        let decision = evaluate(rootPath: rootPath)

        func recordLines(_ rs: [MoverRecord]) -> [String] {
            rs.map { r in
                "  - \(r.label) [\(r.state.rawValue)] plist=\(r.plistPath)"
                + (r.programPath.map { " program=\($0)" } ?? "")
                + " watches=\(r.watchedPaths.joined(separator: ","))"
            }
        }

        var verdict: String
        var detail: [String]
        var code: Int32
        switch decision {
        case .sole:
            verdict = "SOLE"; detail = ["no other movement authority watches this root"]; code = 0
        case .soleWithStale(let stale):
            verdict = "SOLE (stale remnants present)"
            detail = ["stale (executable missing, not loaded) — not blocking:"] + recordLines(stale)
            code = 0
        case .conflict(let movers):
            verdict = "CONFLICT — refusing movement authority"
            detail = ["another authority can move entries from this root:"] + recordLines(movers)
                   + ["resolution: run that service's own teardown, or point DeskTidy at a disjoint --target.",
                      "DeskTidy will not take over a watched root automatically."]
            code = 2
        case .ambiguous(let reason, let movers):
            verdict = "AMBIGUOUS — failing closed"
            detail = ["authority could not be established: \(reason)"] + recordLines(movers)
            code = 3
        }

        if json {
            var movers: [[String: Any]] = []
            let rs: [MoverRecord]
            switch decision {
            case .sole: rs = []
            case .soleWithStale(let x), .conflict(let x): rs = x
            case .ambiguous(_, let x): rs = x
            }
            for r in rs {
                movers.append(["label": r.label, "state": r.state.rawValue,
                               "plist": r.plistPath, "program": r.programPath ?? "",
                               "watches": r.watchedPaths])
            }
            let obj: [String: Any] = [
                "root": root.path, "verdict": verdict, "exitCode": Int(code),
                "movers": movers,
            ]
            if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: d, as: UTF8.self))
            }
        } else {
            print("DeskTidy authority check")
            print("root: \(root.path)")
            print("verdict: \(verdict)")
            detail.forEach { print($0) }
        }
        return code
    }
}
