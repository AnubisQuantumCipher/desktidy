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

        runNativeMenuControlGates(fixtures)

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
        runDuplicateKeyGates()
        runPathParityGates()
        runLaunchdFixtureGates()
        runIdentityGates()

        print("R1A GATES: \(passCount) passed, \(failCount) failed")
        return failCount == 0
    }

    private func runNativeMenuControlGates(_ fixtures: [Fixture]) {
        let healthy = modelState(fixtures.first { $0.expected == .runningHealthy }!)
        let operational = EffectiveState.nativeMenuControls(
            for: healthy,
            setupRequired: false,
            isPaused: false,
            hasUndoEligible: true,
            isBusy: false
        )
        check("U10", "configured healthy menu exposes operational controls",
              !operational.showSetup
                && operational.canTidyNow
                && operational.canPause
                && !operational.canResume
                && operational.canUndo)

        let onboarding = EffectiveState.nativeMenuControls(
            for: healthy,
            setupRequired: true,
            isPaused: false,
            hasUndoEligible: true,
            isBusy: false
        )
        check("U11", "onboarding exposes setup only",
              onboarding.showSetup
                && !onboarding.canTidyNow
                && !onboarding.canPause
                && !onboarding.canResume
                && !onboarding.canUndo)

        let paused = EffectiveState.nativeMenuControls(
            for: healthy,
            setupRequired: false,
            isPaused: true,
            hasUndoEligible: true,
            isBusy: false
        )
        check("U12", "paused menu exposes resume but no movement",
              !paused.canTidyNow
                && !paused.canPause
                && paused.canResume
                && !paused.canUndo)

        let busy = EffectiveState.nativeMenuControls(
            for: healthy,
            setupRequired: false,
            isPaused: false,
            hasUndoEligible: true,
            isBusy: true
        )
        check("U13", "busy menu disables every mutating control",
              !busy.canTidyNow && !busy.canPause && !busy.canResume && !busy.canUndo)

        let pausedSymbol = EffectiveState.menuBarSymbol(for: healthy.overall, isPaused: true)
        let runningSymbol = EffectiveState.menuBarSymbol(for: healthy.overall, isPaused: false)
        check("U14", "durable pause controls the status symbol and headline",
              pausedSymbol == "pause.circle.fill"
                && runningSymbol != pausedSymbol
                && EffectiveState.statusLine(for: healthy, isPaused: true).hasPrefix("Paused")
                && !EffectiveState.statusLine(for: healthy, isPaused: false).hasPrefix("Paused"))

        let notLoaded = modelState(fixtures.first { $0.expected == .pausedNotLoaded }!)
        check("U15", "an unloaded agent is not mislabeled as a durable pause",
              EffectiveState.menuBarSymbol(for: notLoaded.overall, isPaused: false) != "pause.circle.fill"
                && EffectiveState.statusLine(for: notLoaded, isPaused: false).hasPrefix("Not running"))

        let genericConflict = modelState(fixtures.first { $0.expected == .foreignConflict }!)
        var expectedMigration = genericConflict
        expectedMigration.foreignMovers = ["com.sicarii.desktop-autosort"]
        expectedMigration.effectiveMoverLabel = "com.sicarii.desktop-autosort"
        check("U16", "the known personal sorter renders as an expected migration, not a product warning",
              EffectiveState.menuBarSymbol(for: expectedMigration, isPaused: false) == "arrow.triangle.2.circlepath"
                && EffectiveState.statusLine(for: expectedMigration, isPaused: false).hasPrefix("Ready to migrate")
                && EffectiveState.conflictGuidance(for: expectedMigration).contains("verified migration"))
        check("U17", "an unknown same-root authority still renders as a warning",
              EffectiveState.menuBarSymbol(for: genericConflict, isPaused: false) == "exclamationmark.triangle"
                && EffectiveState.statusLine(for: genericConflict, isPaused: false).hasPrefix("Conflict")
                && EffectiveState.conflictGuidance(for: genericConflict).contains("another automation"))

        for state in [OverallState.foreignConflict, .degradedLedger, .ambiguous] {
            let report = modelState(fixtures.first { $0.expected == state }!)
            let controls = EffectiveState.nativeMenuControls(
                for: report,
                setupRequired: false,
                isPaused: false,
                hasUndoEligible: true,
                isBusy: false
            )
            check("U-controls-\(state.rawValue)",
                  "\(state.rawValue) exposes no mutating menu controls",
                  !controls.canTidyNow
                    && !controls.canPause
                    && !controls.canResume
                    && !controls.canUndo)
        }
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

    /// Public binary --effective-state --json under an isolated fixture world.
    private func publicState(_ f: Fixture, configBytes: Data) -> EffectiveStateReport? {
        try! configBytes.write(to: f.app.appendingPathComponent("config.json"))
        let stateFile = applyFixtureEnv(f)
        defer { clearFixtureEnv() }
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

    private func runDuplicateKeyGates() {
        func world(_ name: String) -> Fixture {
            Fixture(name: name, expected: .ambiguous,
                    agents: tempDir("agents"), states: [:],
                    target: tempDir("target"), app: tempDir("app"))
        }

        let a = tempDir("target-a")
        let b = tempDir("target-b")

        // D01: duplicate target keys, different values — public file/parser boundary.
        do {
            let f = world("dupe-target-diff")
            let raw = Data("{\"schema\":1,\"target\":\"\(a.path)\",\"target\":\"\(b.path)\"}".utf8)
            let report = publicState(f, configBytes: raw)
            check("D01", "duplicate target keys (different values) → invalid",
                  report?.overall == .ambiguous && report?.targetResolution == "invalid"
                    && report?.targetSource == TargetSource.nativeConfig.rawValue,
                  "got \(report?.overall.rawValue ?? "nil") res=\(report?.targetResolution ?? "nil") src=\(report?.targetSource ?? "nil") target=\(report?.watchedTarget ?? "nil")")
        }

        // D02: duplicate target keys, identical values still fail closed.
        do {
            let f = world("dupe-target-same")
            let raw = Data("{\"schema\":1,\"target\":\"\(a.path)\",\"target\":\"\(a.path)\"}".utf8)
            let report = publicState(f, configBytes: raw)
            check("D02", "duplicate target keys (identical values) → invalid",
                  report?.overall == .ambiguous && report?.targetResolution == "invalid",
                  "got \(report?.overall.rawValue ?? "nil") res=\(report?.targetResolution ?? "nil")")
        }

        // D03: duplicate schema keys.
        do {
            let f = world("dupe-schema")
            let raw = Data("{\"schema\":1,\"schema\":1,\"target\":\"\(a.path)\"}".utf8)
            let report = publicState(f, configBytes: raw)
            check("D03", "duplicate schema keys → invalid",
                  report?.overall == .ambiguous && report?.targetResolution == "invalid",
                  "got \(report?.overall.rawValue ?? "nil")")
        }

        // D04: escaped-equivalent duplicate key target / targ\u0065t.
        do {
            let f = world("dupe-escaped")
            let raw = Data("{\"schema\":1,\"target\":\"\(a.path)\",\"targ\\u0065t\":\"\(b.path)\"}".utf8)
            let report = publicState(f, configBytes: raw)
            check("D04", "escaped-equivalent duplicate target key → invalid",
                  report?.overall == .ambiguous && report?.targetResolution == "invalid",
                  "got \(report?.overall.rawValue ?? "nil") target=\(report?.watchedTarget ?? "nil")")
        }

        // D05: leading/trailing whitespace around a valid object is accepted.
        do {
            let f = world("ws-valid")
            let raw = Data("  \n{\"schema\":1,\"target\":\"\(a.path)\"}\n  ".utf8)
            let report = publicState(f, configBytes: raw)
            check("D05", "leading/trailing whitespace valid baseline",
                  report?.targetResolution == "resolved" && report?.targetSource == "nativeConfig"
                    && report?.watchedTarget == a.path,
                  "got \(report?.targetResolution ?? "nil") target=\(report?.watchedTarget ?? "nil")")
        }

        // D06: trailing non-whitespace after the object is rejected.
        do {
            let f = world("trailing-junk")
            let raw = Data("{\"schema\":1,\"target\":\"\(a.path)\"} true".utf8)
            let report = publicState(f, configBytes: raw)
            check("D06", "trailing non-whitespace rejected",
                  report?.overall == .ambiguous && report?.targetResolution == "invalid",
                  "got \(report?.overall.rawValue ?? "nil") res=\(report?.targetResolution ?? "nil")")
        }

        // D07: valid schema-1 baseline still resolves.
        do {
            let f = world("schema1-ok")
            let raw = Data("{\"schema\":1,\"target\":\"\(a.path)\"}".utf8)
            let report = publicState(f, configBytes: raw)
            check("D07", "valid schema-1 baseline still resolves",
                  report?.targetResolution == "resolved" && report?.targetSource == "nativeConfig"
                    && report?.watchedTarget == a.path,
                  "got \(report?.targetResolution ?? "nil") target=\(report?.watchedTarget ?? "nil")")
        }

        // D08: engine no-move witness for duplicate-key config.
        do {
            let f = world("engine-dupe")
            let raw = Data("{\"schema\":1,\"target\":\"\(a.path)\",\"target\":\"\(b.path)\"}".utf8)
            try! raw.write(to: f.app.appendingPathComponent("config.json"))
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
            check("D08", "engine refuses duplicate-key config (exit 3, no move)",
                  p.terminationStatus == 3 && stayed,
                  "exit=\(p.terminationStatus) stayed=\(stayed)")
        }
    }

    private func runPathParityGates() {
        let f = Fixture(name: "path-parity", expected: .pausedNotLoaded,
                        agents: tempDir("agents"), states: [:],
                        target: tempDir("target"), app: tempDir("app"))
        _ = applyFixtureEnv(f)
        defer { clearFixtureEnv() }
        let engine = DeskTidy()
        let report = EffectiveState.compute()
        let pathsApp = DeskTidyPaths.appDirectory().path
        let pathsLedger = DeskTidyPaths.ledgerURL().path
        let pathsCfg = DeskTidyPaths.nativeConfigURL().path
        let pathsReceipts = DeskTidyPaths.receiptsDirectory().path
        check("K01", "engine appDirectory equals DeskTidyPaths",
              engine.appDirectory.path == pathsApp, "engine=\(engine.appDirectory.path) paths=\(pathsApp)")
        check("K02", "EffectiveState appDirectory/ledgerPath equal DeskTidyPaths",
              report.appDirectory == pathsApp && report.ledgerPath == pathsLedger,
              "report.app=\(report.appDirectory) report.ledger=\(report.ledgerPath)")
        check("K03", "receipts/config/ledger share one app-support root",
              pathsLedger.hasPrefix(pathsReceipts) && pathsCfg.hasPrefix(pathsApp)
                && pathsCfg.hasSuffix("/config.json") && pathsLedger.hasSuffix("/ledger.jsonl"),
              "cfg=\(pathsCfg) ledger=\(pathsLedger)")
    }

    private func runLaunchdFixtureGates() {
        func world() -> Fixture {
            Fixture(name: "launchd-fixture", expected: .ambiguous,
                    agents: tempDir("agents"), states: [:],
                    target: tempDir("target"), app: tempDir("app"))
        }

        // L01: requested fixture path is absent → explicit ambiguous, not live/notLoaded.
        do {
            let f = world()
            setenv("DESKTIDY_AGENTS_DIR", f.agents.path, 1)
            setenv("DESKTIDY_TARGET_DIR", f.target.path, 1)
            setenv("DESKTIDY_APP_DIR", f.app.path, 1)
            setenv("DESKTIDY_LAUNCHD_STATE_FILE", f.agents.appendingPathComponent("missing-state.json").path, 1)
            defer { clearFixtureEnv() }
            let report = EffectiveState.compute()
            check("L01", "absent launchd fixture file → ambiguous",
                  report.overall == .ambiguous,
                  "got \(report.overall.rawValue): \(report.overallReason)")
        }

        // L02: malformed JSON fixture → ambiguous (public compute/binary path).
        do {
            let f = world()
            let bad = f.agents.appendingPathComponent("state.json")
            try? Data("[1,2,3]".utf8).write(to: bad)
            setenv("DESKTIDY_AGENTS_DIR", f.agents.path, 1)
            setenv("DESKTIDY_TARGET_DIR", f.target.path, 1)
            setenv("DESKTIDY_APP_DIR", f.app.path, 1)
            setenv("DESKTIDY_LAUNCHD_STATE_FILE", bad.path, 1)
            defer { clearFixtureEnv() }
            let report = EffectiveState.compute()
            check("L02", "malformed launchd fixture JSON → ambiguous",
                  report.overall == .ambiguous,
                  "got \(report.overall.rawValue): \(report.overallReason)")
        }

        // L03: invalid state value → ambiguous, never notLoaded.
        do {
            let f = world()
            let bad = f.agents.appendingPathComponent("state.json")
            try? Data(#"{"com.desktidy.sort":"exploded"}"#.utf8).write(to: bad)
            setenv("DESKTIDY_AGENTS_DIR", f.agents.path, 1)
            setenv("DESKTIDY_TARGET_DIR", f.target.path, 1)
            setenv("DESKTIDY_APP_DIR", f.app.path, 1)
            setenv("DESKTIDY_LAUNCHD_STATE_FILE", bad.path, 1)
            defer { clearFixtureEnv() }
            let report = EffectiveState.compute()
            check("L03", "invalid launchd fixture state value → ambiguous",
                  report.overall == .ambiguous,
                  "got \(report.overall.rawValue) agent=\(report.productAgentState): \(report.overallReason)")
        }

        // L04: valid fixture still hermetic (paused).
        do {
            let f = world()
            let report = modelState(f)
            check("L04", "valid empty launchd fixture remains pausedNotLoaded",
                  report.overall == .pausedNotLoaded,
                  "got \(report.overall.rawValue)")
        }

        // L05: public binary --effective-state --json on malformed fixture.
        do {
            let f = world()
            let bad = f.agents.appendingPathComponent("state.json")
            try? Data("not-json".utf8).write(to: bad)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binaryPath)
            p.arguments = ["--effective-state", "--json"]
            var env = ProcessInfo.processInfo.environment
            env["DESKTIDY_AGENTS_DIR"] = f.agents.path
            env["DESKTIDY_TARGET_DIR"] = f.target.path
            env["DESKTIDY_APP_DIR"] = f.app.path
            env["DESKTIDY_LAUNCHD_STATE_FILE"] = bad.path
            p.environment = env
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let report = try? JSONDecoder().decode(EffectiveStateReport.self, from: data)
            check("L05", "public binary reports ambiguous for malformed launchd fixture",
                  p.terminationStatus == 0 && report?.overall == .ambiguous,
                  "exit=\(p.terminationStatus) overall=\(report?.overall.rawValue ?? "nil")")
        }
    }

    private func runIdentityGates() {
        func world() -> Fixture {
            Fixture(name: "identity", expected: .pausedNotLoaded,
                    agents: tempDir("agents"), states: [:],
                    target: tempDir("target"), app: tempDir("app"))
        }

        // I01: expected sort label with expected program is self; no conflict.
        do {
            let f = world()
            writePlist(f.agents, label: ProductIdentity.sortLabel, watch: [f.target.path],
                       program: makeProgram("desktidy-sort"), targetEnv: f.target.path)
            var ff = f
            ff = Fixture(name: f.name, expected: .runningHealthy, agents: f.agents,
                         states: [ProductIdentity.sortLabel: "running"], target: f.target, app: f.app)
            let report = modelState(ff)
            check("I01", "expected sort identity remains self/runningHealthy",
                  report.overall == .runningHealthy && report.effectiveMoverLabel == ProductIdentity.sortLabel,
                  "got \(report.overall.rawValue) mover=\(report.effectiveMoverLabel ?? "nil")")
        }

        // I02: expected notify label is self (not foreign) even if sort is absent.
        do {
            let f = world()
            writePlist(f.agents, label: ProductIdentity.notifyLabel, watch: [f.target.path],
                       program: makeProgram("desktidy-notify"))
            var ff = f
            ff = Fixture(name: f.name, expected: .pausedNotLoaded, agents: f.agents,
                         states: [ProductIdentity.notifyLabel: "running"], target: f.target, app: f.app)
            let report = modelState(ff)
            check("I02", "expected notify identity is not a foreign conflict",
                  report.overall == .pausedNotLoaded && report.foreignMovers.isEmpty,
                  "got \(report.overall.rawValue) foreign=\(report.foreignMovers)")
        }

        // I03: foreign label remains foreign.
        do {
            let f = world()
            writePlist(f.agents, label: "com.example.other-mover", watch: [f.target.path],
                       program: makeProgram("other"))
            var ff = f
            ff = Fixture(name: f.name, expected: .foreignConflict, agents: f.agents,
                         states: ["com.example.other-mover": "running"], target: f.target, app: f.app)
            let report = modelState(ff)
            check("I03", "foreign label remains foreign",
                  report.overall == .foreignConflict && report.foreignMovers.contains("com.example.other-mover"),
                  "got \(report.overall.rawValue)")
        }

        // I04: stolen self-label with contradictory executable fails closed.
        do {
            let f = world()
            writePlist(f.agents, label: ProductIdentity.sortLabel, watch: [f.target.path],
                       program: makeProgram("not-desktidy"), targetEnv: f.target.path)
            var ff = f
            ff = Fixture(name: f.name, expected: .foreignConflict, agents: f.agents,
                         states: [ProductIdentity.sortLabel: "running"], target: f.target, app: f.app)
            let report = modelState(ff)
            check("I04", "self label + contradictory program fails closed",
                  report.overall == .foreignConflict || report.overall == .ambiguous,
                  "got \(report.overall.rawValue): \(report.overallReason)")
        }

        // I05: future/unloaded app-agent label is not silently trusted as self.
        do {
            let f = world()
            writePlist(f.agents, label: "com.desktidy.app.sort", watch: [f.target.path],
                       program: makeProgram("DeskTidy"))
            var ff = f
            ff = Fixture(name: f.name, expected: .foreignConflict, agents: f.agents,
                         states: ["com.desktidy.app.sort": "running"], target: f.target, app: f.app)
            let report = modelState(ff)
            check("I05", "future SMAppService label is not accepted as self",
                  report.overall == .foreignConflict && report.foreignMovers.contains("com.desktidy.app.sort"),
                  "got \(report.overall.rawValue) foreign=\(report.foreignMovers)")
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
