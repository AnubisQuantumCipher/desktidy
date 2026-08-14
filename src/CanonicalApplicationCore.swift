import Darwin
import Foundation

// ============================================================================
//  Phase C — canonical application service.
//
//  All product clients issue these typed commands.  This type owns target and
//  effective-state reads, configuration mutation, pause state, receipt/history
//  queries, notification event production, and every user-file operation.  A
//  user-file operation always calls the supplied MovementService; it never
//  implements a second mover or destination resolver.
// ============================================================================

enum CanonicalCoreCommand: String, Codable, Equatable {
    case setTarget
    case pause
    case resume
    case tidyNow
    case undo
}

enum CanonicalCoreAuthorization: Equatable {
    case allowed
    case refused(String)
}

struct CanonicalCoreAuthorizationRequest: Equatable {
    let command: CanonicalCoreCommand
    let currentTarget: String?
    let requestedTarget: String?
}

enum CanonicalCoreRefusal: Error, Equatable {
    case invalidTargetConfiguration
    case unresolvedTarget(String)
    case targetMismatch
    case targetUnavailable
    case paused
    case unauthorized(String)
    case invalidTarget(String)
    case invalidReceipt(String)
    case receiptUnavailable
}

enum CanonicalCommandOutcome: String, Codable, Equatable {
    case prepared
    case completed
    case failed
}

struct CanonicalCommandReceipt: Codable, Equatable {
    let schema: Int
    let id: String
    let command: CanonicalCoreCommand
    let outcome: CanonicalCommandOutcome
    let occurredAt: String
    let detail: String?
}

enum CanonicalCoreEventKind: String, Equatable {
    case commandCompleted
    case commandRefused
    case movementCompleted
}

struct CanonicalCoreEvent: Equatable {
    let kind: CanonicalCoreEventKind
    let command: CanonicalCoreCommand
    let receiptID: String?
    let message: String
}

enum CanonicalLifecycleStatus: Equatable {
    case fixture(String)
    case active
    case paused
    case unavailable(String)
}

struct CanonicalEffectiveState {
    let effective: EffectiveStateReport
    let isPaused: Bool
}

struct CanonicalMovementHistory {
    let receipts: [Receipt]
    let malformedLines: Int
}

struct CanonicalWhereDidItGo {
    let receipt: Receipt
    let destination: String
}

struct CanonicalCommandResult {
    let command: CanonicalCoreCommand
    let outcome: CanonicalCommandOutcome
    let refusal: CanonicalCoreRefusal?
    let receiptID: String?
}

struct CanonicalTidyNowResult {
    let moved: [Receipt]
    let failed: [Receipt]
    let skippedFresh: Int
    let refusal: CanonicalCoreRefusal?
    let receiptID: String?
}

struct CanonicalCommandReceiptLedger {
    let url: URL
    private let fm = FileManager.default

    init(receiptsDirectory: URL) {
        url = receiptsDirectory.appendingPathComponent("command-receipts.jsonl")
    }

    func append(_ receipt: CanonicalCommandReceipt) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let line = try encoder.encode(receipt) + Data("\n".utf8)
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    func readAll() -> [CanonicalCommandReceipt] {
        guard let data = fm.contents(atPath: url.path),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap {
            try? JSONDecoder().decode(CanonicalCommandReceipt.self, from: Data($0.utf8))
        }
    }
}

final class CanonicalApplicationCore {
    let movement: MovementService

    private let nativeConfigURL: URL
    private let targetResolver: () -> TargetResolution
    private let effectiveStateProvider: () -> EffectiveStateReport
    private let lifecycleStatusProvider: () -> CanonicalLifecycleStatus
    private let authorize: (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization
    private let emit: (CanonicalCoreEvent) -> Void
    private let fm: FileManager
    private let pauseURL: URL
    private let commandReceipts: CanonicalCommandReceiptLedger
    private let iso: ISO8601DateFormatter

    init(
        movement: MovementService,
        nativeConfigURL: URL,
        targetResolver: @escaping () -> TargetResolution,
        effectiveState: @escaping () -> EffectiveStateReport,
        lifecycleStatus: @escaping () -> CanonicalLifecycleStatus,
        authorize: @escaping (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization,
        emit: @escaping (CanonicalCoreEvent) -> Void = { _ in },
        fm: FileManager = .default
    ) {
        self.movement = movement
        self.nativeConfigURL = nativeConfigURL
        self.targetResolver = targetResolver
        self.effectiveStateProvider = effectiveState
        self.lifecycleStatusProvider = lifecycleStatus
        self.authorize = authorize
        self.emit = emit
        self.fm = fm
        self.pauseURL = nativeConfigURL.deletingLastPathComponent().appendingPathComponent("pause-state.json")
        self.commandReceipts = CanonicalCommandReceiptLedger(receiptsDirectory: movement.ledger.receiptsDir)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.iso = formatter
    }

    /// Production construction is deliberately side-effect free.  It creates
    /// no directories and does not contact ServiceManagement; authorization is
    /// evaluated immediately before a mutating command.
    static func live(log: @escaping (String) -> Void = { _ in },
                     emit: @escaping (CanonicalCoreEvent) -> Void = { _ in }) -> CanonicalApplicationCore {
        let resolution = TargetResolver.resolve()
        let appDirectory = DeskTidyPaths.appDirectory()
        let target: URL
        switch resolution {
        case .resolved(let path, _, _):
            target = URL(fileURLWithPath: path, isDirectory: true)
        case .invalid:
            target = appDirectory.appendingPathComponent(".unresolved-target", isDirectory: true)
        }
        let movement = MovementService(
            root: target,
            ledger: ReceiptLedger(appDirectory: appDirectory),
            moverVersion: DeskTidyVersion.string,
            log: log
        )
        return CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: DeskTidyPaths.nativeConfigURL(),
            targetResolver: { TargetResolver.resolve() },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: {
                switch EffectiveState.compute().overall {
                case .runningHealthy: return .active
                case .pausedNotLoaded: return .paused
                case .foreignConflict, .degradedLedger, .ambiguous:
                    return .unavailable(EffectiveState.compute().overallReason)
                }
            },
            authorize: { request in
                var paths = [String]()
                if let current = request.currentTarget { paths.append(current) }
                if let requested = request.requestedTarget { paths.append(requested) }
                for path in Set(paths) {
                    switch AuthorityGuard().evaluate(rootPath: path) {
                    case .sole, .soleWithStale:
                        continue
                    case .conflict(let movers):
                        return .refused("another movement authority owns \(path): \(movers.map(\.label).joined(separator: ", "))")
                    case .ambiguous(let reason, _):
                        return .refused("movement authority is unprovable for \(path): \(reason)")
                    }
                }
                return .allowed
            },
            emit: emit
        )
    }

    // MARK: Read APIs

    func effectiveState() -> CanonicalEffectiveState {
        CanonicalEffectiveState(effective: effectiveStateProvider(), isPaused: isPaused())
    }

    func target() -> TargetResolution { targetResolver() }

    func targetConfiguration() -> NativeConfigParser.Outcome? {
        guard let data = fm.contents(atPath: nativeConfigURL.path) else { return nil }
        return NativeConfigParser.parse(data)
    }

    func installationStatus() -> CanonicalLifecycleStatus { lifecycleStatusProvider() }

    func history() -> CanonicalMovementHistory {
        let result = movement.ledger.readAll()
        return CanonicalMovementHistory(receipts: result.receipts, malformedLines: result.malformedLines)
    }

    func commandHistory() -> [CanonicalCommandReceipt] { commandReceipts.readAll() }

    func whereDidItGo(named name: String) -> CanonicalWhereDidItGo? {
        guard !name.isEmpty else { return nil }
        for receipt in history().receipts.reversed() {
            let source = URL(fileURLWithPath: receipt.sourceRel).lastPathComponent
            let destination = (receipt.finalDestRel ?? receipt.plannedDestRel)
            let destinationName = URL(fileURLWithPath: destination).lastPathComponent
            if source == name || destinationName == name {
                return CanonicalWhereDidItGo(receipt: receipt, destination: destination)
            }
        }
        return nil
    }

    // MARK: Mutating commands

    func setTarget(_ path: String) -> CanonicalCommandResult {
        if case .failed = targetConfiguration() {
            return refused(command: .setTarget, reason: .invalidTargetConfiguration)
        }
        let standardized = TargetResolver.standardize(path)
        var isDirectory: ObjCBool = false
        guard !standardized.isEmpty,
              fm.fileExists(atPath: standardized, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return refused(command: .setTarget, reason: .invalidTarget(path))
        }
        let requested = AuthorityGuard.canonicalize(standardized).path
        let current = currentResolvedTargetPath()
        return execute(command: .setTarget, currentTarget: current, requestedTarget: requested) {
            let object: [String: Any] = ["schema": TargetResolver.nativeSchema, "target": requested]
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try self.fm.createDirectory(at: self.nativeConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: self.nativeConfigURL, options: [.atomic])
            try self.fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: self.nativeConfigURL.path)
            try self.sync(self.nativeConfigURL)
            try self.sync(self.nativeConfigURL.deletingLastPathComponent())
        }
    }

    func pause() -> CanonicalCommandResult {
        execute(command: .pause, currentTarget: currentResolvedTargetPath()) {
            try self.writePauseState(true)
        }
    }

    func resume() -> CanonicalCommandResult {
        execute(command: .resume, currentTarget: currentResolvedTargetPath()) {
            try self.writePauseState(false)
        }
    }

    func tidyNow() -> CanonicalTidyNowResult {
        switch readyForMovement(command: .tidyNow) {
        case .failure(let refusal):
            _ = refused(command: .tidyNow, reason: refusal)
            return CanonicalTidyNowResult(moved: [], failed: [], skippedFresh: 0, refusal: refusal, receiptID: nil)
        case .success(let target):
            let commandResult = execute(command: .tidyNow, currentTarget: target) {
                _ = self.movement.startupReconcile()
            }
            guard commandResult.outcome == .completed else {
                return CanonicalTidyNowResult(moved: [], failed: [], skippedFresh: 0,
                                              refusal: commandResult.refusal, receiptID: commandResult.receiptID)
            }
            let sweep = sweep(target: URL(fileURLWithPath: target, isDirectory: true))
            return CanonicalTidyNowResult(moved: sweep.moved, failed: sweep.failed,
                                          skippedFresh: sweep.skippedFresh, refusal: nil,
                                          receiptID: commandResult.receiptID)
        }
    }

    func undo(receiptID: String) -> CanonicalCommandResult {
        switch readyForMovement(command: .undo) {
        case .failure(let refusal):
            return refused(command: .undo, reason: refusal)
        case .success(let target):
            let receipts = history().receipts
            guard let original = receipts.last(where: { $0.id == receiptID }),
                  original.undoEligible,
                  (original.outcome == "moved" || original.outcome == "recovered"),
                  !receipts.contains(where: {
                      $0.reversesReceiptID == receiptID
                          && ($0.outcome == "moved" || $0.outcome == "recovered")
                  }) else {
                return refused(command: .undo, reason: .invalidReceipt(receiptID))
            }
            var moved: Receipt?
            let result = execute(command: .undo, currentTarget: target) {
                moved = self.movement.undo(receipt: original)
                guard moved?.outcome == "moved" else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            if result.outcome == .completed, let moved {
                emit(CanonicalCoreEvent(kind: .movementCompleted, command: .undo,
                                        receiptID: moved.id,
                                        message: "undo completed for \(original.sourceRel)"))
            }
            return result
        }
    }

    // MARK: Command execution

    private func execute(command: CanonicalCoreCommand, currentTarget: String?, requestedTarget: String? = nil,
                         body: () throws -> Void) -> CanonicalCommandResult {
        let request = CanonicalCoreAuthorizationRequest(command: command, currentTarget: currentTarget,
                                                        requestedTarget: requestedTarget)
        guard case .allowed = authorize(request) else {
            let refusal: CanonicalCoreRefusal
            if case .refused(let reason) = authorize(request) { refusal = .unauthorized(reason) }
            else { refusal = .unauthorized("authorization was not granted") }
            return refused(command: command, reason: refusal)
        }

        let receiptID = UUID().uuidString
        let prepared = CanonicalCommandReceipt(schema: 1, id: receiptID, command: command,
                                               outcome: .prepared, occurredAt: now(), detail: nil)
        do {
            try commandReceipts.append(prepared)
        } catch {
            return refused(command: command, reason: .receiptUnavailable)
        }

        do {
            try body()
        } catch {
            let failed = CanonicalCommandReceipt(schema: 1, id: receiptID, command: command,
                                                 outcome: .failed, occurredAt: now(),
                                                 detail: error.localizedDescription)
            try? commandReceipts.append(failed)
            return CanonicalCommandResult(command: command, outcome: .failed,
                                          refusal: nil, receiptID: receiptID)
        }

        let completed = CanonicalCommandReceipt(schema: 1, id: receiptID, command: command,
                                                outcome: .completed, occurredAt: now(), detail: nil)
        try? commandReceipts.append(completed)
        emit(CanonicalCoreEvent(kind: .commandCompleted, command: command, receiptID: receiptID,
                                message: "\(command.rawValue) completed"))
        return CanonicalCommandResult(command: command, outcome: .completed, refusal: nil, receiptID: receiptID)
    }

    private func refused(command: CanonicalCoreCommand, reason: CanonicalCoreRefusal) -> CanonicalCommandResult {
        emit(CanonicalCoreEvent(kind: .commandRefused, command: command, receiptID: nil,
                                message: refusalText(reason)))
        return CanonicalCommandResult(command: command, outcome: .failed, refusal: reason, receiptID: nil)
    }

    private func readyForMovement(command: CanonicalCoreCommand) -> Result<String, CanonicalCoreRefusal> {
        if isPaused() { return .failure(.paused) }
        switch targetResolver() {
        case .invalid(let reason, let source, _):
            if source == .nativeConfig { return .failure(.invalidTargetConfiguration) }
            return .failure(.unresolvedTarget(reason))
        case .resolved(let path, _, let exists):
            guard exists else { return .failure(.targetUnavailable) }
            guard AuthorityGuard.canonicalize(path) == movement.rootCanonical else {
                return .failure(.targetMismatch)
            }
            return .success(path)
        }
    }

    private func currentResolvedTargetPath() -> String? {
        if case .resolved(let path, _, let exists) = targetResolver(), exists { return path }
        return nil
    }

    private func isPaused() -> Bool {
        guard let data = fm.contents(atPath: pauseURL.path),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text == "paused\n" || text != "running\n"
    }

    private func writePauseState(_ paused: Bool) throws {
        try fm.createDirectory(at: pauseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data((paused ? "paused\n" : "running\n").utf8)
        try data.write(to: pauseURL, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pauseURL.path)
        try sync(pauseURL)
        try sync(pauseURL.deletingLastPathComponent())
    }

    private func sync(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }

    private func sweep(target: URL) -> (moved: [Receipt], failed: [Receipt], skippedFresh: Int) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(at: target, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            return ([], [], 0)
        }

        let reserved = Set(Category.allCases.map(\.folderName))
        var moved: [Receipt] = []
        var failed: [Receipt] = []
        var skippedFresh = 0
        for item in items {
            let name = item.lastPathComponent
            guard !reserved.contains(name), !shouldSkipPartial(name) else { continue }
            guard let values = try? item.resourceValues(forKeys: keys), values.isSymbolicLink != true else { continue }
            let modified = values.contentModificationDate ?? Date()
            let age = Date().timeIntervalSince(modified)
            guard age >= Config.settleSeconds else { skippedFresh += 1; continue }
            let route = classify(name: name, isDirectory: values.isDirectory == true)
            guard let receipt = movement.perform(source: item, category: route.category, ruleID: route.ruleID,
                                                 settleMTime: modified, settleAge: age) else { continue }
            if receipt.outcome == "moved" {
                moved.append(receipt)
                emit(CanonicalCoreEvent(kind: .movementCompleted, command: .tidyNow,
                                        receiptID: receipt.id,
                                        message: "moved \(receipt.sourceRel) to \(receipt.finalDestRel ?? receipt.plannedDestRel)"))
            } else {
                failed.append(receipt)
            }
        }
        return (moved, failed, skippedFresh)
    }

    private func classify(name: String, isDirectory: Bool) -> (category: Category, ruleID: String) {
        if isDirectory { return (.folders, "dir") }
        let lower = name.lowercased()
        if lower.hasPrefix("screenshot ") || lower.hasPrefix("screen shot ") { return (.screenshots, "prefix:screenshot") }
        if lower.hasPrefix("screen recording ") { return (.videos, "prefix:screen-recording") }
        let ext = (name as NSString).pathExtension.lowercased()
        if Config.imageExts.contains(ext) { return (.images, "ext:\(ext)") }
        if Config.videoExts.contains(ext) { return (.videos, "ext:\(ext)") }
        if Config.audioExts.contains(ext) { return (.audio, "ext:\(ext)") }
        if Config.archiveExts.contains(ext) { return (.archives, "ext:\(ext)") }
        if Config.codeExts.contains(ext) { return (.code, "ext:\(ext)") }
        if Config.documentExts.contains(ext) { return (.documents, "ext:\(ext)") }
        return (.inbox, "fallback:inbox")
    }

    private func shouldSkipPartial(_ name: String) -> Bool {
        let lower = name.lowercased()
        return [".crdownload", ".part", ".download", ".partial", ".tmp"].contains { lower.hasSuffix($0) }
    }

    private func now() -> String { iso.string(from: Date()) }

    private func refusalText(_ refusal: CanonicalCoreRefusal) -> String {
        switch refusal {
        case .invalidTargetConfiguration: return "target configuration is invalid"
        case .unresolvedTarget(let reason): return "target is unresolved: \(reason)"
        case .targetMismatch: return "resolved target differs from the movement root"
        case .targetUnavailable: return "resolved target is unavailable"
        case .paused: return "DeskTidy is paused"
        case .unauthorized(let reason): return "not authorized: \(reason)"
        case .invalidTarget(let path): return "invalid target: \(path)"
        case .invalidReceipt(let id): return "receipt is not undo eligible: \(id)"
        case .receiptUnavailable: return "command receipt storage is unavailable"
        }
    }
}

// The only adapter future App Intents or notification handlers need.  It owns
// no file-system or movement implementation and can only dispatch core commands.
struct CanonicalCoreCommandAdapter {
    let core: CanonicalApplicationCore

    init(core: CanonicalApplicationCore) {
        self.core = core
    }

    func execute(_ command: CanonicalCoreCommand) -> CanonicalAdapterResult {
        switch command {
        case .tidyNow:
            return CanonicalAdapterResult(tidyNow: core.tidyNow(), command: nil)
        case .pause:
            return CanonicalAdapterResult(tidyNow: nil, command: core.pause())
        case .resume:
            return CanonicalAdapterResult(tidyNow: nil, command: core.resume())
        case .setTarget, .undo:
            return CanonicalAdapterResult(tidyNow: nil,
                                          command: CanonicalCommandResult(command: command, outcome: .failed,
                                                                          refusal: .invalidReceipt("argument required"), receiptID: nil))
        }
    }
}

struct CanonicalAdapterResult {
    let tidyNow: CanonicalTidyNowResult?
    let command: CanonicalCommandResult?
}
