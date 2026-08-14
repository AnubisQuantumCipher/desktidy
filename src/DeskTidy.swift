import Foundation

#if canImport(FoundationModels)
import FoundationModels
import PDFKit
#endif

// ============================================================================
//  DeskTidy — automatic Desktop organizer for macOS.
//
//  Deterministic core (works on any recent macOS): watches a folder and files
//  loose items into type folders, safely. Optional on-device AI triage (macOS
//  26+) only *suggests* homes for leftovers — it never moves anything.
//
//  Behavior you can rely on:
//    • never deletes anything (moves only; name clashes are de-duplicated)
//    • waits `settleSeconds` before touching a file (no grabbing mid-download)
//    • single-instance lock (the watcher and a manual run can't collide)
//    • the target folder's own type-folders are never re-sorted
//    • every move is logged; nothing is hidden
// ============================================================================

// Plain records used by the optional AI pass (safe to keep unconditionally).
struct CachedDecision: Codable, Equatable {
    let fingerprint: String
    let destination: String
    let certainty: String
    let reason: String
}

struct Suggestion: Equatable {
    let name: String
    let destination: String
    let certainty: String
    let reason: String
}

final class DeskTidy {
    let fm = FileManager.default
    let home: URL
    let target: URL
    let appDirectory: URL
    let inbox: URL
    let logURL: URL
    let lockURL: URL
    let smartStampURL: URL
    let smartCacheURL: URL
    let suggestionsURL: URL

    let settleSeconds = Config.settleSeconds
    let smartIntervalSeconds = Config.smartIntervalSeconds
    let smartItemLimit = 12
    let previewByteLimit = 24_000
    let previewCharacterLimit = 6_000
    var lockFD: Int32 = -1

    #if canImport(FoundationModels)
    let smartCompiledIn = true
    #else
    let smartCompiledIn = false
    #endif

    let targetResolution: TargetResolution

    lazy var ledger = ReceiptLedger(appDirectory: appDirectory)
    lazy var movement = MovementService(root: target, ledger: ledger,
                                        moverVersion: DeskTidyVersion.string,
                                        log: { [weak self] in self?.log($0) })

    // The target's own type-folders are skipped when scanning the root.
    var reservedRootNames: Set<String> { Set(Category.allCases.map { $0.folderName }) }

    init() {
        home = fm.homeDirectoryForCurrentUser
        appDirectory = DeskTidyPaths.appDirectory()
        targetResolution = TargetResolver.resolve()
        switch targetResolution {
        case .resolved(let path, _, _):
            target = URL(fileURLWithPath: path, isDirectory: true)
        case .invalid:
            // Not a movement target. run() refuses before any access/sweep.
            // Keep the URL off ~/Desktop so a forgotten check cannot sort live.
            target = appDirectory.appendingPathComponent(".unresolved-target", isDirectory: true)
        }
        inbox = target.appendingPathComponent(Config.folderInbox, isDirectory: true)
        logURL = appDirectory.appendingPathComponent("desktidy.log")
        lockURL = appDirectory.appendingPathComponent("desktidy.lock")
        smartStampURL = appDirectory.appendingPathComponent("smart-triage.last")
        smartCacheURL = appDirectory.appendingPathComponent("smart-triage-cache.json")
        suggestionsURL = inbox.appendingPathComponent("SMART_TRIAGE_SUGGESTIONS.md")
    }

    func run(arguments: [String]) async -> Int32 {
        do {
            try fm.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        } catch {
            fputs("DeskTidy: cannot create application directory: \(error)\n", stderr)
            return 1
        }

        if arguments.contains("--health")    { printHealth();               return 0 }
        if arguments.contains("--self-test") { return selfTest() ? 0 : 1 }
        if arguments.contains("--check-access") {   // read-only probe: never moves anything
            do { try probeAccess(); print("access OK: \(target.path)"); return 0 }
            catch { print("NO ACCESS: \(target.path) — \(error.localizedDescription)"); return 1 }
        }
        if arguments.contains("--authority-diagnose") || arguments.contains("--authority-check") {
            return AuthorityGuard().diagnose(rootPath: target.path, json: arguments.contains("--json"))
        }
        if arguments.contains("--effective-state") {
            let report = EffectiveState.compute()
            if arguments.contains("--json") {
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let d = try? enc.encode(report) { print(String(decoding: d, as: UTF8.self)) }
            } else {
                print(EffectiveState.diagnostic(report))
            }
            return 0
        }
        if arguments.contains("--state-test") {
            return R1ATests(binaryPath: CommandLine.arguments[0]).runAll() ? 0 : 1
        }
        if arguments.contains("--phase1a-test") {
            return Phase1ATests().runAll() ? 0 : 1
        }
        if arguments.contains("--phase1a1-test") {
            return Phase1A1Tests().runAll() ? 0 : 1
        }
        if arguments.contains("--phase1b-test") {
            return Phase1BTests().runAll() ? 0 : 1
        }
        if arguments.contains("--phase2-test") {
            return Phase2Tests().runAll() ? 0 : 1
        }
        if arguments.contains("--phasec-test") {
            return PhaseCTests().runAll() ? 0 : 1
        }
        if arguments.contains("--phased-test") {
            return PhaseDTests().runAll() ? 0 : 1
        }
        if arguments.contains("--phasee-test") {
            return PhaseETests().runAll() ? 0 : 1
        }
        if arguments.contains("--phasef-test") {
            return PhaseFTests().runAll() ? 0 : 1
        }
        if arguments.contains("--phaseg-test") {
            return PhaseGTests().runAll() ? 0 : 1
        }
        if arguments.contains("--phaseh-test") {
            return PhaseHTests().runAll() ? 0 : 1
        }
        if arguments.contains("--phasei-test") {
            return PhaseITests().runAll() ? 0 : 1
        }
        if arguments.contains("--phasej-test") {
            return PhaseJTests().runAll() ? 0 : 1
        }
        if arguments.contains("--history") {
            return printHistory(arguments: arguments)
        }
        if arguments.contains("--verify-ledger") {
            if let problem = ledger.verifyChain() { print("LEDGER FAIL: \(problem)"); return 1 }
            let (rs, _) = ledger.readAll()
            print("LEDGER OK: \(rs.count) receipt(s), digest chain intact")
            return 0
        }
        if arguments.contains("--r0-test") {
            return await R0Tests(engineVersion: DeskTidyVersion.string).runAll() ? 0 : 1
        }
        if arguments.contains("--model-smoke") {
            #if canImport(FoundationModels)
            if #available(macOS 26, *) { return await modelSmokeTest() ? 0 : 1 }
            #endif
            print("Smart triage is not built into this copy (needs macOS 26+ at build time).")
            return 0
        }

        if case .invalid(let reason, let source, _) = targetResolution {
            fputs("DeskTidy: target resolution failed (\(source.rawValue): \(reason)) — refusing movement\n", stderr)
            return 3
        }

        guard acquireLock() else { return 0 }   // another instance is already running
        defer { releaseLock() }

        do {
            try ensureAccess()
        } catch {
            log("ERROR: cannot access the target folder (Full Disk Access may not be granted): \(error.localizedDescription)")
            return 0
        }

        // R0 authority gate: refuse movement when another authority shares the
        // root (or authority cannot be proven). Runs on EVERY movement start —
        // launchd wake, sort-now, and any future entry point all pass through here.
        switch AuthorityGuard().evaluate(rootPath: target.path) {
        case .sole, .soleWithStale:
            break
        case .conflict(let movers):
            let labels = movers.map { $0.label }.joined(separator: ", ")
            log("AUTHORITY CONFLICT: refusing to move — another authority watches this root: \(labels)")
            fputs("DeskTidy: authority conflict (\(labels)) — run --authority-diagnose\n", stderr)
            return 2
        case .ambiguous(let reason, _):
            log("AUTHORITY AMBIGUOUS: failing closed — \(reason)")
            fputs("DeskTidy: movement authority ambiguous — failing closed. \(reason)\n", stderr)
            return 3
        }

        // R0 crash recovery: reconcile any interrupted movement intents
        // against filesystem truth before making new decisions.
        _ = movement.startupReconcile()

        var (moved, skippedFresh) = deterministicSweep()
        // Files dropped moments ago get skipped by the settle window. Instead of
        // leaving them for the next launchd interval (worst case ~75s of visible
        // clutter), wait out the window once and sweep again — typical time from
        // drop to filed is then ~settleSeconds + a moment.
        if skippedFresh > 0 {
            try? await Task.sleep(nanoseconds: UInt64((settleSeconds + 1) * 1_000_000_000))
            let second = deterministicSweep()
            moved += second.moved
        }

        let forceSmart = arguments.contains("--smart-now")
        #if canImport(FoundationModels)
        if #available(macOS 26, *), Config.enableSmartTriage {
            if forceSmart || smartTriageIsDue() {
                markSmartTriageAttempt()
                await writeSmartSuggestions()
            }
        }
        #endif

        if arguments.contains("--verbose") || forceSmart {
            print("DeskTidy: \(moved) item(s) filed.")
            print("Target: \(target.path)")
            print("Log: \(logURL.path)")
        }
        return 0
    }

    // -- single-instance lock ----------------------------------------------
    func acquireLock() -> Bool {
        lockFD = open(lockURL.path, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard lockFD >= 0 else { log("ERROR: unable to open single-instance lock"); return false }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { close(lockFD); lockFD = -1; return false }
        return true
    }
    func releaseLock() {
        guard lockFD >= 0 else { return }
        _ = flock(lockFD, LOCK_UN); close(lockFD); lockFD = -1
    }

    // -- access probe (this is what fails without Full Disk Access) --------
    // Read-only: verifies the target exists and is listable. Moves nothing.
    func probeAccess() throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }
        _ = try fm.contentsOfDirectory(at: target, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    }

    func ensureAccess() throws {
        try probeAccess()
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true)   // needed for suggestions
    }

    // -- the deterministic pass --------------------------------------------
    // Returns how many items were filed and how many were skipped only because
    // they were too fresh (still inside the settle window).
    func deterministicSweep() -> (moved: Int, skippedFresh: Int) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(
                at: target, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            log("ERROR: cannot list target folder: \(error.localizedDescription)")
            return (0, 0)
        }

        var moved = 0
        var skippedFresh = 0
        for item in items {
            let name = item.lastPathComponent
            guard !reservedRootNames.contains(name) else { continue }
            guard !shouldSkipPartial(name) else { continue }
            do {
                let values = try item.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    log("SKIP symlink at root: \(safeLog(name))")
                    continue
                }
                let modified = values.contentModificationDate ?? Date()
                let age = Date().timeIntervalSince(modified)
                guard age >= settleSeconds else { skippedFresh += 1; continue }
                let route = classify(name: name, isDirectory: values.isDirectory == true)
                let receipt = movement.perform(source: item, category: route.category,
                                               ruleID: route.ruleID,
                                               settleMTime: modified, settleAge: age)
                if receipt?.outcome == "moved" { moved += 1 }
            } catch {
                log("ERROR: could not inspect \(safeLog(name)): \(error.localizedDescription)")
            }
        }
        if moved > 0 { log("--- pass complete: \(moved) item(s) filed ---") }
        return (moved, skippedFresh)
    }

    // -- routing ------------------------------------------------------------
    // Returns the destination and a stable rule ID recorded in receipts.
    func classify(name: String, isDirectory: Bool) -> (category: Category, ruleID: String) {
        if isDirectory { return (.folders, "dir") }
        let lower = name.lowercased()
        if lower.hasPrefix("screenshot ") || lower.hasPrefix("screen shot ") { return (.screenshots, "prefix:screenshot") }
        if lower.hasPrefix("screen recording ") { return (.videos, "prefix:screen-recording") }

        let ext = (name as NSString).pathExtension.lowercased()
        if Config.imageExts.contains(ext)    { return (.images,    "ext:\(ext)") }
        if Config.videoExts.contains(ext)    { return (.videos,    "ext:\(ext)") }
        if Config.audioExts.contains(ext)    { return (.audio,     "ext:\(ext)") }
        if Config.archiveExts.contains(ext)  { return (.archives,  "ext:\(ext)") }
        if Config.codeExts.contains(ext)     { return (.code,      "ext:\(ext)") }
        if Config.documentExts.contains(ext) { return (.documents, "ext:\(ext)") }
        return (.inbox, "fallback:inbox")
    }

    func shouldSkipPartial(_ name: String) -> Bool {
        let lower = name.lowercased()
        return [".crdownload", ".part", ".download", ".partial", ".tmp"].contains { lower.hasSuffix($0) }
    }

    // NOTE (R0): the movement itself lives in MovementService (src/Receipts.swift)
    // — the single code path allowed to move user files. uniqueDestination stays
    // here only as the naming oracle exercised by --self-test.
    func uniqueDestination(in directory: URL, for fileName: String) -> URL {
        let direct = directory.appendingPathComponent(fileName)
        guard fm.fileExists(atPath: direct.path) else { return direct }
        let sourceURL = URL(fileURLWithPath: fileName)
        let ext = sourceURL.pathExtension
        let stem = ext.isEmpty ? fileName : sourceURL.deletingPathExtension().lastPathComponent
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        var counter = 1
        while true {
            let ordinal = counter == 1 ? "" : "-\(counter)"
            let candidateName = ext.isEmpty ? "\(stem) (dup \(stamp)\(ordinal))" : "\(stem) (dup \(stamp)\(ordinal)).\(ext)"
            let candidate = directory.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    // -- logging ------------------------------------------------------------
    func singleLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
    func safeLog(_ value: String) -> String { singleLine(value) }

    func log(_ message: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date()))\t\(safeLog(message))\n"
        if !fm.fileExists(atPath: logURL.path) { _ = fm.createFile(atPath: logURL.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        do { try handle.seekToEnd(); try handle.write(contentsOf: Data(line.utf8)); try handle.close() }
        catch { try? handle.close() }
    }

    func printHealth() {
        print("DeskTidy \(DeskTidyVersion.string)")
        print("Target: \(target.path)")
        print("Mode: deterministic sorting" + (smartCompiledIn ? " + optional on-device AI triage" : " (AI triage not built in)"))
        print("Settle: \(Int(settleSeconds))s   Smart cadence: \(Int(smartIntervalSeconds))s")
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            print("Apple on-device model: \(String(describing: SystemLanguageModel(useCase: .general).availability))")
        }
        #endif
        print("Network use: none by this program")
    }

    // -- self-test (no side effects on the target) -------------------------
    func selfTest() -> Bool {
        let cases: [(String, Bool, Category)] = [
            ("Screenshot 2026-08-13 at 7.00.00 AM.png", false, .screenshots),
            ("screen shot sample.JPG",                  false, .screenshots),
            ("Screen Recording 2026-08-13.mov",         false, .videos),
            ("holiday.JPG",                             false, .images),
            ("clip.mp4",                                false, .videos),
            ("song.flac",                               false, .audio),
            ("backup.zip",                              false, .archives),
            ("installer.dmg",                           false, .archives),
            ("report.pdf",                              false, .documents),
            ("notes.MD",                                false, .documents),
            ("main.rs",                                 false, .code),
            ("config.json",                             false, .code),
            ("mystery.xyz",                             false, .inbox),
            ("no-extension",                            false, .inbox),
            ("some-dropped-folder",                     true,  .folders)
        ]
        var failures = 0
        for (name, isDir, expected) in cases {
            let actual = classify(name: name, isDirectory: isDir).category
            if actual != expected {
                fputs("FAIL classify \(name): \(actual.folderName), expected \(expected.folderName)\n", stderr); failures += 1
            }
        }
        if !shouldSkipPartial("download.CRDOWNLOAD") || shouldSkipPartial("ready.txt") {
            fputs("FAIL partial-download guard\n", stderr); failures += 1
        }
        // collision de-dup must preserve the extension and not overwrite
        let scratch = fm.temporaryDirectory.appendingPathComponent("DeskTidy-selftest-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
            _ = fm.createFile(atPath: scratch.appendingPathComponent("report.pdf").path, contents: Data())
            let collision = uniqueDestination(in: scratch, for: "report.pdf")
            if collision.pathExtension != "pdf" || !collision.deletingPathExtension().lastPathComponent.contains("(dup ") {
                fputs("FAIL collision naming\n", stderr); failures += 1
            }
            try fm.removeItem(at: scratch)
        } catch { fputs("FAIL collision setup: \(error)\n", stderr); failures += 1 }

        if failures == 0 { print("PASS: \(cases.count + 2) deterministic safety checks"); return true }
        return false
    }
}

extension DeskTidy {
    // The single history reader (ReceiptLedger.readAll) drives status/history.
    func printHistory(arguments: [String]) -> Int32 {
        let (receipts, malformed) = ledger.readAll()
        var count = 10
        if let idx = arguments.firstIndex(of: "--history"), idx + 1 < arguments.count,
           let n = Int(arguments[idx + 1]) { count = max(1, n) }
        let recent = receipts.suffix(count)
        if arguments.contains("--json") {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let d = try? enc.encode(Array(recent)) { print(String(decoding: d, as: UTF8.self)) }
        } else {
            if recent.isEmpty { print("No movement receipts yet.") }
            for r in recent {
                let dest = r.finalDestRel ?? r.plannedDestRel
                print("\(r.completedAt ?? r.preparedAt)  [\(r.outcome)]  \(r.sourceRel) -> \(dest)  rule=\(r.ruleID)\(r.failureCode.map { "  code=\($0)" } ?? "")")
            }
            if malformed > 0 { print("WARNING: \(malformed) malformed ledger line(s) — run --verify-ledger") }
        }
        return 0
    }
}


@main
struct DeskTidyMain {
    static func main() async {
        let app = DeskTidy()
        let code = await app.run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}
