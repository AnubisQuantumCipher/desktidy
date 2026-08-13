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

// Where a file belongs. Folder names come from Config (user-editable).
enum Category: CaseIterable {
    case inbox, documents, images, screenshots, videos, audio, archives, code, folders

    var folderName: String {
        switch self {
        case .inbox:       return Config.folderInbox
        case .documents:   return Config.folderDocuments
        case .images:      return Config.folderImages
        case .screenshots: return Config.folderScreenshots
        case .videos:      return Config.folderVideos
        case .audio:       return Config.folderAudio
        case .archives:    return Config.folderArchives
        case .code:        return Config.folderCode
        case .folders:     return Config.folderFolders
        }
    }
}

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

    // The target's own type-folders are skipped when scanning the root.
    var reservedRootNames: Set<String> { Set(Category.allCases.map { $0.folderName }) }

    init() {
        let env = ProcessInfo.processInfo.environment
        home = fm.homeDirectoryForCurrentUser

        if let t = env["DESKTIDY_TARGET_DIR"], !t.isEmpty {
            target = URL(fileURLWithPath: (t as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            target = home.appendingPathComponent(Config.targetDirName, isDirectory: true)
        }
        if let a = env["DESKTIDY_APP_DIR"], !a.isEmpty {
            appDirectory = URL(fileURLWithPath: (a as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            appDirectory = home.appendingPathComponent("Library/Application Support/DeskTidy", isDirectory: true)
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
        if arguments.contains("--model-smoke") {
            #if canImport(FoundationModels)
            if #available(macOS 26, *) { return await modelSmokeTest() ? 0 : 1 }
            #endif
            print("Smart triage is not built into this copy (needs macOS 26+ at build time).")
            return 0
        }

        guard acquireLock() else { return 0 }   // another instance is already running
        defer { releaseLock() }

        do {
            try ensureAccess()
        } catch {
            log("ERROR: cannot access the target folder (Full Disk Access may not be granted): \(error.localizedDescription)")
            return 0
        }

        let moved = deterministicSweep()

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
    func deterministicSweep() -> Int {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(
                at: target, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            log("ERROR: cannot list target folder: \(error.localizedDescription)")
            return 0
        }

        var moved = 0
        for item in items {
            let name = item.lastPathComponent
            guard !reservedRootNames.contains(name) else { continue }
            guard !shouldSkipPartial(name) else { continue }
            do {
                let values = try item.resourceValues(forKeys: keys)
                let modified = values.contentModificationDate ?? Date()
                guard Date().timeIntervalSince(modified) >= settleSeconds else { continue }
                if move(item, to: classify(name: name, isDirectory: values.isDirectory == true)) { moved += 1 }
            } catch {
                log("ERROR: could not inspect \(safeLog(name)): \(error.localizedDescription)")
            }
        }
        if moved > 0 { log("--- pass complete: \(moved) item(s) filed ---") }
        return moved
    }

    // -- routing ------------------------------------------------------------
    func classify(name: String, isDirectory: Bool) -> Category {
        if isDirectory { return .folders }
        let lower = name.lowercased()
        if lower.hasPrefix("screenshot ") || lower.hasPrefix("screen shot ") { return .screenshots }
        if lower.hasPrefix("screen recording ") { return .videos }

        let ext = (name as NSString).pathExtension.lowercased()
        if Config.imageExts.contains(ext)    { return .images }
        if Config.videoExts.contains(ext)    { return .videos }
        if Config.audioExts.contains(ext)    { return .audio }
        if Config.archiveExts.contains(ext)  { return .archives }
        if Config.codeExts.contains(ext)     { return .code }
        if Config.documentExts.contains(ext) { return .documents }
        return .inbox
    }

    func shouldSkipPartial(_ name: String) -> Bool {
        let lower = name.lowercased()
        return [".crdownload", ".part", ".download", ".partial", ".tmp"].contains { lower.hasSuffix($0) }
    }

    // -- the move (never overwrites) ---------------------------------------
    func move(_ source: URL, to category: Category) -> Bool {
        let directory = target.appendingPathComponent(category.folderName, isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let dest = uniqueDestination(in: directory, for: source.lastPathComponent)
            try fm.moveItem(at: source, to: dest)
            log("\(safeLog(source.lastPathComponent)) -> \(category.folderName)/")
            return true
        } catch {
            log("ERROR: could not move \(safeLog(source.lastPathComponent)): \(error.localizedDescription)")
            return false
        }
    }

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
            let actual = classify(name: name, isDirectory: isDir)
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

enum DeskTidyVersion { static let string = "v1.0.0" }

@main
struct DeskTidyMain {
    static func main() async {
        let app = DeskTidy()
        let code = await app.run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}
