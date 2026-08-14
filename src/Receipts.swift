import CryptoKit
import Darwin
import Foundation

// ============================================================================
//  R0 — Canonical receipts and the single movement service.
//
//  Every movement attempt flows through MovementService.perform() and leaves
//  exactly one receipt in one ledger. The protocol is durable:
//
//      prepare (fsync'd intent file)  →  confined no-overwrite move  →
//      complete (fsync'd ledger append, intent removed)
//
//  If DeskTidy dies at any point, startupReconcile() replays pending intents
//  against filesystem truth and records `failed`, `recovered`, or
//  `indeterminate` — it never invents success.
//
//  The ledger is append-only JSONL with a SHA-256 hash chain. NOTE: the chain
//  is UNKEYED — it is integrity/identity evidence (detects truncation and
//  tampering of history), not author authentication. Anyone with write access
//  to the file could rebuild a consistent chain; the chain proves the ledger
//  is internally consistent, not who wrote it.
//
//  Receipts never contain file contents or secrets — names, paths relative to
//  the watched root, rule IDs, timestamps, sizes/mtimes, and outcome only.
// ============================================================================

/// Bounded, durable evidence used to prove that an Undo source is the exact
/// artifact which the original receipt moved. Regular-file bytes are hashed
/// only when the complete file is within the fixed limit; larger or
/// non-regular artifacts are deliberately not undo-eligible.
struct FileArtifactIdentity: Codable, Equatable {
    static let maximumDigestBytes: Int64 = 4 * 1024 * 1024

    let device: UInt64
    let inode: UInt64
    let fileType: UInt32
    let size: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
    let contentDigest: String?

    var isUndoVerifiable: Bool { contentDigest != nil }

    static func capture(at url: URL) -> FileArtifactIdentity? {
        var metadata = stat()
        guard Darwin.lstat(url.path, &metadata) == 0 else { return nil }

        let mode = UInt32(metadata.st_mode)
        let type = mode & UInt32(S_IFMT)
        guard type != UInt32(S_IFLNK) else { return nil }

        let size = Int64(metadata.st_size)
        let digest: String?
        if type == UInt32(S_IFREG), size >= 0, size <= maximumDigestBytes,
           let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            let hash = SHA256.hash(data: data)
            digest = hash.map { String(format: "%02x", $0) }.joined()
        } else {
            digest = nil
        }

        return FileArtifactIdentity(
            device: UInt64(metadata.st_dev),
            inode: UInt64(metadata.st_ino),
            fileType: type,
            size: size,
            modificationSeconds: Int64(metadata.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(metadata.st_mtimespec.tv_nsec),
            contentDigest: digest
        )
    }
}

struct Receipt: Codable {
    var schema: Int = 1
    var id: String
    var preparedAt: String
    var completedAt: String?
    var moverLabel: String
    var moverVersion: String
    var rootCanonical: String
    var sourceRel: String
    var plannedDestRel: String
    var finalDestRel: String?
    var ruleID: String
    var rulePolicyVersion: String
    var settleMTime: String
    var settleAgeSeconds: Double
    var collision: Bool?
    var outcome: String        // prepared | moved | failed | recovered | indeterminate
    var failureCode: String?
    var undoEligible: Bool
    var reversesReceiptID: String? = nil
    var artifactIdentity: FileArtifactIdentity? = nil
    var prevDigest: String
    var digest: String

    static let outcomes: Set<String> = ["prepared", "moved", "failed", "recovered", "indeterminate"]
}

enum ReceiptLedgerValidation {
    case valid([Receipt])
    case invalid(String)
}

enum MoveError: Error, CustomStringConvertible {
    case confinement(String)
    case prepareFailed(String)
    case moveFailed(String)

    var description: String {
        switch self {
        case .confinement(let s):   return "confinement: \(s)"
        case .prepareFailed(let s): return "prepare: \(s)"
        case .moveFailed(let s):    return "move: \(s)"
        }
    }
}

final class ReceiptLedger {
    let receiptsDir: URL
    let pendingDir: URL
    let ledgerURL: URL
    private let fm = FileManager.default
    private let appendLock = NSLock()
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Test-only post-move durability interruption. Production never assigns it.
    var testHookBeforeAppend: ((Receipt) throws -> Void)?

    init(appDirectory: URL) {
        receiptsDir = appDirectory.appendingPathComponent("receipts", isDirectory: true)
        pendingDir = receiptsDir.appendingPathComponent("pending", isDirectory: true)
        ledgerURL = receiptsDir.appendingPathComponent("ledger.jsonl")
    }

    func ensureDirectories() throws {
        try fm.createDirectory(at: pendingDir, withIntermediateDirectories: true)
    }

    func now() -> String { iso.string(from: Date()) }

    // -- digest chain --------------------------------------------------------
    private func canonicalPayload(_ r: Receipt) -> Data {
        var copy = r
        copy.digest = ""
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]     // deterministic serialization
        return (try? enc.encode(copy)) ?? Data()
    }

    func computeDigest(_ r: Receipt) -> String {
        let h = SHA256.hash(data: canonicalPayload(r))
        return h.map { String(format: "%02x", $0) }.joined()
    }

    func lastDigest() -> String {
        guard let data = fm.contents(atPath: ledgerURL.path),
              let text = String(data: data, encoding: .utf8) else { return "genesis" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard let last = lines.last,
              let rec = try? JSONDecoder().decode(Receipt.self, from: Data(last.utf8)) else {
            return lines.isEmpty ? "genesis" : "unparseable-tail"
        }
        return rec.digest
    }

    // -- durable writes ------------------------------------------------------
    /// Atomically persist a pending intent. Throws if it cannot be made durable.
    func writePending(_ r: Receipt) throws {
        try ensureDirectories()
        let url = pendingDir.appendingPathComponent("\(r.id).json")
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(r)
        try data.write(to: url, options: [.atomic])
        let fd = open(url.path, O_RDONLY)
        if fd >= 0 { fsync(fd); close(fd) }
    }

    func removePending(id: String) {
        try? fm.removeItem(at: pendingDir.appendingPathComponent("\(id).json"))
    }

    /// Append a completed receipt to the ledger with fsync. Throws on failure —
    /// callers must NOT report success if this throws.
    func append(_ receipt: Receipt) throws {
        appendLock.lock()
        defer { appendLock.unlock() }

        try testHookBeforeAppend?(receipt)
        try ensureDirectories()
        var r = receipt
        r.prevDigest = lastDigest()
        r.digest = computeDigest(r)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let line = try enc.encode(r) + Data("\n".utf8)
        if !fm.fileExists(atPath: ledgerURL.path) {
            guard fm.createFile(atPath: ledgerURL.path, contents: nil) else {
                throw MoveError.prepareFailed("cannot create ledger")
            }
        }
        let handle = try FileHandle(forWritingTo: ledgerURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    // -- the single history reader ------------------------------------------
    /// The one reader used by status/history (and future Undo/WhereDidItGo).
    func readAll() -> (receipts: [Receipt], malformedLines: Int) {
        guard let data = fm.contents(atPath: ledgerURL.path),
              let text = String(data: data, encoding: .utf8) else { return ([], 0) }
        var out: [Receipt] = []
        var bad = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let r = try? JSONDecoder().decode(Receipt.self, from: Data(line.utf8)),
               Receipt.outcomes.contains(r.outcome) {
                out.append(r)
            } else {
                bad += 1
            }
        }
        return (out, bad)
    }

    /// Verify the digest chain. Returns nil when intact, else a description.
    func verifyChain() -> String? {
        let (receipts, malformed) = readAll()
        if malformed > 0 { return "\(malformed) malformed line(s) in ledger" }
        var prev = "genesis"
        for (i, r) in receipts.enumerated() {
            if r.prevDigest != prev { return "chain break at record \(i): prevDigest mismatch" }
            if computeDigest(r) != r.digest { return "chain break at record \(i): digest mismatch" }
            prev = r.digest
        }
        return nil
    }
}

// ============================================================================
//  MovementService — the only code path that moves user files.
// ============================================================================

final class MovementService {
    let root: URL
    let rootCanonical: CanonicalPath
    let ledger: ReceiptLedger
    let moverVersion: String
    private let fm = FileManager.default
    private let log: (String) -> Void

    /// Test hook: runs after the pending intent is durably written and before
    /// the move syscall. Used by hostile controls to simulate races/crashes.
    /// Never set in production paths.
    var testHookAfterPrepare: ((Receipt) -> Void)?

    init(root: URL, ledger: ReceiptLedger, moverVersion: String, log: @escaping (String) -> Void) {
        self.root = root
        self.rootCanonical = AuthorityGuard.canonicalize(root.path)
        self.ledger = ledger
        self.moverVersion = moverVersion
        self.log = log
    }

    /// Root-relative path for receipts. The URL's PARENT is canonicalized
    /// (it always exists in our flows) so symlinked prefixes like macOS's
    /// /var → /private/var cannot silently degrade receipt paths to bare
    /// filenames — reconciliation depends on these being real relative paths.
    private func relative(_ url: URL) -> String {
        let parent = AuthorityGuard.canonicalize(url.deletingLastPathComponent().path).path
        let full = (parent.hasSuffix("/") ? parent : parent + "/") + url.lastPathComponent
        let rootP = rootCanonical.path.hasSuffix("/") ? rootCanonical.path : rootCanonical.path + "/"
        if full.hasPrefix(rootP) { return String(full.dropFirst(rootP.count)) }
        return url.lastPathComponent
    }

    // -- confinement ---------------------------------------------------------
    /// Source must be a direct, non-symlink child of the canonical root;
    /// destination directory must resolve inside the canonical root.
    private func validateConfinement(source: URL, destDir: URL) throws {
        let name = source.lastPathComponent
        if name == ".." || name == "." || name.contains("/") {
            throw MoveError.confinement("illegal source name")
        }
        // Source's parent must BE the canonical root (no traversal below root).
        let parentCanon = AuthorityGuard.canonicalize(source.deletingLastPathComponent().path)
        guard parentCanon == rootCanonical else {
            throw MoveError.confinement("source is not a direct child of the watched root")
        }
        // Source itself must not be a symlink (a link's target may escape the root).
        if let values = try? source.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            throw MoveError.confinement("source is a symlink")
        }
        // Destination directory (existing or to-be-created) must resolve inside root.
        var probe = destDir
        while !fm.fileExists(atPath: probe.path), probe.path.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        let destCanon = AuthorityGuard.canonicalize(probe.path)
        let rootPrefix = rootCanonical.path.hasSuffix("/") ? rootCanonical.path : rootCanonical.path + "/"
        guard destCanon == rootCanonical || destCanon.path.hasPrefix(rootPrefix) else {
            throw MoveError.confinement("destination resolves outside the watched root")
        }
        // If the destination dir itself exists, it must not be a symlink.
        if fm.fileExists(atPath: destDir.path),
           let values = try? destDir.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            throw MoveError.confinement("destination directory is a symlink")
        }
    }

    // -- unique naming (never overwrite) ------------------------------------
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
            let candidate = directory.appendingPathComponent(
                ext.isEmpty ? "\(stem) (dup \(stamp)\(ordinal))" : "\(stem) (dup \(stamp)\(ordinal)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
        }
    }

    // -- the movement protocol ----------------------------------------------
    /// Returns the completed receipt. A `moved` outcome means the file is at
    /// finalDestRel AND the completion was durably recorded.
    @discardableResult
    func perform(source: URL, category: Category, ruleID: String,
                 settleMTime: Date, settleAge: TimeInterval) -> Receipt? {
        let destDir = root.appendingPathComponent(category.folderName, isDirectory: true)

        // 1. Confinement — validated before anything is written anywhere.
        do {
            try validateConfinement(source: source, destDir: destDir)
        } catch {
            log("REFUSED \(source.lastPathComponent): \(error)")
            var r = skeleton(source: source, planned: destDir.appendingPathComponent(source.lastPathComponent),
                             ruleID: ruleID, settleMTime: settleMTime, settleAge: settleAge)
            r.outcome = "failed"
            r.failureCode = "confinement_rejected"
            r.completedAt = ledger.now()
            try? ledger.append(r)   // best-effort: refusals are recorded but never block the refusal itself
            return r
        }

        // 2. Plan + durably persist the prepared intent. No persistence → no move.
        do { try fm.createDirectory(at: destDir, withIntermediateDirectories: true) }
        catch {
            return recordFailure(source: source, destDir: destDir, ruleID: ruleID,
                                 settleMTime: settleMTime, settleAge: settleAge,
                                 code: "destination_unavailable", detail: error.localizedDescription)
        }
        var planned = uniqueDestination(in: destDir, for: source.lastPathComponent)
        var receipt = skeleton(source: source, planned: planned, ruleID: ruleID,
                               settleMTime: settleMTime, settleAge: settleAge)
        receipt.outcome = "prepared"
        do {
            try ledger.writePending(receipt)
        } catch {
            log("ERROR: cannot persist movement intent for \(source.lastPathComponent) — refusing to move: \(error.localizedDescription)")
            return nil   // no durable intent ⇒ no move, no invented receipt
        }

        testHookAfterPrepare?(receipt)

        // 3. One confined, no-overwrite move. If a race created our planned
        //    destination in the meantime, re-plan ONCE — never overwrite.
        if fm.fileExists(atPath: planned.path) {
            planned = uniqueDestination(in: destDir, for: source.lastPathComponent)
            receipt.plannedDestRel = relative(planned)
            receipt.collision = true
        }
        do {
            try moveWithoutOverwrite(source: source, to: planned)
        } catch {
            receipt.outcome = "failed"
            receipt.failureCode = "move_syscall_failed"
            receipt.completedAt = ledger.now()
            finalizeCompletion(&receipt)
            log("ERROR: could not move \(source.lastPathComponent): \(error.localizedDescription)")
            return receipt
        }

        // 4. Durably record completion. If this fails, the pending intent
        //    stays for restart reconciliation — we do NOT claim success.
        receipt.outcome = "moved"
        receipt.finalDestRel = relative(planned)
        receipt.collision = receipt.collision ?? (planned.lastPathComponent != source.lastPathComponent)
        receipt.undoEligible = receipt.artifactIdentity?.isUndoVerifiable == true
        receipt.completedAt = ledger.now()
        do {
            try ledger.append(receipt)
            ledger.removePending(id: receipt.id)
        } catch {
            log("ERROR: moved \(source.lastPathComponent) but completion receipt could not be written — will reconcile on next start")
            return receipt
        }
        log("\(planned.lastPathComponent) -> \(category.folderName)/")
        return receipt
    }

    /// Checks whether the receipt still names the exact confined artifact and
    /// its original root slot remains vacant. This has no movement side effect.
    func canUndo(receipt original: Receipt) -> Bool {
        validatedUndoPaths(for: original) != nil
    }

    /// Reverse one eligible movement through this same durable mover. Undo is
    /// intentionally an exact restoration, not a collision-renaming move:
    /// when the original root slot is occupied, it refuses without moving.
    @discardableResult
    func undo(receipt original: Receipt) -> Receipt? {
        guard let initial = validatedUndoPaths(for: original) else { return nil }

        let modification = (try? initial.source.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        var receipt = skeleton(source: initial.source, planned: initial.destination,
                               ruleID: "undo:\(original.id)",
                               settleMTime: modification, settleAge: 0)
        receipt.reversesReceiptID = original.id
        receipt.outcome = "prepared"
        receipt.undoEligible = false
        do {
            try ledger.writePending(receipt)
        } catch {
            log("ERROR: cannot persist undo intent for \(initial.source.lastPathComponent) — refusing to move")
            return nil
        }

        testHookAfterPrepare?(receipt)

        // Revalidate after durable prepare. A manual create/replace between
        // presentation and syscall must never cause an overwrite or reversal
        // of an intervening artifact.
        guard let live = validatedUndoPaths(for: original) else {
            receipt.outcome = "failed"
            receipt.failureCode = "undo_precondition_changed"
            receipt.completedAt = ledger.now()
            finalizeCompletion(&receipt)
            return receipt
        }
        do {
            try moveWithoutOverwrite(source: live.source, to: live.destination)
        } catch {
            receipt.outcome = "failed"
            receipt.failureCode = "undo_move_syscall_failed"
            receipt.completedAt = ledger.now()
            finalizeCompletion(&receipt)
            log("ERROR: could not undo \(live.source.lastPathComponent): \(error.localizedDescription)")
            return receipt
        }

        receipt.outcome = "moved"
        receipt.finalDestRel = relative(live.destination)
        receipt.completedAt = ledger.now()
        do {
            try ledger.append(receipt)
            ledger.removePending(id: receipt.id)
        } catch {
            // The file did move, but without a durable completion record it is
            // not a successful command. The pending intent is restart evidence.
            log("ERROR: undo moved \(live.source.lastPathComponent) but completion receipt could not be written — will reconcile on next start")
            return nil
        }
        log("\(live.source.lastPathComponent) -> watched root (undo)")
        return receipt
    }

    private func validatedUndoPaths(for original: Receipt) -> (source: URL, destination: URL)? {
        guard original.rootCanonical == rootCanonical.path,
              original.undoEligible,
              original.outcome == "moved" || original.outcome == "recovered",
              let finalRel = original.finalDestRel,
              let identity = original.artifactIdentity,
              identity.isUndoVerifiable,
              let source = undoSource(for: finalRel),
              let destinationName = directRootName(from: original.sourceRel) else {
            return nil
        }
        let destination = root.appendingPathComponent(destinationName)
        guard !fm.fileExists(atPath: destination.path),
              FileArtifactIdentity.capture(at: source) == identity else {
            return nil
        }
        return (source, destination)
    }

    private func directRootName(from relativePath: String) -> String? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 1,
              let name = components.first,
              !name.isEmpty,
              name != ".",
              name != ".." else {
            return nil
        }
        return String(name)
    }

    private func moveWithoutOverwrite(source: URL, to destination: URL) throws {
        guard Darwin.renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func undoSource(for relativePath: String) -> URL? {
        guard let source = confinedPath(for: relativePath, directRootChild: false),
              fm.fileExists(atPath: source.path) else {
            return nil
        }
        return source
    }

    private func reconciliationPaths(for receipt: Receipt) -> (source: URL, destination: URL)? {
        guard receipt.outcome == "prepared",
              receipt.rootCanonical == rootCanonical.path else {
            return nil
        }
        let undo = receipt.reversesReceiptID != nil
        guard let source = confinedPath(for: receipt.sourceRel, directRootChild: !undo),
              let destination = confinedPath(for: receipt.plannedDestRel, directRootChild: undo) else {
            return nil
        }
        return (source, destination)
    }

    private func confinedPath(for relativePath: String, directRootChild: Bool) -> URL? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        let expectedComponentCount = directRootChild ? 1 : 2
        guard components.count == expectedComponentCount,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }

        let path = root.appendingPathComponent(relativePath)
        let parent = path.deletingLastPathComponent()
        if directRootChild {
            guard AuthorityGuard.canonicalize(parent.path) == rootCanonical else { return nil }
        } else {
            guard AuthorityGuard.canonicalize(parent.deletingLastPathComponent().path) == rootCanonical,
                  !isSymbolicLink(parent) else {
                return nil
            }
        }
        guard !isSymbolicLink(path) else { return nil }
        return path
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        var metadata = stat()
        return Darwin.lstat(url.path, &metadata) == 0
            && (UInt32(metadata.st_mode) & UInt32(S_IFMT)) == UInt32(S_IFLNK)
    }

    private func skeleton(source: URL, planned: URL, ruleID: String,
                          settleMTime: Date, settleAge: TimeInterval) -> Receipt {
        Receipt(
            id: UUID().uuidString,
            preparedAt: ledger.now(),
            completedAt: nil,
            moverLabel: "com.desktidy.sort",
            moverVersion: moverVersion,
            rootCanonical: rootCanonical.path,
            sourceRel: relative(source),
            plannedDestRel: relative(planned),
            finalDestRel: nil,
            ruleID: ruleID,
            rulePolicyVersion: Config.routingPolicyVersion,
            settleMTime: ISO8601DateFormatter().string(from: settleMTime),
            settleAgeSeconds: settleAge,
            collision: nil,
            outcome: "prepared",
            failureCode: nil,
            undoEligible: false,
            artifactIdentity: FileArtifactIdentity.capture(at: source),
            prevDigest: "",
            digest: ""
        )
    }

    private func recordFailure(source: URL, destDir: URL, ruleID: String,
                               settleMTime: Date, settleAge: TimeInterval,
                               code: String, detail: String) -> Receipt {
        var r = skeleton(source: source, planned: destDir.appendingPathComponent(source.lastPathComponent),
                         ruleID: ruleID, settleMTime: settleMTime, settleAge: settleAge)
        r.outcome = "failed"
        r.failureCode = code
        r.completedAt = ledger.now()
        try? ledger.append(r)
        log("ERROR: \(code) for \(source.lastPathComponent): \(detail)")
        return r
    }

    private func finalizeCompletion(_ receipt: inout Receipt) {
        do {
            try ledger.append(receipt)
            ledger.removePending(id: receipt.id)
        } catch {
            log("ERROR: completion receipt write failed for \(receipt.sourceRel) — pending intent retained")
        }
    }

    // -- crash recovery ------------------------------------------------------
    /// Reconcile pending intents against filesystem truth. Deterministic:
    ///   source present + dest absent   → failed   (move never happened)
    ///   source absent  + dest present  → recovered (move happened, completion lost)
    ///   both present                   → failed   (move did not happen; dest is foreign)
    ///   neither present                → indeterminate (cannot prove anything)
    func startupReconcile() -> Int {
        let fmgr = FileManager.default
        guard let entries = try? fmgr.contentsOfDirectory(at: ledger.pendingDir, includingPropertiesForKeys: nil)
        else { return 0 }
        var handled = 0
        for entry in entries.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }) {
            guard let data = fmgr.contents(atPath: entry.path),
                  var r = try? JSONDecoder().decode(Receipt.self, from: data) else {
                // Malformed/truncated intent: quarantine + indeterminate marker.
                let quarantined = ledger.pendingDir.appendingPathComponent("corrupt-\(entry.lastPathComponent)")
                try? fmgr.moveItem(at: entry, to: quarantined)
                var marker = Receipt(
                    id: UUID().uuidString, preparedAt: ledger.now(), completedAt: ledger.now(),
                    moverLabel: "com.desktidy.sort", moverVersion: moverVersion,
                    rootCanonical: rootCanonical.path, sourceRel: "?", plannedDestRel: "?",
                    finalDestRel: nil, ruleID: "recovery", rulePolicyVersion: Config.routingPolicyVersion,
                    settleMTime: ledger.now(), settleAgeSeconds: 0, collision: nil,
                    outcome: "indeterminate", failureCode: "malformed_intent:\(entry.lastPathComponent)",
                    undoEligible: false, prevDigest: "", digest: "")
                marker.completedAt = ledger.now()
                try? ledger.append(marker)
                handled += 1
                continue
            }
            guard let paths = reconciliationPaths(for: r) else {
                r.outcome = "indeterminate"
                r.failureCode = "pending_path_rejected"
                r.completedAt = ledger.now()
                do {
                    try ledger.append(r)
                    ledger.removePending(id: r.id)
                    handled += 1
                } catch {
                    log("ERROR: could not reconcile pending intent \(r.id) — leaving for next start")
                }
                continue
            }

            let sourceExists = fmgr.fileExists(atPath: paths.source.path)
            let destinationExists = fmgr.fileExists(atPath: paths.destination.path)
            r.completedAt = ledger.now()
            switch (sourceExists, destinationExists) {
            case (true, false):
                r.outcome = "failed"
                r.failureCode = "crash_before_move"
            case (false, true):
                if let identity = FileArtifactIdentity.capture(at: paths.destination),
                   identity == r.artifactIdentity {
                    r.outcome = "recovered"
                    r.finalDestRel = r.plannedDestRel
                    r.undoEligible = r.reversesReceiptID == nil && identity.isUndoVerifiable
                } else {
                    r.outcome = "indeterminate"
                    r.failureCode = "recovered_identity_mismatch"
                }
            case (true, true):
                r.outcome = "failed"
                r.failureCode = "crash_before_move_dest_occupied"
            case (false, false):
                r.outcome = "indeterminate"
                r.failureCode = "state_unprovable"
            }
            do {
                try ledger.append(r)
                ledger.removePending(id: r.id)
                handled += 1
            } catch {
                log("ERROR: could not reconcile pending intent \(r.id) — leaving for next start")
            }
        }
        if handled > 0 { log("RECOVERY: reconciled \(handled) pending intent(s)") }
        return handled
    }
}
