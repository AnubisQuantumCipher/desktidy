import Foundation

// ============================================================================
// Phase E durable pause contracts. Every fixture is self-contained under
// /private/tmp and passes a real MovementService. No fixture targets Desktop.
// ============================================================================

final class PhaseETests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private final class Clock {
        var date: Date
        var monotonic: TimeInterval
        let bootSessionID: String

        init(date: Date = Date(timeIntervalSince1970: 1_000), monotonic: TimeInterval = 10, bootSessionID: String = "phase-e-boot") {
            self.date = date
            self.monotonic = monotonic
            self.bootSessionID = bootSessionID
        }
    }

    private final class CoreReference {
        var core: CanonicalApplicationCore?
    }

    private final class Results {
        private let lock = NSLock()
        private var values: [CanonicalTidyNowResult] = []

        func append(_ value: CanonicalTidyNowResult) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        func all() -> [CanonicalTidyNowResult] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private final class TargetPointer {
        var path: String

        init(_ path: String) {
            self.path = path
        }
    }

    private struct Fixture {
        let sandbox: URL
        let root: URL
        let alternate: URL
        let app: URL
        let clock: Clock
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
            .appendingPathComponent("desktidy-phasee-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeCore(
        root: URL,
        app: URL,
        clock: Clock,
        targetPath: @escaping () -> String,
        authorize: @escaping (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization = { _ in .allowed },
        beforeMove: @escaping () -> Void = {}
    ) -> CanonicalApplicationCore {
        let movement = MovementService(
            root: root,
            ledger: ReceiptLedger(appDirectory: app),
            moverVersion: DeskTidyVersion.string,
            log: { _ in }
        )
        return CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: app.appendingPathComponent("config.json"),
            targetResolver: { .resolved(path: targetPath(), source: .environment, exists: true) },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: { .fixture("phase-e") },
            authorize: authorize,
            dateNow: { clock.date },
            monotonicNow: { clock.monotonic },
            bootSessionID: { clock.bootSessionID },
            beforeMove: beforeMove
        )
    }

    private func fixture(
        clock: Clock = Clock(),
        authorize: @escaping (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization = { _ in .allowed },
        targetPath: (() -> String)? = nil,
        beforeMove: @escaping () -> Void = {}
    ) -> Fixture {
        let sandbox = temporaryDirectory("fixture")
        let root = sandbox.appendingPathComponent("watched", isDirectory: true)
        let alternate = sandbox.appendingPathComponent("alternate", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        try! fm.createDirectory(at: alternate, withIntermediateDirectories: true)
        try! fm.createDirectory(at: app, withIntermediateDirectories: true)
        let core = makeCore(root: root, app: app, clock: clock,
                            targetPath: targetPath ?? { root.path },
                            authorize: authorize, beforeMove: beforeMove)
        return Fixture(sandbox: sandbox, root: root, alternate: alternate, app: app, clock: clock, core: core)
    }

    private func settledFile(in root: URL, named name: String) -> URL {
        let file = root.appendingPathComponent(name)
        fm.createFile(atPath: file.path, contents: Data("fixture".utf8))
        try! fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: file.path)
        return file
    }

    func runAll() -> Bool {
        runDurationExpiryAndRestartContract()
        runCorruptPauseFailsClosedContract()
        runPauseAtWorkBoundaryContract()
        runPauseAfterFirstMovePreservesPartialResultContract()
        runIdempotentResumeContract()
        runConcurrentTidyNowContract()
        runAuthorityAndTargetChangeContract()
        print("PHASE E GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func runDurationExpiryAndRestartContract() {
        let clock = Clock()
        let f = fixture(clock: clock)
        defer { try? fm.removeItem(at: f.sandbox) }
        let source = settledFile(in: f.root, named: "expiry.pdf")
        let pause = f.core.pause(for: 60)
        let blocked = f.core.tidyNow()
        let pausedState = f.core.pauseState()
        let restartBeforeExpiry = makeCore(root: f.root, app: f.app, clock: clock, targetPath: { f.root.path })
        let restartBeforeExpiryState = restartBeforeExpiry.pauseState()
        clock.date.addTimeInterval(61)
        clock.monotonic += 61
        let restartAfterExpiry = makeCore(root: f.root, app: f.app, clock: clock, targetPath: { f.root.path })
        let afterExpiry = restartAfterExpiry.tidyNow()
        let wasBounded: Bool
        if case .pausedUntil = pausedState { wasBounded = true } else { wasBounded = false }
        check(
            "E01",
            "bounded pauses survive a core restart, block until their monotonic or wall deadline, then expire",
            pause.outcome == .completed
                && wasBounded
                && blocked.refusal == .paused
                && restartBeforeExpiryState.isMovementBlocked
                && restartAfterExpiry.pauseState() == .running
                && afterExpiry.moved.count == 1
                && !fm.fileExists(atPath: source.path)
        )
    }

    private func runCorruptPauseFailsClosedContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let source = settledFile(in: f.root, named: "corrupt.pdf")
        let pauseURL = f.app.appendingPathComponent("pause-state.json")
        try! Data("{not-json}".utf8).write(to: pauseURL)
        let state = f.core.pauseState()
        let result = f.core.tidyNow()
        let unreadable: Bool
        if case .unreadable = state { unreadable = true } else { unreadable = false }
        check(
            "E02",
            "corrupt durable pause data is observable and fails closed before Tidy Now scans or moves",
            unreadable
                && state.isMovementBlocked
                && result.refusal == .paused
                && fm.fileExists(atPath: source.path)
                && f.core.history().receipts.isEmpty
        )
    }

    private func runPauseAtWorkBoundaryContract() {
        let reference = CoreReference()
        let f = fixture(beforeMove: { _ = reference.core?.pauseIndefinitely() })
        reference.core = f.core
        defer { try? fm.removeItem(at: f.sandbox) }
        let source = settledFile(in: f.root, named: "boundary.pdf")
        let result = f.core.tidyNow()
        check(
            "E03",
            "a pause accepted after Tidy Now begins but before MovementService.perform blocks that move",
            result.refusal == .paused
                && fm.fileExists(atPath: source.path)
                && f.core.history().receipts.isEmpty
                && f.core.pauseState().isMovementBlocked
        )
    }

    private func runPauseAfterFirstMovePreservesPartialResultContract() {
        let reference = CoreReference()
        var beforeMoveCount = 0
        let f = fixture(beforeMove: {
            beforeMoveCount += 1
            if beforeMoveCount == 2 {
                _ = reference.core?.pauseIndefinitely()
            }
        })
        reference.core = f.core
        defer { try? fm.removeItem(at: f.sandbox) }
        let first = settledFile(in: f.root, named: "first.pdf")
        let second = settledFile(in: f.root, named: "second.pdf")
        let result = f.core.tidyNow()
        let movementReceipts = f.core.history().receipts.filter { $0.outcome == "moved" }
        let durableFailure = f.core.commandHistory().contains {
            $0.command == .tidyNow
                && $0.id == result.receiptID
                && $0.outcome == .failed
                && $0.detail == "DeskTidy is paused"
        }
        check(
            "E04",
            "a pause after one move preserves its result and records the Tidy Now command as a durable paused refusal",
            result.moved.count == 1
                && result.moved.count == movementReceipts.count
                && result.moved.first?.id == movementReceipts.first?.id
                && result.failed.isEmpty
                && result.skippedFresh == 0
                && result.refusal == .paused
                && result.receiptID != nil
                && durableFailure
                && !fm.fileExists(atPath: first.path)
                && fm.fileExists(atPath: second.path)
        )
    }

    private func runIdempotentResumeContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let paused = f.core.pauseIndefinitely()
        let first = f.core.resume()
        let second = f.core.resume()
        let resumes = f.core.commandHistory().filter { $0.command == .resume && $0.outcome == .completed }
        check(
            "E05",
            "resume is idempotent: an already-running durable state still returns a completed receipted command",
            paused.outcome == .completed
                && first.outcome == .completed
                && second.outcome == .completed
                && f.core.pauseState() == .running
                && resumes.count == 2
        )
    }

    private func runConcurrentTidyNowContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        let source = settledFile(in: f.root, named: "concurrent.pdf")
        let results = Results()
        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            results.append(f.core.tidyNow())
        }
        let values = results.all()
        let movementReceipts = f.core.history().receipts.filter { $0.outcome == "moved" }
        check(
            "E06",
            "concurrent Tidy Now requests serialize through the core and create exactly one MovementService receipt",
            values.count == 2
                && values.reduce(0) { $0 + $1.moved.count } == 1
                && movementReceipts.count == 1
                && !fm.fileExists(atPath: source.path)
        )
    }

    private func runAuthorityAndTargetChangeContract() {
        let foreign = fixture(authorize: { request in
            .refused("foreign mover owns \(request.currentTarget ?? "unknown")")
        })
        defer { try? fm.removeItem(at: foreign.sandbox) }
        let foreignSource = settledFile(in: foreign.root, named: "foreign.pdf")
        let foreignPause = foreign.core.pause(for: 30)
        let foreignTidy = foreign.core.tidyNow()

        let pointer = TargetPointer("unused")
        let changed = fixture(targetPath: { pointer.path })
        pointer.path = changed.alternate.path
        defer { try? fm.removeItem(at: changed.sandbox) }
        let changedSource = settledFile(in: changed.root, named: "changed.pdf")
        let changedPause = changed.core.pauseIndefinitely()
        let changedTidy = changed.core.tidyNow()

        check(
            "E07",
            "foreign authority and a target changed before a control call both refuse without writing pause state or moving files",
            foreignPause.refusal == .unauthorized("foreign mover owns \(foreign.root.path)")
                && foreignTidy.refusal == .unauthorized("foreign mover owns \(foreign.root.path)")
                && foreign.core.pauseState() == .running
                && fm.fileExists(atPath: foreignSource.path)
                && changedPause.refusal == .targetMismatch
                && changedTidy.refusal == .targetMismatch
                && changed.core.pauseState() == .running
                && fm.fileExists(atPath: changedSource.path)
        )
    }
}
