import Foundation

// ============================================================================
//  R1A gates — the effective-state fixture matrix, cross-surface parity, and
//  fail-closed UI mapping. Run via `desktidy-sort --state-test`.
//
//  Every fixture is an isolated temp world (agents dir + launchd-state file +
//  target root + app dir) injected through the same environment variables the
//  real surfaces read. Live launchd, the real Desktop, and the personal mover
//  are never touched.
//
//  Parity is proven mechanically, not assumed: for each fixture the in-process
//  model result (what the app renders) is compared with the JSON printed by a
//  REAL child invocation of the CLI (`--effective-state --json`).
// ============================================================================

final class R1ATests {
    let binaryPath: String
    private let fm = FileManager.default
    private var passCount = 0
    private var failCount = 0

    init(binaryPath: String) { self.binaryPath = binaryPath }

    private func check(_ id: String, _ desc: String, _ ok: Bool, _ detail: String = "") {
        if ok { print("PASS  \(id)  \(desc)"); passCount += 1 }
        else { print("FAIL  \(id)  \(desc)\(detail.isEmpty ? "" : " — \(detail)")"); failCount += 1 }
    }

    private func tempDir(_ tag: String) -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("desktidy-r1a-\(tag)-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct Fixture {
        let name: String
        let expected: OverallState
        let agents: URL
        let states: [String: String]
        let target: URL
        let app: URL
    }

    private func writePlist(_ dir: URL, label: String, watch: [String]?, program: String,
                            targetEnv: String? = nil) {
        var dict: [String: Any] = ["Label": label, "ProgramArguments": [program]]
        if let watch { dict["WatchPaths"] = watch }
        if let targetEnv { dict["EnvironmentVariables"] = ["DESKTIDY_TARGET_DIR": targetEnv] }
        let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try! data.write(to: dir.appendingPathComponent("\(label).plist"))
    }

    private func makeProgram(_ name: String) -> String {
        let p = tempDir("bin").appendingPathComponent(name)
        fm.createFile(atPath: p.path, contents: Data("#!/bin/sh\n".utf8))
        return p.path
    }

    /// Compute the model in-process (the app's exact input) under fixture env.
    private func modelState(_ f: Fixture) -> EffectiveStateReport {
        setenv("DESKTIDY_AGENTS_DIR", f.agents.path, 1)
        setenv("DESKTIDY_TARGET_DIR", f.target.path, 1)
        setenv("DESKTIDY_APP_DIR", f.app.path, 1)
        let stateFile = f.agents.appendingPathComponent("launchd-state.json")
        let enc = try! JSONSerialization.data(withJSONObject: f.states)
        try! enc.write(to: stateFile)
        setenv("DESKTIDY_LAUNCHD_STATE_FILE", stateFile.path, 1)
        defer {
            unsetenv("DESKTIDY_AGENTS_DIR"); unsetenv("DESKTIDY_TARGET_DIR")
            unsetenv("DESKTIDY_APP_DIR"); unsetenv("DESKTIDY_LAUNCHD_STATE_FILE")
        }
        return EffectiveState.compute()
    }

    /// Invoke the real CLI as a child with the fixture env; decode its JSON.
    private func cliState(_ f: Fixture) -> EffectiveStateReport? {
        let stateFile = f.agents.appendingPathComponent("launchd-state.json")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["--effective-state", "--json"]
        var env = ProcessInfo.processInfo.environment
        env["DESKTIDY_AGENTS_DIR"] = f.agents.path
        env["DESKTIDY_TARGET_DIR"] = f.target.path
        env["DESKTIDY_APP_DIR"] = f.app.path
        env["DESKTIDY_LAUNCHD_STATE_FILE"] = stateFile.path
        p.environment = env
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return try? JSONDecoder().decode(EffectiveStateReport.self, from: data)
    }

    // ------------------------------------------------------------------ run
    func runAll() -> Bool {
        let fixtures = buildFixtures()

        // S-gates: state matrix, one per fixture.
        for (i, f) in fixtures.enumerated() {
            let report = modelState(f)
            check(String(format: "S%02d", i + 1),
                  "fixture '\(f.name)' → \(f.expected.rawValue)",
                  report.overall == f.expected,
                  "got \(report.overall.rawValue): \(report.overallReason)")
        }

        // P-gates: cross-surface parity — CLI JSON must equal the model.
        for (i, f) in fixtures.enumerated() {
            let model = modelState(f)
            guard let cli = cliState(f) else {
                check(String(format: "P%02d", i + 1), "parity '\(f.name)'", false, "CLI produced no decodable JSON")
                continue
            }
            let same = cli.overall == model.overall
                && cli.foreignMovers == model.foreignMovers
                && cli.productAgentState == model.productAgentState
                && cli.targetExists == model.targetExists
                && cli.ledger == model.ledger
            check(String(format: "P%02d", i + 1),
                  "parity '\(f.name)': CLI == app model",
                  same,
                  "cli=\(cli.overall.rawValue) model=\(model.overall.rawValue)")
        }

        // U-gates: fail-closed UI mapping — unsafe states may never render healthy.
        let healthySymbol = EffectiveState.menuBarSymbol(for: .runningHealthy)
        for state in [OverallState.foreignConflict, .degradedLedger, .ambiguous] {
            check("U-\(state.rawValue)",
                  "\(state.rawValue) never renders the healthy symbol",
                  EffectiveState.menuBarSymbol(for: state) != healthySymbol)
        }
        for (i, f) in fixtures.enumerated() where f.expected != .runningHealthy {
            let report = modelState(f)
            let line = EffectiveState.statusLine(for: report)
            check(String(format: "U%02d", i + 1),
                  "fixture '\(f.name)' status line is not 'Active'",
                  !line.hasPrefix("Active"), line)
        }

        // R-gates: read-only confinement — computing state and building the
        // diagnostic must not create, modify, or remove anything in the target.
        do {
            let f = fixtures[0]
            _ = fm.createFile(atPath: f.target.appendingPathComponent("witness.pdf").path,
                              contents: Data("w".utf8))
            let before = try! fm.contentsOfDirectory(atPath: f.target.path).sorted()
            let report = modelState(f)
            _ = EffectiveState.diagnostic(report)
            _ = EffectiveState.statusLine(for: report)
            _ = cliState(f)
            let after = try! fm.contentsOfDirectory(atPath: f.target.path).sorted()
            check("R01", "state computation + diagnostic are read-only on the target", before == after,
                  "before=\(before) after=\(after)")
            let ledgerFile = f.app.appendingPathComponent("receipts/ledger.jsonl")
            check("R02", "state computation writes no ledger", !fm.fileExists(atPath: ledgerFile.path))
        }

        runTargetResolutionGates()

        print("R1A GATES: \(passCount) passed, \(failCount) failed")
        return failCount == 0
    }

    private func writeNativeConfig(_ app: URL, object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try! data.write(to: app.appendingPathComponent("config.json"))
    }

    private func applyFixtureEnv(_ f: Fixture, omitTargetEnv: Bool = false) -> URL {
        if omitTargetEnv { unsetenv("DESKTIDY_TARGET_DIR") }
        else { setenv("DESKTIDY_TARGET_DIR", f.target.path, 1) }
        setenv("DESKTIDY_AGENTS_DIR", f.agents.path, 1)
        setenv("DESKTIDY_APP_DIR", f.app.path, 1)
        let stateFile = f.agents.appendingPathComponent("launchd-state.json")
        let enc = try! JSONSerialization.data(withJSONObject: f.states)
        try! enc.write(to: stateFile)
        setenv("DESKTIDY_LAUNCHD_STATE_FILE", stateFile.path, 1)
        return stateFile
    }

    private func clearFixtureEnv() {
        unsetenv("DESKTIDY_AGENTS_DIR"); unsetenv("DESKTIDY_TARGET_DIR")
        unsetenv("DESKTIDY_APP_DIR"); unsetenv("DESKTIDY_LAUNCHD_STATE_FILE")
    }

    private func runTargetResolutionGates() {
        func world(_ name: String) -> Fixture {
            Fixture(name: name, expected: .ambiguous,
                    agents: tempDir("agents"), states: [:],
                    target: tempDir("target"), app: tempDir("app"))
        }

        // T01: malformed native config refuses instead of env/default fallback.
        do {
            let f = world("malformed-native-config")
            try? Data("not-json{".utf8).write(to: f.app.appendingPathComponent("config.json"))
            let report = modelState(f)
            check("T01", "malformed native config refuses instead of env/default fallback",
                  report.overall == .ambiguous && report.targetResolution == "invalid",
                  "got \(report.overall.rawValue) res=\(report.targetResolution): \(report.overallReason)")
        }

        // T02: no config/plist/env → default Desktop path (fixture agents, no live probe).
        do {
            let f = world("default")
            _ = applyFixtureEnv(f, omitTargetEnv: true)
            defer { clearFixtureEnv() }
            let report = EffectiveState.compute()
            let expected = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(Config.targetDirName).path
            check("T02", "no config/plist/env → default Desktop",
                  report.targetSource == TargetSource.defaultDesktop.rawValue && report.watchedTarget == expected,
                  "source=\(report.targetSource) target=\(report.watchedTarget)")
        }

        // T03: env only.
        do {
            let f = world("env-only")
            let report = modelState(f)
            check("T03", "env only → environment source",
                  report.targetSource == TargetSource.environment.rawValue && report.watchedTarget == f.target.path,
                  "source=\(report.targetSource) target=\(report.watchedTarget)")
        }

        // T04: plist overrides env.
        do {
            let f = world("plist-over-env")
            let plistTarget = tempDir("plist-target")
            writePlist(f.agents, label: "com.desktidy.sort", watch: [plistTarget.path],
                       program: makeProgram("desktidy-sort"), targetEnv: plistTarget.path)
            let report = modelState(f) // env still points at f.target
            check("T04", "plist overrides env",
                  report.targetSource == TargetSource.installedPlist.rawValue && report.watchedTarget == plistTarget.path,
                  "source=\(report.targetSource) target=\(report.watchedTarget)")
        }

        // T05: valid native config overrides plist and env.
        do {
            let f = world("config-over-plist")
            let plistTarget = tempDir("plist-target")
            let configTarget = tempDir("config-target")
            writePlist(f.agents, label: "com.desktidy.sort", watch: [plistTarget.path],
                       program: makeProgram("desktidy-sort"), targetEnv: plistTarget.path)
            writeNativeConfig(f.app, object: ["schema": 1, "target": configTarget.path])
            let report = modelState(f)
            check("T05", "valid native config overrides plist",
                  report.targetSource == TargetSource.nativeConfig.rawValue && report.watchedTarget == configTarget.path,
                  "source=\(report.targetSource) target=\(report.watchedTarget)")
        }

        // T06: empty / wrong-type native target refuses.
        do {
            let f = world("empty-native-target")
            writeNativeConfig(f.app, object: ["schema": 1, "target": ""])
            let empty = modelState(f)
            writeNativeConfig(f.app, object: ["schema": 1, "target": 12])
            let wrong = modelState(f)
            check("T06", "empty/wrong-type native target refuses",
                  empty.overall == .ambiguous && wrong.overall == .ambiguous
                    && empty.targetResolution == "invalid" && wrong.targetResolution == "invalid",
                  "empty=\(empty.overall.rawValue) wrong=\(wrong.overall.rawValue)")
        }

        // T07: unreadable selected config refuses (no env fallback).
        do {
            let f = world("unreadable-config")
            let cfg = f.app.appendingPathComponent("config.json")
            try? Data("{\"schema\":1,\"target\":\"/tmp\"}".utf8).write(to: cfg)
            try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: cfg.path)
            let report = modelState(f)
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: cfg.path)
            check("T07", "unreadable native config refuses",
                  report.overall == .ambiguous && report.targetResolution == "invalid",
                  "got \(report.overall.rawValue): \(report.overallReason)")
        }

        // T08: missing/non-directory target cannot be healthy.
        do {
            let f = world("missing-resolved-target")
            try? fm.removeItem(at: f.target)
            let report = modelState(f)
            check("T08", "missing target cannot be runningHealthy",
                  report.overall == .ambiguous && report.overall != .runningHealthy,
                  "got \(report.overall.rawValue)")
        }

        // T09: engine target equals EffectiveState target for every valid source.
        do {
            var same = true
            var detail = ""
            // env
            let envF = world("parity-env")
            _ = applyFixtureEnv(envF)
            let envReport = EffectiveState.compute()
            let envEngine = DeskTidy()
            if envEngine.target.path != envReport.watchedTarget { same = false; detail += " env" }
            // plist
            let plistF = world("parity-plist")
            let plistTarget = tempDir("parity-plist-target")
            writePlist(plistF.agents, label: "com.desktidy.sort", watch: [plistTarget.path],
                       program: makeProgram("desktidy-sort"), targetEnv: plistTarget.path)
            _ = applyFixtureEnv(plistF)
            let plistReport = EffectiveState.compute()
            let plistEngine = DeskTidy()
            if plistEngine.target.path != plistReport.watchedTarget { same = false; detail += " plist" }
            // native config
            let cfgF = world("parity-config")
            let cfgTarget = tempDir("parity-cfg-target")
            writeNativeConfig(cfgF.app, object: ["schema": 1, "target": cfgTarget.path])
            _ = applyFixtureEnv(cfgF)
            let cfgReport = EffectiveState.compute()
            let cfgEngine = DeskTidy()
            if cfgEngine.target.path != cfgReport.watchedTarget { same = false; detail += " config" }
            clearFixtureEnv()
            check("T09", "engine target equals EffectiveState target for valid sources",
                  same && envReport.targetSource == "environment"
                    && plistReport.targetSource == "installedPlist"
                    && cfgReport.targetSource == "nativeConfig",
                  "mismatch=\(detail) sources=\(envReport.targetSource),\(plistReport.targetSource),\(cfgReport.targetSource)")
        }

        // T10: engine refuses every ambiguous target fixture (exit 3, no move).
        do {
            let f = world("engine-refuse")
            try? Data("not-json{".utf8).write(to: f.app.appendingPathComponent("config.json"))
            let witness = f.target.appendingPathComponent("stay.pdf")
            fm.createFile(atPath: witness.path, contents: Data("x".utf8))
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: witness.path)
            let stateFile = applyFixtureEnv(f)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binaryPath)
            p.arguments = []
            var env = ProcessInfo.processInfo.environment
            env["DESKTIDY_AGENTS_DIR"] = f.agents.path
            env["DESKTIDY_TARGET_DIR"] = f.target.path
            env["DESKTIDY_APP_DIR"] = f.app.path
            env["DESKTIDY_LAUNCHD_STATE_FILE"] = stateFile.path
            p.environment = env
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            clearFixtureEnv()
            let stayed = fm.fileExists(atPath: witness.path)
            check("T10", "engine refuses ambiguous target (exit 3, no move)",
                  p.terminationStatus == 3 && stayed, "exit=\(p.terminationStatus) stayed=\(stayed)")
        }

        // T11: malformed installed sort plist refuses rather than env fallback.
        do {
            let f = world("malformed-plist")
            try? Data("not a plist".utf8).write(to: f.agents.appendingPathComponent("com.desktidy.sort.plist"))
            let report = modelState(f)
            check("T11", "malformed sort plist refuses instead of env fallback",
                  report.overall == .ambiguous && report.targetSource == TargetSource.installedPlist.rawValue,
                  "got \(report.overall.rawValue) source=\(report.targetSource): \(report.overallReason)")
        }
    }

    // ------------------------------------------------------------ fixtures
    private func buildFixtures() -> [Fixture] {
        var out: [Fixture] = []

        func base(_ name: String, _ expected: OverallState,
                  mutate: (inout Fixture) -> Void = { _ in }) {
            var f = Fixture(name: name, expected: expected,
                            agents: tempDir("agents"), states: [:],
                            target: tempDir("target"), app: tempDir("app"))
            mutate(&f)
            out.append(f)
        }

        // 1. running under DeskTidy authority
        base("running", .runningHealthy) { f in
            self.writePlist(f.agents, label: "com.desktidy.sort", watch: [f.target.path],
                            program: self.makeProgram("desktidy-sort"), targetEnv: f.target.path)
            f = Fixture(name: f.name, expected: f.expected, agents: f.agents,
                        states: ["com.desktidy.sort": "running"], target: f.target, app: f.app)
        }
        // 2. paused / not loaded (no plists at all)
        base("paused", .pausedNotLoaded)
        // 3. same-root foreign conflict
        base("foreign-conflict", .foreignConflict) { f in
            self.writePlist(f.agents, label: "com.example.other-mover", watch: [f.target.path],
                            program: self.makeProgram("other"))
            f = Fixture(name: f.name, expected: f.expected, agents: f.agents,
                        states: ["com.example.other-mover": "running"], target: f.target, app: f.app)
        }
        // 4. symlink-equivalent conflict
        base("symlink-conflict", .foreignConflict) { f in
            let alias = self.tempDir("links").appendingPathComponent("alias")
            try? self.fm.createSymbolicLink(at: alias, withDestinationURL: f.target)
            self.writePlist(f.agents, label: "com.example.aliased", watch: [alias.path],
                            program: self.makeProgram("aliased"))
            f = Fixture(name: f.name, expected: f.expected, agents: f.agents,
                        states: ["com.example.aliased": "loaded"], target: f.target, app: f.app)
        }
        // 5. disjoint foreign mover → not a conflict; nothing loaded ⇒ paused
        base("disjoint-foreign", .pausedNotLoaded) { f in
            self.writePlist(f.agents, label: "com.example.elsewhere",
                            watch: [self.tempDir("other-root").path],
                            program: self.makeProgram("elsewhere"))
            f = Fixture(name: f.name, expected: f.expected, agents: f.agents,
                        states: ["com.example.elsewhere": "running"], target: f.target, app: f.app)
        }
        // 6. stale foreign plist (executable gone, not loaded) → paused, non-blocking
        base("stale-plist", .pausedNotLoaded) { f in
            self.writePlist(f.agents, label: "com.example.stale", watch: [f.target.path],
                            program: "/nonexistent/gone-\(UUID().uuidString)")
            f = Fixture(name: f.name, expected: f.expected, agents: f.agents,
                        states: ["com.example.stale": "not-loaded"], target: f.target, app: f.app)
        }
        // 7. unreadable agent definition → ambiguous
        base("unreadable-agent", .ambiguous) { f in
            try? Data("not a plist".utf8).write(to: f.agents.appendingPathComponent("com.example.junk.plist"))
        }
        // 8. missing target directory → ambiguous
        base("missing-target", .ambiguous) { f in
            try? self.fm.removeItem(at: f.target)
        }
        // 9. invalid ledger (tampered chain) → degradedLedger
        base("invalid-ledger", .degradedLedger) { f in
            let ledger = ReceiptLedger(appDirectory: f.app)
            let svc = MovementService(root: f.target, ledger: ledger,
                                      moverVersion: DeskTidyVersion.string, log: { _ in })
            let src = f.target.appendingPathComponent("seed.pdf")
            self.fm.createFile(atPath: src.path, contents: Data("s".utf8))
            try? self.fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                       ofItemAtPath: src.path)
            _ = svc.perform(source: src, category: .documents, ruleID: "seed",
                            settleMTime: Date(timeIntervalSinceNow: -3600), settleAge: 3600)
            if var text = try? String(contentsOf: ledger.ledgerURL, encoding: .utf8) {
                text = text.replacingOccurrences(of: "seed.pdf", with: "SEED.pdf")
                try? Data(text.utf8).write(to: ledger.ledgerURL)
            }
        }
        return out
    }
}
