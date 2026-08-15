import Foundation

// ============================================================================
// Phase G first-class Undo contracts. Every control uses a fresh disposable
// root and app directory; none observes or mutates the live Desktop.
// ============================================================================

final class PhaseGTests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private final class MutableState {
        let root: URL
        let alternate: URL
        var targetPath: String
        var authorizationCalls = 0
        var flipTargetAtNextAuthorization = false
        var revokeAfterFirstUndoAuthorization = false

        init(root: URL, alternate: URL) {
            self.root = root
            self.alternate = alternate
            targetPath = root.path
        }
    }

    private final class EventRecorder {
        var events: [CanonicalCoreEvent] = []
    }

    private struct Fixture {
        let root: URL
        let alternate: URL
        let app: URL
        let state: MutableState
        let movement: MovementService
        let core: CanonicalApplicationCore
        let events: EventRecorder
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
            .appendingPathComponent("desktidy-phaseg-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture(movementProcessLock: MovementProcessLock? = nil) -> Fixture {
        let sandbox = temporaryDirectory("fixture")
        let root = sandbox.appendingPathComponent("watched", isDirectory: true)
        let alternate = sandbox.appendingPathComponent("alternate", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        try! fm.createDirectory(at: alternate, withIntermediateDirectories: true)
        try! fm.createDirectory(at: app, withIntermediateDirectories: true)

        let state = MutableState(root: root, alternate: alternate)
        let events = EventRecorder()
        let movement = MovementService(
            root: root,
            ledger: ReceiptLedger(appDirectory: app),
            moverVersion: DeskTidyVersion.string,
            log: { _ in }
        )
        let core = CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: app.appendingPathComponent("config.json"),
            targetResolver: {
                .resolved(path: state.targetPath, source: .environment,
                          exists: self.fm.fileExists(atPath: state.targetPath))
            },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: { .fixture("hermetic") },
            authorize: { _ in
                state.authorizationCalls += 1
                if state.flipTargetAtNextAuthorization {
                    state.flipTargetAtNextAuthorization = false
                    state.targetPath = state.alternate.path
                    return .allowed
                }
                if state.revokeAfterFirstUndoAuthorization && state.authorizationCalls > 1 {
                    return .refused("authority changed during undo")
                }
                return .allowed
            },
            emit: { events.events.append($0) },
            movementProcessLock: movementProcessLock
        )
        return Fixture(root: root, alternate: alternate, app: app, state: state,
                       movement: movement, core: core, events: events)
    }

    private func settledFile(in root: URL, named name: String, data: Data) -> URL {
        let file = root.appendingPathComponent(name)
        fm.createFile(atPath: file.path, contents: data)
        try! fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: file.path)
        return file
    }

    private func movedReceipt(_ fixture: Fixture, name: String, data: Data) -> Receipt? {
        _ = settledFile(in: fixture.root, named: name, data: data)
        return fixture.core.tidyNow().moved.first
    }

    private func destination(_ receipt: Receipt, in fixture: Fixture) -> URL {
        fixture.root.appendingPathComponent(receipt.finalDestRel ?? receipt.plannedDestRel)
    }

    func runAll() -> Bool {
        runByteRoundTripContract()
        runSourceSlotContract()
        runDestinationIdentityContracts()
        runTamperedLedgerContract()
        runInterruptedUndoReconciliationContract()
        runConcurrentAndRepeatedUndoContract()
        runTargetAndAuthorityChangeContracts()
        runSymlinkEscapeContract()
        runABACycleProtectionContract()
        runProcessLockContract()
        runLegacyRootCompatibilityContract()
        print("PHASE G GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func runByteRoundTripContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let bytes = Data([0, 1, 2, 0xff, 0x7f, 0x41, 0x00, 0x42])
        guard let original = movedReceipt(f, name: "bytes.bin", data: bytes) else {
            check("G01", "undo restores exact bytes through the canonical receipt path", false, "initial move failed")
            return
        }
        let result = f.core.undo(receiptID: original.id)
        let restored = fm.contents(atPath: f.root.appendingPathComponent("bytes.bin").path)
        let undoReceipt = f.core.history().receipts.last(where: { $0.reversesReceiptID == original.id })
        let movementEvents = f.events.events.filter { $0.kind == .movementCompleted }
        check(
            "G01",
            "undo restores exact bytes through the canonical receipt path",
            result.outcome == .completed
                && restored == bytes
                && undoReceipt?.outcome == "moved"
                && movementEvents.count == 2
        )
    }

    private func runSourceSlotContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let originalBytes = Data("original".utf8)
        guard let original = movedReceipt(f, name: "occupied.pdf", data: originalBytes) else {
            check("G02", "undo refuses an occupied original source slot without overwriting either artifact", false, "initial move failed")
            return
        }
        let occupant = Data("manual occupant".utf8)
        _ = settledFile(in: f.root, named: "occupied.pdf", data: occupant)
        let result = f.core.undo(receiptID: original.id)
        check(
            "G02",
            "undo refuses an occupied original source slot without overwriting either artifact",
            result.refusal == .invalidReceipt(original.id)
                && fm.contents(atPath: f.root.appendingPathComponent("occupied.pdf").path) == occupant
                && fm.contents(atPath: destination(original, in: f).path) == originalBytes
        )
    }

    private func runDestinationIdentityContracts() {
        do {
            let f = fixture()
            defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
            guard let original = movedReceipt(f, name: "missing.pdf", data: Data("original".utf8)) else {
                check("G03", "undo refuses a missing receipt destination", false, "initial move failed")
                return
            }
            try? fm.removeItem(at: destination(original, in: f))
            let result = f.core.undo(receiptID: original.id)
            check("G03", "undo refuses a missing receipt destination",
                  result.refusal == .invalidReceipt(original.id)
                    && !fm.fileExists(atPath: f.root.appendingPathComponent("missing.pdf").path))
        }

        do {
            let f = fixture()
            defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
            guard let original = movedReceipt(f, name: "replaced.pdf", data: Data("original".utf8)) else {
                check("G04", "undo refuses a destination replaced after the original movement", false, "initial move failed")
                return
            }
            let destinationURL = destination(original, in: f)
            try? fm.removeItem(at: destinationURL)
            fm.createFile(atPath: destinationURL.path, contents: Data("replacement".utf8))
            let result = f.core.undo(receiptID: original.id)
            check("G04", "undo refuses a destination replaced after the original movement",
                  result.refusal == .invalidReceipt(original.id)
                    && fm.contents(atPath: destinationURL.path) == Data("replacement".utf8)
                    && !fm.fileExists(atPath: f.root.appendingPathComponent("replaced.pdf").path))
        }

        do {
            let f = fixture()
            defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
            guard let original = movedReceipt(f, name: "modified.pdf", data: Data("payload".utf8)) else {
                check("G05", "undo refuses a live destination whose bounded artifact snapshot changed", false, "initial move failed")
                return
            }
            let destinationURL = destination(original, in: f)
            let changed = Data("altered".utf8)
            try? changed.write(to: destinationURL)
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 3600)], ofItemAtPath: destinationURL.path)
            let result = f.core.undo(receiptID: original.id)
            check("G05", "undo refuses a live destination whose bounded artifact snapshot changed",
                  result.refusal == .invalidReceipt(original.id)
                    && fm.contents(atPath: destinationURL.path) == changed
                    && !fm.fileExists(atPath: f.root.appendingPathComponent("modified.pdf").path))
        }
    }

    private func runTamperedLedgerContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        guard let original = movedReceipt(f, name: "ledger.pdf", data: Data("ledger".utf8)),
              var text = String(data: fm.contents(atPath: f.movement.ledger.ledgerURL.path) ?? Data(), encoding: .utf8) else {
            check("G06", "undo fails closed when the receipt ledger digest chain is tampered", false, "initial move or ledger read failed")
            return
        }
        text = text.replacingOccurrences(of: "ledger.pdf", with: "Ledger.pdf")
        try? Data(text.utf8).write(to: f.movement.ledger.ledgerURL, options: [.atomic])
        let result = f.core.undo(receiptID: original.id)
        check("G06", "undo fails closed when the receipt ledger digest chain is tampered",
              f.movement.ledger.verifyChain() != nil
                && result.refusal == .invalidReceipt(original.id)
                && fm.fileExists(atPath: destination(original, in: f).path))
    }

    private func runInterruptedUndoReconciliationContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let bytes = Data("recoverable undo".utf8)
        guard let original = movedReceipt(f, name: "interrupted.pdf", data: bytes) else {
            check("G07", "post-move undo interruption remains pending and restart reconciles an exact undo receipt", false, "initial move failed")
            return
        }
        f.movement.ledger.testHookBeforeAppend = { receipt in
            if receipt.reversesReceiptID == original.id { throw CocoaError(.fileWriteUnknown) }
        }
        let interrupted = f.core.undo(receiptID: original.id)
        f.movement.ledger.testHookBeforeAppend = nil
        let pending = (try? fm.contentsOfDirectory(atPath: f.movement.ledger.pendingDir.path)) ?? []
        let restarted = MovementService(root: f.root, ledger: f.movement.ledger,
                                        moverVersion: DeskTidyVersion.string, log: { _ in })
        let reconciled = restarted.startupReconcile()
        let recovered = f.movement.ledger.readAll().receipts.last(where: { $0.reversesReceiptID == original.id })
        check(
            "G07",
            "post-move undo interruption remains pending and restart reconciles an exact undo receipt",
            interrupted.outcome == .failed
                && pending.contains(where: { $0.hasSuffix(".json") })
                && reconciled == 1
                && recovered?.outcome == "recovered"
                && recovered?.undoEligible == false
                && fm.contents(atPath: f.root.appendingPathComponent("interrupted.pdf").path) == bytes
                && !fm.fileExists(atPath: destination(original, in: f).path)
        )
    }

    private func runConcurrentAndRepeatedUndoContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let bytes = Data("one winner".utf8)
        guard let original = movedReceipt(f, name: "concurrent.pdf", data: bytes) else {
            check("G08", "concurrent and repeated undo requests have one durable winner", false, "initial move failed")
            return
        }
        let resultLock = NSLock()
        var results: [CanonicalCommandResult] = []
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            let result = f.core.undo(receiptID: original.id)
            resultLock.lock()
            results.append(result)
            resultLock.unlock()
        }
        let repeated = f.core.undo(receiptID: original.id)
        let reversals = f.core.history().receipts.filter {
            $0.reversesReceiptID == original.id && ($0.outcome == "moved" || $0.outcome == "recovered")
        }
        check(
            "G08",
            "concurrent and repeated undo requests have one durable winner",
            results.filter { $0.outcome == .completed }.count == 1
                && results.filter { $0.refusal == .invalidReceipt(original.id) }.count == 7
                && repeated.refusal == .invalidReceipt(original.id)
                && reversals.count == 1
                && fm.contents(atPath: f.root.appendingPathComponent("concurrent.pdf").path) == bytes
        )
    }

    private func runTargetAndAuthorityChangeContracts() {
        do {
            let f = fixture()
            defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
            guard let original = movedReceipt(f, name: "target.pdf", data: Data("target".utf8)) else {
                check("G09", "undo rechecks the resolved target before moving", false, "initial move failed")
                return
            }
            f.state.authorizationCalls = 0
            f.state.flipTargetAtNextAuthorization = true
            let result = f.core.undo(receiptID: original.id)
            check("G09", "undo rechecks the resolved target before moving",
                  result.refusal == .targetMismatch
                    && fm.fileExists(atPath: destination(original, in: f).path)
                    && !fm.fileExists(atPath: f.root.appendingPathComponent("target.pdf").path))
        }

        do {
            let f = fixture()
            defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
            guard let original = movedReceipt(f, name: "authority.pdf", data: Data("authority".utf8)) else {
                check("G10", "undo rechecks movement authority after command preparation", false, "initial move failed")
                return
            }
            f.state.authorizationCalls = 0
            f.state.revokeAfterFirstUndoAuthorization = true
            let result = f.core.undo(receiptID: original.id)
            check("G10", "undo rechecks movement authority after command preparation",
                  result.refusal == .unauthorized("authority changed during undo")
                    && fm.fileExists(atPath: destination(original, in: f).path)
                    && !fm.fileExists(atPath: f.root.appendingPathComponent("authority.pdf").path))
        }
    }

    private func runSymlinkEscapeContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        guard let original = movedReceipt(f, name: "escape.pdf", data: Data("protected".utf8)) else {
            check("G11", "undo rejects a receipt destination made reachable only through a symlink escape", false, "initial move failed")
            return
        }
        let destinationURL = destination(original, in: f)
        let outside = f.root.deletingLastPathComponent().appendingPathComponent("outside", isDirectory: true)
        try? fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try? fm.removeItem(at: destinationURL)
        try? fm.removeItem(at: destinationURL.deletingLastPathComponent())
        fm.createFile(atPath: outside.appendingPathComponent("escape.pdf").path, contents: Data("outside".utf8))
        try? fm.createSymbolicLink(at: destinationURL.deletingLastPathComponent(), withDestinationURL: outside)
        let result = f.core.undo(receiptID: original.id)
        check("G11", "undo rejects a receipt destination made reachable only through a symlink escape",
              result.refusal == .invalidReceipt(original.id)
                && fm.contents(atPath: outside.appendingPathComponent("escape.pdf").path) == Data("outside".utf8)
                && !fm.fileExists(atPath: f.root.appendingPathComponent("escape.pdf").path))
    }

    private func runABACycleProtectionContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let bytes = Data("cycle bytes".utf8)
        guard let first = movedReceipt(f, name: "cycle.pdf", data: bytes) else {
            check("G12", "A→B→A cycles cannot replay an earlier undo receipt against a later artifact", false, "initial move failed")
            return
        }
        let firstUndo = f.core.undo(receiptID: first.id)
        let secondMove = f.core.tidyNow()
        let staleUndo = f.core.undo(receiptID: first.id)
        guard let second = secondMove.moved.first else {
            check("G12", "A→B→A cycles cannot replay an earlier undo receipt against a later artifact", false, "second move failed")
            return
        }
        check(
            "G12",
            "A→B→A cycles cannot replay an earlier undo receipt against a later artifact",
            firstUndo.outcome == .completed
                && staleUndo.refusal == .invalidReceipt(first.id)
                && fm.contents(atPath: destination(second, in: f).path) == bytes
                && !fm.fileExists(atPath: f.root.appendingPathComponent("cycle.pdf").path)
        )
    }

    private func runProcessLockContract() {
        let sandbox = temporaryDirectory("process-lock")
        let lockURL = sandbox.appendingPathComponent("desktidy.lock")
        let coreLock = MovementProcessLock(url: lockURL)
        let f = fixture(movementProcessLock: coreLock)
        defer {
            try? fm.removeItem(at: f.root.deletingLastPathComponent())
            try? fm.removeItem(at: sandbox)
        }
        let bytes = Data("cross process serialization".utf8)
        guard let original = movedReceipt(f, name: "serialized.pdf", data: bytes) else {
            check("G13", "Undo serializes with the automatic mover's process lock", false, "initial move failed")
            return
        }
        let competing = MovementProcessLock(url: lockURL)
        try? competing.acquire()
        let blocked = f.core.undo(receiptID: original.id)
        competing.release()
        let completed = f.core.undo(receiptID: original.id)
        check(
            "G13",
            "Undo serializes with the automatic mover's process lock",
            blocked.refusal == .movementBusy
                && completed.outcome == .completed
                && fm.contents(atPath: f.root.appendingPathComponent("serialized.pdf").path) == bytes
        )
    }

    private func runLegacyRootCompatibilityContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let names = ["Archive", "Docs", "Media", "Projects"]
        for name in names {
            let directory = f.root.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
                                  ofItemAtPath: directory.path)
        }
        let result = f.core.tidyNow()
        check(
            "G14",
            "manual Tidy Now preserves legacy category roots just like the automatic mover",
            result.moved.isEmpty
                && names.allSatisfy { fm.fileExists(atPath: f.root.appendingPathComponent($0).path) }
        )
    }
}
