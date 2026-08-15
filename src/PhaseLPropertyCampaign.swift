import Foundation

// ============================================================================
// Phase L — bounded hostile property campaign.
//
// This is finite evidence for one fixed seed and fourteen hermetic fixtures;
// it is not a universal proof. Every fixture and the raw evidence file must
// remain below /private/tmp so the campaign cannot reach a live Desktop.
// ============================================================================

enum PhaseLCampaignConfiguration {
    static let seed: UInt64 = 0x4C5F_2026_0814
    static let expectedCaseCount = 14
    static let schema = 1
    static let caseTimeoutMilliseconds = 5_000
    static let temporaryRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
}

enum PhaseLRecordStatus: String, Codable, Equatable {
    case passed
    case failed
    case timedOut
}

struct PhaseLRawRecord: Codable, Equatable {
    let schema: Int
    let id: String
    let seed: UInt64
    let caseIndex: Int
    let caseName: String
    let status: PhaseLRecordStatus
    let checks: Int
    let timeoutMilliseconds: Int
    let detail: String?

    static func readJSONL(from url: URL) throws -> [PhaseLRawRecord] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw PhaseLCampaignError.invalidRawEvidence("raw evidence is not UTF-8")
        }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else {
            throw PhaseLCampaignError.invalidRawEvidence("raw evidence contains no records")
        }
        return try lines.enumerated().map { index, line in
            guard !line.isEmpty else {
                throw PhaseLCampaignError.invalidRawEvidence("empty JSONL line at \(index + 1)")
            }
            do {
                return try JSONDecoder().decode(PhaseLRawRecord.self, from: Data(line.utf8))
            } catch {
                throw PhaseLCampaignError.invalidRawEvidence("invalid JSONL record at \(index + 1): \(error.localizedDescription)")
            }
        }
    }
}

struct PhaseLCampaignResult: Equatable {
    let totalCases: Int
    let passedCases: Int
    let failedCases: Int
    let timedOutCases: Int
}

enum PhaseLCampaignError: LocalizedError {
    case unsafeOutputPath(String)
    case invalidRawEvidence(String)
    case fixtureFailure(String)

    var errorDescription: String? {
        switch self {
        case .unsafeOutputPath(let path):
            return "Phase L output must be beneath /private/tmp: \(path)"
        case .invalidRawEvidence(let reason):
            return "invalid Phase L raw evidence: \(reason)"
        case .fixtureFailure(let reason):
            return "Phase L fixture failure: \(reason)"
        }
    }
}

final class PhaseLCampaign {
    private let outputURL: URL
    private let fm: FileManager

    private final class FixtureState {
        var targetPath: String
        var authorized = true

        init(targetPath: String) {
            self.targetPath = targetPath
        }
    }

    private struct Fixture {
        let sandbox: URL
        let root: URL
        let alternate: URL
        let app: URL
        let state: FixtureState
        let movement: MovementService
        let core: CanonicalApplicationCore
    }

    private struct CaseEvaluation {
        let passed: Bool
        let checks: Int
        let detail: String?
    }

    private let caseNames = [
        "document-route",
        "unknown-inbox-route",
        "collision-preserves-existing-destination",
        "partial-download-is-not-moved",
        "symbolic-link-is-not-followed",
        "directory-routes-as-folder",
        "undo-restores-exact-bytes",
        "paused-core-refuses-movement",
        "target-change-refuses-movement",
        "authorization-refusal-is-nonmutating",
        "tampered-ledger-refuses-undo",
        "unknown-receipt-refuses-undo",
        "screenshot-prefix-is-case-insensitive",
        "receipt-chain-remains-valid-after-multiple-moves"
    ]

    init(outputURL: URL, fm: FileManager = .default) {
        self.outputURL = outputURL.standardizedFileURL
        self.fm = fm
    }

    func run() throws -> PhaseLCampaignResult {
        try validateOutputURL()
        var records = [PhaseLRawRecord]()
        for index in caseNames.indices {
            let started = ProcessInfo.processInfo.systemUptime
            let evaluation: CaseEvaluation
            do {
                evaluation = try executeCase(index)
            } catch {
                evaluation = CaseEvaluation(passed: false, checks: 1, detail: error.localizedDescription)
            }
            let elapsedMilliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            let status: PhaseLRecordStatus
            let detail: String?
            if elapsedMilliseconds > PhaseLCampaignConfiguration.caseTimeoutMilliseconds {
                status = .timedOut
                detail = "case exceeded declared \(PhaseLCampaignConfiguration.caseTimeoutMilliseconds) ms bound"
            } else if evaluation.passed {
                status = .passed
                detail = nil
            } else {
                status = .failed
                detail = evaluation.detail ?? "one or more checks failed"
            }
            records.append(PhaseLRawRecord(
                schema: PhaseLCampaignConfiguration.schema,
                id: caseID(index),
                seed: PhaseLCampaignConfiguration.seed,
                caseIndex: index + 1,
                caseName: caseNames[index],
                status: status,
                checks: max(1, evaluation.checks),
                timeoutMilliseconds: PhaseLCampaignConfiguration.caseTimeoutMilliseconds,
                detail: detail
            ))
        }
        try write(records)
        return PhaseLCampaignResult(
            totalCases: records.count,
            passedCases: records.filter { $0.status == .passed }.count,
            failedCases: records.filter { $0.status == .failed }.count,
            timedOutCases: records.filter { $0.status == .timedOut }.count
        )
    }

    private func validateOutputURL() throws {
        let root = PhaseLCampaignConfiguration.temporaryRoot.path + "/"
        guard outputURL.path.hasPrefix(root) else {
            throw PhaseLCampaignError.unsafeOutputPath(outputURL.path)
        }
    }

    private func write(_ records: [PhaseLRawRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try records.map { record in
            String(decoding: try encoder.encode(record), as: UTF8.self)
        }
        try fm.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: outputURL, options: [.atomic])
    }

    private func caseID(_ index: Int) -> String {
        String(format: "L%02d-%016llX", index + 1, PhaseLCampaignConfiguration.seed)
    }

    private func executeCase(_ index: Int) throws -> CaseEvaluation {
        switch index {
        case 0: return try documentRouteCase(index)
        case 1: return try inboxRouteCase(index)
        case 2: return try collisionCase(index)
        case 3: return try partialDownloadCase(index)
        case 4: return try symbolicLinkCase(index)
        case 5: return try directoryCase(index)
        case 6: return try undoBytesCase(index)
        case 7: return try pauseCase(index)
        case 8: return try targetChangeCase(index)
        case 9: return try authorizationCase(index)
        case 10: return try tamperedLedgerCase(index)
        case 11: return try unknownReceiptCase(index)
        case 12: return try screenshotCase(index)
        case 13: return try ledgerChainCase(index)
        default: throw PhaseLCampaignError.fixtureFailure("unmapped case index \(index)")
        }
    }

    private func fixture(_ index: Int) throws -> Fixture {
        let sandbox = PhaseLCampaignConfiguration.temporaryRoot
            .appendingPathComponent("desktidy-phase-l-\(PhaseLCampaignConfiguration.seed)-\(index + 1)", isDirectory: true)
        if fm.fileExists(atPath: sandbox.path) { try fm.removeItem(at: sandbox) }
        let root = sandbox.appendingPathComponent("watched", isDirectory: true)
        let alternate = sandbox.appendingPathComponent("alternate", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: alternate, withIntermediateDirectories: true)
        try fm.createDirectory(at: app, withIntermediateDirectories: true)

        let state = FixtureState(targetPath: root.path)
        let movement = MovementService(root: root, ledger: ReceiptLedger(appDirectory: app),
                                       moverVersion: DeskTidyVersion.string, log: { _ in })
        let core = CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: app.appendingPathComponent("config.json"),
            targetResolver: {
                .resolved(path: state.targetPath, source: .environment,
                          exists: self.fm.fileExists(atPath: state.targetPath))
            },
            effectiveState: { self.fixtureEffectiveState(root: root, app: app) },
            lifecycleStatus: { .fixture("phase-l") },
            authorize: { _ in state.authorized ? .allowed : .refused("Phase L fixture authority refusal") },
            fm: fm
        )
        return Fixture(sandbox: sandbox, root: root, alternate: alternate, app: app,
                       state: state, movement: movement, core: core)
    }

    private func withFixture(_ index: Int, _ body: (Fixture) throws -> CaseEvaluation) throws -> CaseEvaluation {
        let f = try fixture(index)
        defer { try? fm.removeItem(at: f.sandbox) }
        return try body(f)
    }

    private func fixtureEffectiveState(root: URL, app: URL) -> EffectiveStateReport {
        EffectiveStateReport(
            generatedAt: "phase-l-fixture",
            overall: .pausedNotLoaded,
            overallReason: "hermetic Phase L fixture",
            watchedTarget: root.path,
            watchedTargetCanonical: root.path,
            targetExists: true,
            targetSource: "environment",
            targetResolution: "resolved",
            appDirectory: app.path,
            ledgerPath: app.appendingPathComponent("receipts/ledger.jsonl").path,
            productAgentLoaded: false,
            productAgentState: "notLoaded",
            effectiveMoverLabel: nil,
            effectiveMoverProgram: nil,
            foreignMovers: [],
            ambiguityReason: nil,
            ledger: "absent",
            ledgerReceiptCount: 0,
            suggestionsPresent: false,
            moverVersion: DeskTidyVersion.string
        )
    }

    @discardableResult
    private func settledFile(in root: URL, named name: String, data: Data) throws -> URL {
        let file = root.appendingPathComponent(name)
        guard fm.createFile(atPath: file.path, contents: data) else {
            throw PhaseLCampaignError.fixtureFailure("cannot create \(name)")
        }
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
        return file
    }

    private func settledDirectory(in root: URL, named name: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: directory.path)
        return directory
    }

    private func documentRouteCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let source = try settledFile(in: f.root, named: "report.PDF", data: Data("report".utf8))
            let result = f.core.tidyNow()
            let destination = f.root.appendingPathComponent("\(Config.folderDocuments)/report.PDF")
            return CaseEvaluation(passed: result.moved.count == 1 && !fm.fileExists(atPath: source.path)
                                  && fm.contents(atPath: destination.path) == Data("report".utf8), checks: 3, detail: "document was not moved through the canonical core")
        }
    }

    private func inboxRouteCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let source = try settledFile(in: f.root, named: "unclassified.weird", data: Data("unknown".utf8))
            let result = f.core.tidyNow()
            let destination = f.root.appendingPathComponent("Inbox/unclassified.weird")
            return CaseEvaluation(passed: result.moved.count == 1 && !fm.fileExists(atPath: source.path)
                                  && fm.fileExists(atPath: destination.path), checks: 3, detail: "unknown extension did not use Inbox fallback")
        }
    }

    private func collisionCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let documents = f.root.appendingPathComponent(Config.folderDocuments, isDirectory: true)
            try fm.createDirectory(at: documents, withIntermediateDirectories: true)
            let existing = documents.appendingPathComponent("report.pdf")
            guard fm.createFile(atPath: existing.path, contents: Data("original".utf8)) else {
                throw PhaseLCampaignError.fixtureFailure("cannot create collision destination")
            }
            _ = try settledFile(in: f.root, named: "report.pdf", data: Data("incoming".utf8))
            let receipt = f.core.tidyNow().moved.first
            let actual = receipt.flatMap { $0.finalDestRel ?? $0.plannedDestRel }
                .map { f.root.appendingPathComponent($0) }
            return CaseEvaluation(passed: fm.contents(atPath: existing.path) == Data("original".utf8)
                                  && actual?.path != existing.path
                                  && actual.flatMap { fm.contents(atPath: $0.path) } == Data("incoming".utf8), checks: 3, detail: "collision overwrote or lost an existing destination")
        }
    }

    private func partialDownloadCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let partial = try settledFile(in: f.root, named: "active.crdownload", data: Data("partial".utf8))
            let result = f.core.tidyNow()
            return CaseEvaluation(passed: result.moved.isEmpty && result.failed.isEmpty
                                  && fm.fileExists(atPath: partial.path), checks: 3, detail: "partial download was moved")
        }
    }

    private func symbolicLinkCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let outside = f.sandbox.appendingPathComponent("outside.txt")
            guard fm.createFile(atPath: outside.path, contents: Data("outside".utf8)) else {
                throw PhaseLCampaignError.fixtureFailure("cannot create symbolic-link target")
            }
            let link = f.root.appendingPathComponent("escape.pdf")
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: outside.path)
            let result = f.core.tidyNow()
            return CaseEvaluation(passed: result.moved.isEmpty && fm.fileExists(atPath: link.path)
                                  && fm.contents(atPath: outside.path) == Data("outside".utf8), checks: 3, detail: "symbolic link was followed or moved")
        }
    }

    private func directoryCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let source = f.root.appendingPathComponent("Project", isDirectory: true)
            try fm.createDirectory(at: source, withIntermediateDirectories: true)
            _ = try settledFile(in: source, named: "inside.txt", data: Data("inside".utf8))
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: source.path)
            let result = f.core.tidyNow()
            let destination = f.root.appendingPathComponent("\(Config.folderFolders)/Project/inside.txt")
            return CaseEvaluation(passed: result.moved.count == 1 && !fm.fileExists(atPath: source.path)
                                  && fm.contents(atPath: destination.path) == Data("inside".utf8), checks: 3, detail: "directory did not route through Folders")
        }
    }

    private func undoBytesCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let bytes = Data([0, 1, 2, 0xff, 0x7f, 0x41, 0, 0x42])
            let source = try settledFile(in: f.root, named: "bytes.bin", data: bytes)
            guard let moved = f.core.tidyNow().moved.first else {
                return CaseEvaluation(passed: false, checks: 1, detail: "initial move failed")
            }
            let undo = f.core.undo(receiptID: moved.id)
            return CaseEvaluation(passed: undo.outcome == .completed && fm.contents(atPath: source.path) == bytes
                                  && f.movement.ledger.verifyChain() == nil, checks: 3, detail: "undo did not restore exact bytes with an intact ledger")
        }
    }

    private func pauseCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let source = try settledFile(in: f.root, named: "blocked.pdf", data: Data("blocked".utf8))
            let pause = f.core.pauseIndefinitely()
            let result = f.core.tidyNow()
            return CaseEvaluation(passed: pause.outcome == .completed && result.refusal == .paused
                                  && fm.fileExists(atPath: source.path), checks: 3, detail: "paused core permitted movement")
        }
    }

    private func targetChangeCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let source = try settledFile(in: f.root, named: "mismatch.pdf", data: Data("mismatch".utf8))
            f.state.targetPath = f.alternate.path
            let result = f.core.tidyNow()
            return CaseEvaluation(passed: result.refusal == .targetMismatch && fm.fileExists(atPath: source.path), checks: 2, detail: "target mismatch did not refuse movement")
        }
    }

    private func authorizationCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let source = try settledFile(in: f.root, named: "denied.pdf", data: Data("denied".utf8))
            f.state.authorized = false
            let result = f.core.tidyNow()
            let refused: Bool
            if case .unauthorized = result.refusal { refused = true } else { refused = false }
            return CaseEvaluation(passed: refused && fm.fileExists(atPath: source.path), checks: 2, detail: "authorization refusal permitted movement")
        }
    }

    private func tamperedLedgerCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            _ = try settledFile(in: f.root, named: "tamper.bin", data: Data("tamper".utf8))
            guard let moved = f.core.tidyNow().moved.first,
                  var ledger = fm.contents(atPath: f.movement.ledger.ledgerURL.path) else {
                return CaseEvaluation(passed: false, checks: 1, detail: "initial move or ledger creation failed")
            }
            ledger.append(Data("not-json\n".utf8))
            try ledger.write(to: f.movement.ledger.ledgerURL)
            let undo = f.core.undo(receiptID: moved.id)
            return CaseEvaluation(passed: undo.refusal == .invalidReceipt(moved.id)
                                  && f.movement.ledger.verifyChain() != nil, checks: 2, detail: "tampered ledger was accepted for undo")
        }
    }

    private func unknownReceiptCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            let result = f.core.undo(receiptID: "not-a-receipt")
            return CaseEvaluation(passed: result.refusal == .invalidReceipt("not-a-receipt")
                                  && result.outcome == .failed, checks: 2, detail: "unknown receipt was accepted")
        }
    }

    private func screenshotCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            _ = try settledFile(in: f.root, named: "SCREEN SHOT 2026-08-14.PNG", data: Data("pixels".utf8))
            let receipt = f.core.tidyNow().moved.first
            let destination = receipt?.finalDestRel ?? receipt?.plannedDestRel
            return CaseEvaluation(passed: destination == "\(Config.folderScreenshots)/SCREEN SHOT 2026-08-14.PNG"
                                  && receipt?.ruleID == "prefix:screenshot", checks: 2, detail: "case-insensitive screenshot prefix was not recognized")
        }
    }

    private func ledgerChainCase(_ index: Int) throws -> CaseEvaluation {
        try withFixture(index) { f in
            _ = try settledFile(in: f.root, named: "one.pdf", data: Data("one".utf8))
            _ = try settledFile(in: f.root, named: "two.zip", data: Data("two".utf8))
            _ = try settledFile(in: f.root, named: "three.swift", data: Data("three".utf8))
            let result = f.core.tidyNow()
            let ledger = f.movement.ledger.readAll().receipts
            return CaseEvaluation(passed: result.moved.count == 3 && ledger.count == 3
                                  && ledger.allSatisfy { $0.outcome == "moved" }
                                  && f.movement.ledger.verifyChain() == nil, checks: 4, detail: "multiple canonical moves did not retain a valid receipt chain")
        }
    }
}
