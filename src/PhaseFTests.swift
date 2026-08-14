import Foundation
import UserNotifications

// ============================================================================
// Phase F receipt-derived notification contracts. These tests are hermetic:
// the sender is an in-process fake and every movement uses a disposable root.
// ============================================================================

final class PhaseFTests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private final class FakeReceiptNotificationSender: ReceiptNotificationSending {
        var payloads: [ReceiptNotificationPayload] = []
        var nextResult: Result<Void, Error> = .success(())

        func send(_ payload: ReceiptNotificationPayload,
                  completion: @escaping (Result<Void, Error>) -> Void) {
            payloads.append(payload)
            completion(nextResult)
        }
    }

    private final class FakeReceiptNotificationActionHandler: ReceiptNotificationActionHandling {
        func handle(action: ReceiptNotificationAction, receiptID: String) {}
    }

    private final class RevealRecorder {
        var urls: [URL] = []
    }

    private struct Fixture {
        let root: URL
        let app: URL
        let core: CanonicalApplicationCore
        let sender: FakeReceiptNotificationSender
        let service: ReceiptNotificationService
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
            .appendingPathComponent("desktidy-phasef-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture() -> Fixture {
        let sandbox = temporaryDirectory("fixture")
        let root = sandbox.appendingPathComponent("watched", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        try! fm.createDirectory(at: app, withIntermediateDirectories: true)
        let movement = MovementService(
            root: root,
            ledger: ReceiptLedger(appDirectory: app),
            moverVersion: DeskTidyVersion.string,
            log: { _ in }
        )
        let sender = FakeReceiptNotificationSender()
        var core: CanonicalApplicationCore!
        let service = ReceiptNotificationService(
            sender: sender,
            dedupeStore: InMemoryReceiptNotificationDedupeStore(),
            undoEligible: { receiptID in core.isUndoEligible(receiptID: receiptID) },
            schedule: { work in work() }
        )
        core = CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: app.appendingPathComponent("config.json"),
            targetResolver: { .resolved(path: root.path, source: .environment, exists: true) },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: { .fixture("hermetic") },
            authorize: { _ in .allowed },
            movementCompleted: { receipt in service.enqueue(receipt) }
        )
        return Fixture(root: root, app: app, core: core, sender: sender, service: service)
    }

    private func settledFile(in root: URL, named name: String) {
        let file = root.appendingPathComponent(name)
        fm.createFile(atPath: file.path, contents: Data("fixture".utf8))
        try! fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: file.path)
    }

    func runAll() -> Bool {
        runSuccessfulMoveNotificationContract()
        runDeliveryFailureContract()
        runDuplicateReceiptContract()
        runStaleUndoEligibilityContract()
        runInvalidPayloadRetryContract()
        runAuthorizationGatedDispatchContract()
        runAuthorizationRefusalContract()
        runRevealPayloadAndActionRoutingContract()
        print("PHASE F GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func runSuccessfulMoveNotificationContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        settledFile(in: f.root, named: "report.pdf")

        let result = f.core.tidyNow()
        let receipt = result.moved.first
        let payload = f.sender.payloads.first
        check(
            "F01",
            "a completed durable movement receipt produces one receipt-derived notification",
            result.moved.count == 1
                && receipt?.outcome == "moved"
                && f.core.history().receipts.contains(where: { $0.id == receipt?.id })
                && payload?.receiptID == receipt?.id
                && payload?.originalName == "report.pdf"
                && payload?.finalName == "report.pdf"
                && payload?.destinationCategory == Config.folderDocuments
                && payload?.destinationPath == "\(Config.folderDocuments)/report.pdf"
                && payload?.actions == [.reveal, .undo]
        )
    }

    private func runDeliveryFailureContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        f.sender.nextResult = .failure(CocoaError(.fileWriteUnknown))
        settledFile(in: f.root, named: "failure.pdf")

        let result = f.core.tidyNow()
        let receipt = result.moved.first
        let destination = receipt.map { f.root.appendingPathComponent($0.finalDestRel ?? $0.plannedDestRel) }
        check(
            "F02",
            "sender failure occurs after the durable move and cannot reverse or fail the command",
            result.refusal == nil
                && result.moved.count == 1
                && receipt?.outcome == "moved"
                && receipt.map { moved in f.core.history().receipts.contains(where: { $0.id == moved.id }) } == true
                && destination.map { self.fm.fileExists(atPath: $0.path) } == true
                && f.sender.payloads.count == 1
        )
    }

    private func runDuplicateReceiptContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        settledFile(in: f.root, named: "duplicate.pdf")
        let result = f.core.tidyNow()
        guard let receipt = result.moved.first else {
            check("F03", "a duplicate completed receipt does not create a second notification", false)
            return
        }

        f.service.enqueue(receipt)
        check(
            "F03",
            "a duplicate completed receipt does not create a second notification",
            f.sender.payloads.count == 1
        )
    }

    private func runStaleUndoEligibilityContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        settledFile(in: f.root, named: "stale.pdf")
        guard let original = f.core.tidyNow().moved.first else {
            check("F04", "a receipt reversed before delivery has no Undo action", false)
            return
        }
        _ = CanonicalCoreCommandAdapter(core: f.core).undo(receiptID: original.id)

        let sender = FakeReceiptNotificationSender()
        let service = ReceiptNotificationService(
            sender: sender,
            dedupeStore: InMemoryReceiptNotificationDedupeStore(),
            undoEligible: { receiptID in f.core.isUndoEligible(receiptID: receiptID) },
            schedule: { work in work() }
        )
        service.enqueue(original)
        check(
            "F04",
            "a receipt reversed before delivery has no Undo action",
            sender.payloads.first?.actions == [.reveal]
        )
    }

    private func runInvalidPayloadRetryContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        settledFile(in: f.root, named: "retry.pdf")
        guard let receipt = f.core.tidyNow().moved.first else {
            check("F05", "an invalid payload leaves its receipt available for a later valid retry", false)
            return
        }

        var invalid = receipt
        invalid.id = "notification-payload-retry"
        invalid.sourceRel = "../retry.pdf"
        var retry = receipt
        retry.id = invalid.id

        let sender = FakeReceiptNotificationSender()
        let service = ReceiptNotificationService(
            sender: sender,
            dedupeStore: InMemoryReceiptNotificationDedupeStore(),
            undoEligible: { _ in true },
            schedule: { work in work() }
        )
        service.enqueue(invalid)
        service.enqueue(retry)
        check(
            "F05",
            "an invalid payload leaves its receipt available for a later valid retry",
            sender.payloads.count == 1 && sender.payloads.first?.receiptID == retry.id
        )
    }

    private func runAuthorizationGatedDispatchContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        settledFile(in: f.root, named: "authorization.pdf")
        guard let receipt = f.core.tidyNow().moved.first,
              let payload = ReceiptNotificationPayload(receipt: receipt, undoEligible: true) else {
            check("F06", "notification dispatch requests alert, badge, and sound authorization before adding", false)
            return
        }

        var requestedOptions: UNAuthorizationOptions = []
        var events: [String] = []
        var result: Result<Void, Error>?
        let sender = UNUserNotificationCenterReceiptSender(
            actionHandler: FakeReceiptNotificationActionHandler(),
            requestAuthorization: { options, completion in
                requestedOptions = options
                events.append("authorize")
                completion(true, nil)
            },
            addRequest: { _, completion in
                events.append("add")
                completion(nil)
            }
        )
        sender.send(payload) {
            result = $0
            events.append("complete")
        }
        let delivered: Bool
        if case .success? = result {
            delivered = true
        } else {
            delivered = false
        }
        check(
            "F06",
            "notification dispatch requests alert, badge, and sound authorization before adding",
            requestedOptions == [.alert, .badge, .sound]
                && events == ["authorize", "add", "complete"]
                && delivered
        )
    }

    private func runAuthorizationRefusalContract() {
        var requestAdded = false
        var result: Result<Void, Error>?
        let sender = UNUserNotificationCenterReceiptSender(
            actionHandler: FakeReceiptNotificationActionHandler(),
            requestAuthorization: { _, completion in completion(false, nil) },
            addRequest: { _, completion in
                requestAdded = true
                completion(nil)
            }
        )
        let payload = ReceiptNotificationPayload(
            receipt: Receipt(
                id: "authorization-refusal",
                preparedAt: "",
                completedAt: nil,
                moverLabel: "",
                moverVersion: "",
                rootCanonical: "",
                sourceRel: "source.pdf",
                plannedDestRel: "Documents/source.pdf",
                finalDestRel: "Documents/source.pdf",
                ruleID: "",
                rulePolicyVersion: "",
                settleMTime: "",
                settleAgeSeconds: 0,
                collision: false,
                outcome: "moved",
                failureCode: nil,
                undoEligible: false,
                prevDigest: "",
                digest: ""
            ),
            undoEligible: false
        )!
        sender.send(payload) { result = $0 }
        let refused: Bool
        if case .failure? = result {
            refused = true
        } else {
            refused = false
        }
        check(
            "F07",
            "a declined authorization reports failure without adding a notification request",
            refused && !requestAdded
        )
    }

    private func runRevealPayloadAndActionRoutingContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.root.deletingLastPathComponent()) }
        settledFile(in: f.root, named: "reveal.pdf")
        guard let receipt = f.core.tidyNow().moved.first else {
            check("F08", "Reveal resolves the receipt destination through the canonical command adapter", false)
            return
        }
        let adapter = CanonicalCoreCommandAdapter(core: f.core)
        let recorder = RevealRecorder()
        let router = CanonicalReceiptNotificationActionRouter(
            commandAdapter: { Optional(adapter) },
            reveal: { recorder.urls.append($0) }
        )
        router.handle(action: .reveal, receiptID: receipt.id)

        let expected = f.root.appendingPathComponent(receipt.finalDestRel ?? receipt.plannedDestRel)
        check(
            "F08",
            "Reveal resolves the receipt destination through the canonical command adapter",
            recorder.urls == [expected]
        )
    }
}
