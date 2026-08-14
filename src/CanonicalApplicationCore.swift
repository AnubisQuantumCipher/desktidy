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
    case invalidPauseDuration
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
    case notLoaded(String)
    case unavailable(String)
}

enum CanonicalPauseState: Equatable {
    case running
    case pausedIndefinitely(since: Date)
    case pausedUntil(Date)
    case unreadable(String)

    var isMovementBlocked: Bool {
        switch self {
        case .running: return false
        case .pausedIndefinitely, .pausedUntil, .unreadable: return true
        }
    }
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
    private let lock = NSLock()

    init(receiptsDirectory: URL) {
        url = receiptsDirectory.appendingPathComponent("command-receipts.jsonl")
    }

    func append(_ receipt: CanonicalCommandReceipt) throws {
        lock.lock()
        defer { lock.unlock() }
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
        lock.lock()
        defer { lock.unlock() }
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
    private let configurationStore: NativeConfigurationStore

    private let targetResolver: () -> TargetResolution
    private let effectiveStateProvider: () -> EffectiveStateReport
    private let lifecycleStatusProvider: () -> CanonicalLifecycleStatus
    private let authorize: (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization
    private let emit: (CanonicalCoreEvent) -> Void
    private let movementCompleted: (Receipt) -> Void
    private let fm: FileManager
    private let pauseURL: URL
    private let commandReceipts: CanonicalCommandReceiptLedger
    private let iso: ISO8601DateFormatter
    private let dateNow: () -> Date
    private let monotonicNow: () -> TimeInterval
    private let bootSessionID: () -> String
    private let beforeMove: () -> Void
    private let tidyLock = NSLock()
    private let pauseStateLock = NSLock()

    private enum CommandExecutionFailure: Error {
        case refusal(CanonicalCoreRefusal)
    }
    private struct SweepInterruption: Error {
        let result: (moved: [Receipt], failed: [Receipt], skippedFresh: Int)
        let refusal: CanonicalCoreRefusal
    }


    private struct DurablePauseStateRecord: Codable {
        enum Mode: String, Codable {
            case running
            case pausedIndefinitely
            case pausedUntil
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case schema
            case mode
            case changedAtUnixSeconds
            case durationSeconds
            case expiresAtUnixSeconds
            case monotonicStartedAt
            case bootSessionID
        }

        private struct AnyCodingKey: CodingKey {
            let stringValue: String
            let intValue: Int?

            init?(stringValue: String) {
                self.stringValue = stringValue
                intValue = nil
            }

            init?(intValue: Int) {
                stringValue = String(intValue)
                self.intValue = intValue
            }
        }

        let schema: Int
        let mode: Mode
        let changedAtUnixSeconds: TimeInterval
        let durationSeconds: TimeInterval?
        let expiresAtUnixSeconds: TimeInterval?
        let monotonicStartedAt: TimeInterval?
        let bootSessionID: String?

        init(schema: Int = 1, mode: Mode, changedAtUnixSeconds: TimeInterval,
             durationSeconds: TimeInterval? = nil, expiresAtUnixSeconds: TimeInterval? = nil,
             monotonicStartedAt: TimeInterval? = nil, bootSessionID: String? = nil) {
            self.schema = schema
            self.mode = mode
            self.changedAtUnixSeconds = changedAtUnixSeconds
            self.durationSeconds = durationSeconds
            self.expiresAtUnixSeconds = expiresAtUnixSeconds
            self.monotonicStartedAt = monotonicStartedAt
            self.bootSessionID = bootSessionID
        }

        init(from decoder: Decoder) throws {
            let raw = try decoder.container(keyedBy: AnyCodingKey.self)
            let keys = Set(raw.allKeys.map(\.stringValue))
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let schema = try values.decode(Int.self, forKey: .schema)
            let mode = try values.decode(Mode.self, forKey: .mode)
            let changedAt = try values.decode(TimeInterval.self, forKey: .changedAtUnixSeconds)
            guard schema == 1, changedAt.isFinite else {
                throw DecodingError.dataCorruptedError(forKey: .schema, in: values,
                                                       debugDescription: "unsupported durable pause state")
            }

            self.schema = schema
            self.mode = mode
            self.changedAtUnixSeconds = changedAt
            switch mode {
            case .running, .pausedIndefinitely:
                guard keys == Set(["schema", "mode", "changedAtUnixSeconds"]) else {
                    throw DecodingError.dataCorruptedError(forKey: .mode, in: values,
                                                           debugDescription: "unexpected durable pause fields")
                }
                durationSeconds = nil
                expiresAtUnixSeconds = nil
                monotonicStartedAt = nil
                bootSessionID = nil
            case .pausedUntil:
                guard keys == Set(["schema", "mode", "changedAtUnixSeconds", "durationSeconds",
                                   "expiresAtUnixSeconds", "monotonicStartedAt", "bootSessionID"]) else {
                    throw DecodingError.dataCorruptedError(forKey: .mode, in: values,
                                                           debugDescription: "incomplete durable pause deadline")
                }
                let duration = try values.decode(TimeInterval.self, forKey: .durationSeconds)
                let expiresAt = try values.decode(TimeInterval.self, forKey: .expiresAtUnixSeconds)
                let monotonicStart = try values.decode(TimeInterval.self, forKey: .monotonicStartedAt)
                let boot = try values.decode(String.self, forKey: .bootSessionID)
                guard duration.isFinite, duration > 0, expiresAt.isFinite,
                      monotonicStart.isFinite, !boot.isEmpty else {
                    throw DecodingError.dataCorruptedError(forKey: .durationSeconds, in: values,
                                                           debugDescription: "invalid durable pause deadline")
                }
                durationSeconds = duration
                expiresAtUnixSeconds = expiresAt
                monotonicStartedAt = monotonicStart
                bootSessionID = boot
            }
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(schema, forKey: .schema)
            try values.encode(mode, forKey: .mode)
            try values.encode(changedAtUnixSeconds, forKey: .changedAtUnixSeconds)
            if mode == .pausedUntil {
                try values.encode(durationSeconds, forKey: .durationSeconds)
                try values.encode(expiresAtUnixSeconds, forKey: .expiresAtUnixSeconds)
                try values.encode(monotonicStartedAt, forKey: .monotonicStartedAt)
                try values.encode(bootSessionID, forKey: .bootSessionID)
            }
        }
    }

    init(
        movement: MovementService,
        nativeConfigURL: URL,
        targetResolver: @escaping () -> TargetResolution,
        effectiveState: @escaping () -> EffectiveStateReport,
        lifecycleStatus: @escaping () -> CanonicalLifecycleStatus,
        authorize: @escaping (CanonicalCoreAuthorizationRequest) -> CanonicalCoreAuthorization,
        emit: @escaping (CanonicalCoreEvent) -> Void = { _ in },
        movementCompleted: @escaping (Receipt) -> Void = { _ in },
        fm: FileManager = .default,
        configurationStore: NativeConfigurationStore? = nil,
        dateNow: @escaping () -> Date = { Date() },
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        bootSessionID: @escaping () -> String = { CanonicalApplicationCore.currentBootSessionID() },
        beforeMove: @escaping () -> Void = {}
    ) {
        self.movement = movement
        self.nativeConfigURL = nativeConfigURL
        self.targetResolver = targetResolver
        self.effectiveStateProvider = effectiveState
        self.lifecycleStatusProvider = lifecycleStatus
        self.authorize = authorize
        self.emit = emit
        self.movementCompleted = movementCompleted
        self.fm = fm
        self.configurationStore = configurationStore ?? NativeConfigurationStore(url: nativeConfigURL, fm: fm)
        self.pauseURL = nativeConfigURL.deletingLastPathComponent().appendingPathComponent("pause-state.json")
        self.commandReceipts = CanonicalCommandReceiptLedger(receiptsDirectory: movement.ledger.receiptsDir)
        self.dateNow = dateNow
        self.monotonicNow = monotonicNow
        self.bootSessionID = bootSessionID
        self.beforeMove = beforeMove
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
        let notificationBridge = ProductionReceiptNotificationBridge(receiptsDirectory: movement.ledger.receiptsDir)
        let core = CanonicalApplicationCore(
            movement: movement,
            nativeConfigURL: DeskTidyPaths.nativeConfigURL(),
            targetResolver: { TargetResolver.resolve() },
            effectiveState: { EffectiveState.compute() },
            lifecycleStatus: {
                switch EffectiveState.compute().overall {
                case .runningHealthy: return .active
                case .pausedNotLoaded:
                    return .notLoaded("DeskTidy service is not loaded")
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
            emit: emit,
            movementCompleted: { receipt in notificationBridge.receive(receipt) }
        )
        notificationBridge.bind(core: core)
        return core
    }
    private static func currentBootSessionID() -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        let result = "kern.boottime".withCString {
            sysctlbyname($0, &bootTime, &size, nil, 0)
        }
        guard result == 0 else { return "unavailable" }
        return "\(bootTime.tv_sec).\(bootTime.tv_usec)"
    }


    // MARK: Read APIs

    func effectiveState() -> CanonicalEffectiveState {
        CanonicalEffectiveState(effective: effectiveStateProvider(), isPaused: pauseState().isMovementBlocked)
    }

    func pauseState() -> CanonicalPauseState {
        pauseStateLock.lock()
        defer { pauseStateLock.unlock() }
        return readPauseState()
    }

    func target() -> TargetResolution { targetResolver() }

    /// Typed configuration read for native UI/settings consumers. This is a
    /// read-only operation unless a caller explicitly asks the store to migrate.
    func configuration() -> NativeConfigurationStoreResult {
        configurationStore.load()
    }

    func configurationReceipts() -> [NativeConfigurationOperationReceipt] {
        configurationStore.receipts()
    }

    func targetConfiguration() -> NativeConfigParser.Outcome? {
        guard fm.fileExists(atPath: nativeConfigURL.path) else { return nil }
        let result = configurationStore.load()
        if let configuration = result.configuration { return .ok(target: configuration.target) }
        return .failed(result.failure ?? "native config is unreadable")
    }

    func receiptsDirectory() -> URL { movement.ledger.receiptsDir }

    func diagnostic() -> String { EffectiveState.diagnostic(effectiveState().effective) }

    func installationStatus() -> CanonicalLifecycleStatus { lifecycleStatusProvider() }

    func history() -> CanonicalMovementHistory {
        let result = movement.ledger.readAll()
        return CanonicalMovementHistory(receipts: result.receipts, malformedLines: result.malformedLines)
    }

    func commandHistory() -> [CanonicalCommandReceipt] { commandReceipts.readAll() }

    /// Notification presentation reads this immediately before delivery so an
    /// Undo button is omitted when a later receipt or filesystem change made
    /// the original movement stale.
    func isUndoEligible(receiptID: String) -> Bool {
        let receipts = history().receipts
        guard let original = receipts.last(where: { $0.id == receiptID }) else { return false }
        return isUndoEligible(original, in: receipts)
    }

    /// Reveal is resolved from the receipt through the canonical root, not from
    /// untrusted notification content. The caller owns Finder presentation.
    func revealDestination(receiptID: String) -> URL? {
        guard let receipt = history().receipts.last(where: { $0.id == receiptID }),
              receipt.outcome == "moved" || receipt.outcome == "recovered" else {
            return nil
        }
        let relative = receipt.finalDestRel ?? receipt.plannedDestRel
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let destination = movement.root.appendingPathComponent(relative)
        guard fm.fileExists(atPath: destination.path) else { return nil }
        return destination
    }

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
            let currentConfiguration = self.configurationStore.load().configuration
                ?? NativeConfiguration.defaultV2(target: requested)
            let saved = self.configurationStore.save(currentConfiguration.withTarget(requested))
            guard saved.configuration != nil else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    func pause() -> CanonicalCommandResult {
        pauseIndefinitely()
    }

    func pauseIndefinitely() -> CanonicalCommandResult {
        switch readyForTarget() {
        case .failure(let refusal):
            return refused(command: .pause, reason: refusal)
        case .success(let target):
            return execute(command: .pause, currentTarget: target) {
                self.pauseStateLock.lock()
                defer { self.pauseStateLock.unlock() }
                try self.writePauseState(DurablePauseStateRecord(
                    mode: .pausedIndefinitely,
                    changedAtUnixSeconds: self.dateNow().timeIntervalSince1970
                ))
            }
        }
    }

    func pause(for duration: TimeInterval) -> CanonicalCommandResult {
        guard duration.isFinite, duration > 0 else {
            return refused(command: .pause, reason: .invalidPauseDuration)
        }
        switch readyForTarget() {
        case .failure(let refusal):
            return refused(command: .pause, reason: refusal)
        case .success(let target):
            return execute(command: .pause, currentTarget: target) {
                let changedAt = self.dateNow().timeIntervalSince1970
                self.pauseStateLock.lock()
                defer { self.pauseStateLock.unlock() }
                try self.writePauseState(DurablePauseStateRecord(
                    mode: .pausedUntil,
                    changedAtUnixSeconds: changedAt,
                    durationSeconds: duration,
                    expiresAtUnixSeconds: changedAt + duration,
                    monotonicStartedAt: self.monotonicNow(),
                    bootSessionID: self.bootSessionID()
                ))
            }
        }
    }

    func resume() -> CanonicalCommandResult {
        switch readyForTarget() {
        case .failure(let refusal):
            return refused(command: .resume, reason: refusal)
        case .success(let target):
            return execute(command: .resume, currentTarget: target) {
                self.pauseStateLock.lock()
                defer { self.pauseStateLock.unlock() }
                try self.writePauseState(DurablePauseStateRecord(
                    mode: .running,
                    changedAtUnixSeconds: self.dateNow().timeIntervalSince1970
                ))
            }
        }
    }

    func tidyNow() -> CanonicalTidyNowResult {
        tidyLock.lock()
        defer { tidyLock.unlock() }
        switch readyForMovement() {
        case .failure(let refusal):
            _ = refused(command: .tidyNow, reason: refusal)
            return CanonicalTidyNowResult(moved: [], failed: [], skippedFresh: 0, refusal: refusal, receiptID: nil)
        case .success(let target):
            var sweepResult = (moved: [Receipt](), failed: [Receipt](), skippedFresh: 0)
            let commandResult = execute(command: .tidyNow, currentTarget: target) {
                try self.requireMovementReady(expectedTarget: target)
                _ = self.movement.startupReconcile()
                try self.requireMovementReady(expectedTarget: target)
                do {
                    sweepResult = try self.sweep(target: URL(fileURLWithPath: target, isDirectory: true),
                                                 expectedTarget: target)
                } catch let interruption as SweepInterruption {
                    sweepResult = interruption.result
                    throw CommandExecutionFailure.refusal(interruption.refusal)
                }
            }
            return CanonicalTidyNowResult(moved: sweepResult.moved, failed: sweepResult.failed,
                                          skippedFresh: sweepResult.skippedFresh,
                                          refusal: commandResult.refusal,
                                          receiptID: commandResult.receiptID)
        }
    }

    func undo(receiptID: String) -> CanonicalCommandResult {
        switch readyForMovement() {
        case .failure(let refusal):
            return refused(command: .undo, reason: refusal)
        case .success(let target):
            let receipts = history().receipts
            guard let original = receipts.last(where: { $0.id == receiptID }),
                  isUndoEligible(original, in: receipts) else {
                return refused(command: .undo, reason: .invalidReceipt(receiptID))
            }
            var moved: Receipt?
            let result = execute(command: .undo, currentTarget: target) {
                self.pauseStateLock.lock()
                defer { self.pauseStateLock.unlock() }
                try self.requireMovementReadyWhileLocked(expectedTarget: target)
                moved = self.movement.undo(receipt: original)
                guard moved?.outcome == "moved" else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            if result.outcome == .completed, let moved {
                emit(CanonicalCoreEvent(kind: .movementCompleted, command: .undo,
                                        receiptID: moved.id,
                                        message: "undo completed for \(original.sourceRel)"))
                if history().receipts.contains(where: { $0.id == moved.id && ($0.outcome == "moved" || $0.outcome == "recovered") }) {
                    movementCompleted(moved)
                }
            }
            return result
        }
    }

    // MARK: Command execution

    private func execute(command: CanonicalCoreCommand, currentTarget: String?, requestedTarget: String? = nil,
                         body: () throws -> Void) -> CanonicalCommandResult {
        let request = CanonicalCoreAuthorizationRequest(command: command, currentTarget: currentTarget,
                                                        requestedTarget: requestedTarget)
        let authorization = authorize(request)
        guard case .allowed = authorization else {
            let refusal: CanonicalCoreRefusal
            if case .refused(let reason) = authorization { refusal = .unauthorized(reason) }
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
            let commandRefusal: CanonicalCoreRefusal?
            if let failure = error as? CommandExecutionFailure,
               case .refusal(let refusal) = failure {
                commandRefusal = refusal
            } else {
                commandRefusal = nil
            }
            let detail = commandRefusal.map(refusalText) ?? error.localizedDescription
            let failed = CanonicalCommandReceipt(schema: 1, id: receiptID, command: command,
                                                 outcome: .failed, occurredAt: now(), detail: detail)
            try? commandReceipts.append(failed)
            if let commandRefusal {
                emit(CanonicalCoreEvent(kind: .commandRefused, command: command, receiptID: receiptID,
                                        message: refusalText(commandRefusal)))
            }
            return CanonicalCommandResult(command: command, outcome: .failed,
                                          refusal: commandRefusal, receiptID: receiptID)
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

    private func readyForMovement() -> Result<String, CanonicalCoreRefusal> {
        if pauseState().isMovementBlocked { return .failure(.paused) }
        return readyForTarget()
    }

    private func readyForTarget() -> Result<String, CanonicalCoreRefusal> {
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

    private func requireMovementReady(expectedTarget: String) throws {
        pauseStateLock.lock()
        defer { pauseStateLock.unlock() }
        try requireMovementReadyWhileLocked(expectedTarget: expectedTarget)
    }

    private func requireMovementReadyWhileLocked(expectedTarget: String) throws {
        guard !readPauseState().isMovementBlocked else {
            throw CommandExecutionFailure.refusal(.paused)
        }
        switch readyForTarget() {
        case .failure(let refusal):
            throw CommandExecutionFailure.refusal(refusal)
        case .success(let current):
            guard AuthorityGuard.canonicalize(current) == AuthorityGuard.canonicalize(expectedTarget) else {
                throw CommandExecutionFailure.refusal(.targetMismatch)
            }
        }
    }

    private func readPauseState() -> CanonicalPauseState {
        if (try? fm.destinationOfSymbolicLink(atPath: pauseURL.path)) != nil {
            return .unreadable("pause state is a symbolic link")
        }
        guard fm.fileExists(atPath: pauseURL.path) else { return .running }
        guard let data = fm.contents(atPath: pauseURL.path) else {
            return .unreadable("pause state cannot be read")
        }
        do {
            let record = try JSONDecoder().decode(DurablePauseStateRecord.self, from: data)
            switch record.mode {
            case .running:
                return .running
            case .pausedIndefinitely:
                return .pausedIndefinitely(since: Date(timeIntervalSince1970: record.changedAtUnixSeconds))
            case .pausedUntil:
                guard let duration = record.durationSeconds,
                      let expiresAt = record.expiresAtUnixSeconds,
                      let monotonicStartedAt = record.monotonicStartedAt,
                      let recordBootSessionID = record.bootSessionID else {
                    return .unreadable("bounded pause is incomplete")
                }
                if dateNow().timeIntervalSince1970 >= expiresAt {
                    return .running
                }
                if recordBootSessionID == bootSessionID(),
                   monotonicNow() >= monotonicStartedAt + duration {
                    return .running
                }
                return .pausedUntil(Date(timeIntervalSince1970: expiresAt))
            }
        } catch {
            return .unreadable("pause state is unreadable: \(error.localizedDescription)")
        }
    }

    private func writePauseState(_ state: DurablePauseStateRecord) throws {
        try fm.createDirectory(at: pauseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: pauseURL, options: [.atomic])
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

    private func sweep(target: URL, expectedTarget: String) throws
        -> (moved: [Receipt], failed: [Receipt], skippedFresh: Int) {
        try requireMovementReady(expectedTarget: expectedTarget)
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
            beforeMove()
            pauseStateLock.lock()
            let receipt: Receipt?
            do {
                try requireMovementReadyWhileLocked(expectedTarget: expectedTarget)
                receipt = movement.perform(source: item, category: route.category, ruleID: route.ruleID,
                                           settleMTime: modified, settleAge: age)
            } catch let failure as CommandExecutionFailure {
                pauseStateLock.unlock()
                let refusal: CanonicalCoreRefusal
                switch failure {
                case .refusal(let value):
                    refusal = value
                }
                throw SweepInterruption(
                    result: (moved: moved, failed: failed, skippedFresh: skippedFresh),
                    refusal: refusal
                )
            } catch {
                pauseStateLock.unlock()
                throw error
            }
            pauseStateLock.unlock()
            guard let receipt else { continue }
            if receipt.outcome == "moved" {
                moved.append(receipt)
                emit(CanonicalCoreEvent(kind: .movementCompleted, command: .tidyNow,
                                        receiptID: receipt.id,
                                        message: "moved \(receipt.sourceRel) to \(receipt.finalDestRel ?? receipt.plannedDestRel)"))
                if history().receipts.contains(where: { $0.id == receipt.id && ($0.outcome == "moved" || $0.outcome == "recovered") }) {
                    movementCompleted(receipt)
                }
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

    private func isUndoEligible(_ original: Receipt, in receipts: [Receipt]) -> Bool {
        guard !receipts.contains(where: {
            $0.reversesReceiptID == original.id
                && ($0.outcome == "moved" || $0.outcome == "recovered")
        }) else {
            return false
        }
        return movement.canUndo(receipt: original)
    }

    private func refusalText(_ refusal: CanonicalCoreRefusal) -> String {
        switch refusal {
        case .invalidTargetConfiguration: return "target configuration is invalid"
        case .unresolvedTarget(let reason): return "target is unresolved: \(reason)"
        case .targetMismatch: return "resolved target differs from the movement root"
        case .targetUnavailable: return "resolved target is unavailable"
        case .paused: return "DeskTidy is paused"
        case .invalidPauseDuration: return "pause duration must be finite and greater than zero"
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

    func undo(receiptID: String) -> CanonicalCommandResult {
        core.undo(receiptID: receiptID)
    }

    func revealDestination(receiptID: String) -> URL? {
        core.revealDestination(receiptID: receiptID)
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
