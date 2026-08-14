import Foundation

// ============================================================================
//  Phase C canonical-application-core contracts. Hermetic only: every test
//  creates a disposable watched root and passes a real MovementService.
// ============================================================================

final class PhaseCTests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private final class EventRecorder {
        var events: [CanonicalCoreEvent] = []
    }

    private struct Fixture {
        let root: URL
        let alternate: URL
        let app: URL
        let events: EventRecorder
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
        let url = fm.temporaryDirectory.appendingPathComponent("desktidy-phasec-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture(authorized: @escaping (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization = { _ in .allowed }) -> Fixture {
        let sandbox = temporaryDirectory("fixture")
        let root = sandbox.appendingPathComponent("watched", isDirectory: true)
        let alternate = sandbox.appendingPathComponent("alternate", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        try! fm.createDirectory(at: alternate, withIntermediateDirectories: true)
        try! fm.createDirectory(at: app, withIntermediateDirectories: true)
        let env = ["DESKTIDY_APP_DIR": app.path, "DESKTIDY_TARGET_DIR": root.path]
        let movement = MovementService(
            root: root,
            ledger: ReceiptLedger(appDirectory: app),
            moverVersion: DeskTidyVersion.string,
            log: { _ in }
        )
        let events = EventRecorder()
        let core = CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: app.appendingPathComponent("config.json"),
            targetResolver: { TargetResolver.resolve(env: env, home: sandbox, fm: self.fm) },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: { .fixture("hermetic") },
            authorize: authorized,
            emit: { events.events.append($0) }
        )
        return Fixture(root: root, alternate: alternate, app: app, events: events, core: core)
    }

    private func settledFile(in root: URL, named name: String) -> URL {
        let file = root.appendingPathComponent(name)
        fm.createFile(atPath: file.path, contents: Data("fixture".utf8))
        try! fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: file.path)
        return file
    }

    func runAll() -> Bool {
        runTargetConfigurationContract()
        runInvalidConfigurationContract()
        runPauseResumeContract()
        runMoveHistoryUndoAndNotificationContract()
        runStatusAndAdapterContract()
        runUndoReplayContract()
        print("PHASE C GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func runTargetConfigurationContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let result = f.core.setTarget(f.alternate.path)
        let configured: Bool
        switch TargetResolver.resolve(
            env: ["DESKTIDY_APP_DIR": f.app.path, "DESKTIDY_TARGET_DIR": f.root.path],
            home: f.root.deletingLastPathComponent(),
            fm: fm
        ) {
        case .resolved(let path, let source, _):
            configured = AuthorityGuard.canonicalize(path) == AuthorityGuard.canonicalize(f.alternate.path)
                && source == .nativeConfig
        case .invalid: configured = false
        }
        let receipts = f.core.commandHistory()
        check(
            "C01",
            "authorized target changes are strict native config plus a durable command receipt",
            result.outcome == .completed
                && configured
                && receipts.contains { $0.command == .setTarget && $0.outcome == .completed },
            "outcome=\(result.outcome.rawValue), configured=\(configured), receipts=\(receipts.map { "\($0.command.rawValue):\($0.outcome.rawValue)" }.joined(separator: ","))"
        )
    }

    private func runInvalidConfigurationContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let source = settledFile(in: f.root, named: "stay.pdf")
        try! Data("{not-json}".utf8).write(to: f.app.appendingPathComponent("config.json"))
        let result = f.core.tidyNow()
        check(
            "C02",
            "invalid serialized config fails closed before a Tidy Now move",
            result.refusal == .invalidTargetConfiguration
                && fm.fileExists(atPath: source.path)
                && f.core.history().receipts.isEmpty
        )
    }

    private func runPauseResumeContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let source = settledFile(in: f.root, named: "pause.pdf")
        let paused = f.core.pause()
        let whilePaused = f.core.tidyNow()
        let resumed = f.core.resume()
        let afterResume = f.core.tidyNow()
        check(
            "C03",
            "pause and resume are authorized, receipted, and gate Tidy Now",
            paused.outcome == .completed
                && whilePaused.refusal == .paused
                && resumed.outcome == .completed
                && afterResume.moved.count == 1
                && !fm.fileExists(atPath: source.path)
                && f.core.commandHistory().filter { $0.command == .pause || $0.command == .resume }.count == 4
        )
    }

    private func runMoveHistoryUndoAndNotificationContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let source = settledFile(in: f.root, named: "invoice.pdf")
        let moved = f.core.tidyNow()
        let receiptID = moved.moved.first?.id
        let whereResult = f.core.whereDidItGo(named: "invoice.pdf")
        let undo = receiptID.map { f.core.undo(receiptID: $0) }
        let moveEvents = f.events.events.filter { $0.kind == .movementCompleted }
        check(
            "C04",
            "Tidy Now, history, Where Did It Go, undo, and notification events share MovementService receipts",
            moved.moved.count == 1
                && whereResult?.destination == "Documents/invoice.pdf"
                && undo?.outcome == .completed
                && fm.fileExists(atPath: source.path)
                && f.core.history().receipts.filter { $0.outcome == "moved" }.count == 2
                && moveEvents.count == 2
        )
    }

    private func runStatusAndAdapterContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let status = f.core.installationStatus()
        let state = f.core.effectiveState()
        let adapter = CanonicalCoreCommandAdapter(core: f.core)
        let source = settledFile(in: f.root, named: "adapter.pdf")
        let moved = adapter.execute(.tidyNow)
        check(
            "C05",
            "core owns effective-state, diagnostics, receipt-location reads, typed lifecycle status, and the future-intent adapter path",
            status == .fixture("hermetic")
                && state.effective.targetResolution == "resolved"
                && f.core.receiptsDirectory() == f.app.appendingPathComponent("receipts", isDirectory: true)
                && f.core.diagnostic().contains("DeskTidy effective state")
                && moved.tidyNow?.moved.count == 1
                && !fm.fileExists(atPath: source.path)
        )
    }

    private func runUndoReplayContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        let originalSource = settledFile(in: f.root, named: "replay.pdf")
        let original = f.core.tidyNow()
        guard let receiptID = original.moved.first?.id else {
            check("C06", "an undo receipt cannot be replayed against a later file", false, "initial move did not create a receipt")
            return
        }
        _ = f.core.undo(receiptID: receiptID)
        try? fm.removeItem(at: originalSource)
        _ = settledFile(in: f.root, named: "replay.pdf")
        let laterMove = f.core.tidyNow()
        let replay = f.core.undo(receiptID: receiptID)
        let laterDestination = f.root.appendingPathComponent("Documents/replay.pdf")
        check(
            "C06",
            "an undo receipt cannot be replayed against a later file",
            laterMove.moved.count == 1
                && replay.refusal == .invalidReceipt(receiptID)
                && fm.fileExists(atPath: laterDestination.path)
        )
    }
}
