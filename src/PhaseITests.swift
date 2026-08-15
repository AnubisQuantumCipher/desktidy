import Foundation

// ============================================================================
// Phase I — hermetic App Intent adapter contracts.
// These fixtures stay under /private/tmp and inject a canonical core; they do
// not invoke Shortcuts, App Intents runtime, ServiceManagement, or a Desktop.
// ============================================================================

final class PhaseITests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private struct Fixture {
        let sandbox: URL
        let root: URL
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

    private func fixture(authorization: @escaping (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization = { _ in .allowed }) -> Fixture {
        let sandbox = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("desktidy-phasei-\(UUID().uuidString)", isDirectory: true)
        let root = sandbox.appendingPathComponent("watched", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try! fm.createDirectory(at: root, withIntermediateDirectories: true)
        try! fm.createDirectory(at: app, withIntermediateDirectories: true)
        let environment = ["DESKTIDY_APP_DIR": app.path, "DESKTIDY_TARGET_DIR": root.path]
        let movement = MovementService(
            root: root,
            ledger: ReceiptLedger(appDirectory: app),
            moverVersion: DeskTidyVersion.string,
            log: { _ in }
        )
        let core = CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: app.appendingPathComponent("config.json"),
            targetResolver: { TargetResolver.resolve(env: environment, home: sandbox, fm: self.fm) },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: { .fixture("phase-i") },
            authorize: authorization
        )
        return Fixture(sandbox: sandbox, root: root, core: core)
    }

    private func settledFile(in root: URL, named name: String) {
        let file = root.appendingPathComponent(name)
        fm.createFile(atPath: file.path, contents: Data("fixture".utf8))
        try! fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: file.path)
    }

    func runAll() -> Bool {
        runUnavailableBridgeContract()
        runAuthorizationAndBoundedPauseContract()
        runTidyAndReadModelContract()
        print("PHASE I GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func runUnavailableBridgeContract() {
        let bridge = DeskTidyIntentBridge()
        let result = bridge.status()
        check(
            "I01",
            "an uninstalled bridge returns bounded unavailable evidence without constructing a live core",
            result.evidence == .unavailable && result.lifecycle == .unavailable,
            "evidence=\(result.evidence), lifecycle=\(result.lifecycle)"
        )
    }

    private func runAuthorizationAndBoundedPauseContract() {
        let denied = fixture(authorization: { _ in .refused("fixture refusal") })
        defer { try? fm.removeItem(at: denied.sandbox) }
        let deniedBridge = DeskTidyIntentBridge(adapter: CanonicalIntentAdapter(core: denied.core))
        let refusal = deniedBridge.pause(.fiveMinutes)

        let allowed = fixture()
        defer { try? fm.removeItem(at: allowed.sandbox) }
        let bridge = DeskTidyIntentBridge(adapter: CanonicalIntentAdapter(core: allowed.core))
        let paused = bridge.pause(.fiveMinutes)
        let wasBlocked = allowed.core.pauseState().isMovementBlocked
        let resumed = bridge.resume()
        check(
            "I02",
            "pause durations are a fixed enum and pause/resume preserve canonical authorization and receipts",
            refusal.evidence == .refused
                && paused.evidence == .completed
                && wasBlocked
                && resumed.evidence == .completed
                && !allowed.core.pauseState().isMovementBlocked,
            "refusal=\(refusal.evidence), paused=\(paused.evidence), resumed=\(resumed.evidence)"
        )
    }

    private func runTidyAndReadModelContract() {
        let f = fixture()
        defer { try? fm.removeItem(at: f.sandbox) }
        settledFile(in: f.root, named: "intent.pdf")
        let bridge = DeskTidyIntentBridge(adapter: CanonicalIntentAdapter(core: f.core))
        let tidy = bridge.tidyNow()
        let status = bridge.status()
        let recent = bridge.recentMoves()
        let found = bridge.whereDidItGo(named: "intent.pdf")
        let invalid = bridge.whereDidItGo(named: "Documents/intent.pdf")
        check(
            "I03",
            "tidy, status, history, and lookup expose bounded evidence classes rather than paths or rules",
            tidy.evidence == .completed
                && tidy.movedCount == 1
                && status.evidence == .available
                && status.lifecycle == .fixture
                && recent.evidence == .available
                && recent.entries.count == 1
                && recent.entries.first?.name == "intent.pdf"
                && recent.entries.first?.category == "Docs"
                && found.evidence == .moved
                && found.category == "Docs"
                && invalid.evidence == .invalidQuery,
            "tidy=\(tidy.evidence), recent=\(recent.entries.count), found=\(found.evidence), invalid=\(invalid.evidence)"
        )
    }
}
