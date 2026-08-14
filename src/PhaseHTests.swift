import Foundation

// ============================================================================
// Phase H — ledger-derived history and Where Did It Go contracts.
// Every case operates only in a fresh /private/tmp fixture; no test observes a
// live Desktop, service, or user receipt ledger.
// ============================================================================

final class PhaseHTests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private struct Fixture {
        let sandbox: URL
        let root: URL
        let app: URL
        let core: CanonicalApplicationCore
    }

    private func check(_ id: String, _ description: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("PASS  \(id)  \(description)")
            pass += 1
        } else {
            print("FAIL  \(id)  \(description)\(detail.isEmpty ? "" : " — \(detail)")")
            fail += 1
        }
    }

    private func temporaryDirectory(_ label: String) -> URL {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("desktidy-phaseh-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture() -> Fixture {
        let sandbox = temporaryDirectory("fixture")
        let root = sandbox.appendingPathComponent("watched", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        try! fm.createDirectory(at: app, withIntermediateDirectories: true)
        let env = ["DESKTIDY_APP_DIR": app.path, "DESKTIDY_TARGET_DIR": root.path]
        let movement = MovementService(
            root: root,
            ledger: ReceiptLedger(appDirectory: app),
            moverVersion: DeskTidyVersion.string,
            log: { _ in }
        )
        let core = CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: app.appendingPathComponent("config.json"),
            targetResolver: { TargetResolver.resolve(env: env, home: sandbox, fm: self.fm) },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: { .fixture("phase-h") },
            authorize: { _ in .allowed }
        )
        return Fixture(sandbox: sandbox, root: root, app: app, core: core)
    }

    @discardableResult
    private func settledFile(in root: URL, named name: String, contents: String = "fixture") -> URL {
        let url = root.appendingPathComponent(name)
        fm.createFile(atPath: url.path, contents: Data(contents.utf8))
        try! fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    private func move(_ name: String, contents: String = "fixture", in fixture: Fixture) -> Receipt {
        _ = settledFile(in: fixture.root, named: name, contents: contents)
        guard let receipt = fixture.core.tidyNow().moved.last else { fatalError("movement fixture did not move \(name)") }
        return receipt
    }

    func runAll() -> Bool {
        runEmptyAndBoundedHistoryContract()
        runMovementCollisionAndUndoContract()
        runWhereDidItGoLivenessContract()
        runDuplicateAndUnicodeQueryContract()
        runOlderReceiptUndoContract()

        runTamperAndNoCacheContract()
        print("PHASE H GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func runEmptyAndBoundedHistoryContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let empty = f.core.history(page: 0, limit: CanonicalHistoryQuery.maximumPageSize)
        let template = move("bounded.pdf", in: f)
        for index in 0..<(CanonicalHistoryQuery.maximumPageSize + 3) {
            var duplicate = template
            duplicate.id = "bounded-\(index)"
            duplicate.preparedAt = "2026-08-14T00:00:\(String(format: "%02d", index % 60)).000Z"
            duplicate.completedAt = duplicate.preparedAt
            try! f.core.movement.ledger.append(duplicate)
        }
        let bounded = f.core.history(page: 0, limit: CanonicalHistoryQuery.maximumPageSize + 1)
        check(
            "H01",
            "empty history is valid and later history pagination is capped",
            empty.integrity == .valid && empty.entries.isEmpty
                && bounded.integrity == .valid
                && bounded.entries.count == CanonicalHistoryQuery.maximumPageSize
                && bounded.hasMore,
            "empty=\(empty.entries.count), bounded=\(bounded.entries.count), hasMore=\(bounded.hasMore)"
        )
    }

    private func runMovementCollisionAndUndoContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let first = move("invoice.pdf", contents: "first", in: f)
        let second = move("invoice.pdf", contents: "second", in: f)
        let undo = f.core.undo(receiptID: first.id)
        let history = f.core.history(page: 0, limit: 20)
        let firstEntry = history.entries.first { $0.receipt.id == first.id }
        let secondEntry = history.entries.first { $0.receipt.id == second.id }
        check(
            "H02",
            "ledger history reconstructs collision and undo entries with display metadata",
            firstEntry?.originalName == "invoice.pdf"
                && firstEntry?.finalName == "invoice.pdf"
                && secondEntry?.finalName != "invoice.pdf"
                && secondEntry?.category == "Documents"
                && firstEntry?.timestamp != nil
                && firstEntry?.mover == "com.desktidy.sort"
                && undo.outcome == .completed
                && firstEntry?.undoEligible == false,
            "first=\(String(describing: firstEntry)), second=\(String(describing: secondEntry)), undo=\(undo.outcome)"
        )
    }

    private func runWhereDidItGoLivenessContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let receipt = move("live.pdf", contents: "original", in: f)
        let destination = f.root.appendingPathComponent(receipt.finalDestRel!)
        let live = f.core.whereDidItGoResult(named: "live.pdf")
        let relocated = f.sandbox.appendingPathComponent("manual-live.pdf")
        try! fm.moveItem(at: destination, to: relocated)
        let missing = f.core.whereDidItGoResult(named: "live.pdf")
        fm.createFile(atPath: destination.path, contents: Data("replacement".utf8))
        let changed = f.core.whereDidItGoResult(named: "live.pdf")
        try! fm.removeItem(at: destination)
        let deleted = f.core.whereDidItGoResult(named: "live.pdf")
        check(
            "H03",
            "Where Did It Go checks the current confined destination identity instead of trusting a receipt",
            live.status == .moved
                && missing.status == .movedElsewhere
                && changed.status == .changed
                && deleted.status == .movedElsewhere
                && live.destination == receipt.finalDestRel,
            "live=\(live.status), missing=\(missing.status), changed=\(changed.status), deleted=\(deleted.status)"
        )
    }

    private func runDuplicateAndUnicodeQueryContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let first = move("Ångström.PDF", contents: "first", in: f)
        let second = move("Ångström.PDF", contents: "second", in: f)
        let exact = f.core.whereDidItGoResult(named: "åNGSTRÖM.pdf")
        let unsafe = f.core.whereDidItGoResult(named: "Documents/Ångström.PDF")
        check(
            "H04",
            "duplicate names select the newest matching valid receipt and Unicode case folding is component-safe",
            exact.status == .moved
                && exact.receipt?.id == second.id
                && exact.receipt?.id != first.id
                && unsafe.status == .invalidQuery,
            "exact=\(exact.status), id=\(exact.receipt?.id ?? "nil"), unsafe=\(unsafe.status)"
        )
    }

    private func runOlderReceiptUndoContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let first = move("oldest.pdf", contents: "first", in: f)
        for index in 0...CanonicalHistoryQuery.maximumPageSize {
            _ = move("later-\(index).pdf", contents: "\(index)", in: f)
        }
        let undo = f.core.undo(receiptID: first.id)
        check(
            "H05",
            "receipt-ID undo searches the full validated bounded ledger rather than the visible history page",
            undo.outcome == .completed,
            "undo=\(undo.outcome)"
        )
    }

    private func runTamperAndNoCacheContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        _ = move("tamper.pdf", in: f)
        let before = f.core.history(page: 0, limit: 10)
        let ledgerURL = f.core.movement.ledger.ledgerURL
        let appended = try! FileHandle(forWritingTo: ledgerURL)
        try! appended.seekToEnd()
        try! appended.write(contentsOf: Data("{not-a-receipt}\n".utf8))
        try! appended.close()
        let after = f.core.history(page: 0, limit: 10)
        let query = f.core.whereDidItGoResult(named: "tamper.pdf")
        check(
            "H06",
            "tampering visibly degrades fresh history reads and prevents stale cached search results",
            before.integrity == .valid
                && after.integrity != .valid
                && after.entries.isEmpty
                && query.status == .ledgerUnavailable,
            "before=\(before.integrity), after=\(after.integrity), query=\(query.status)"
        )
    }
}
