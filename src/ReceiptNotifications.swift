import AppKit
import Foundation
import UserNotifications

// ============================================================================
// Phase F — receipt-derived native notifications.
//
// A notification is best-effort presentation of an already-durable movement
// receipt. The service has no movement capability: it receives receipts only
// from CanonicalApplicationCore after completion, and its sender failure is
// isolated from the completed command.
// ============================================================================

enum ReceiptNotificationAction: String, Equatable {
    case reveal
    case undo
}

struct ReceiptNotificationPayload: Equatable {
    let receiptID: String
    let originalName: String
    let finalName: String
    let destinationCategory: String
    let destinationPath: String
    let actions: [ReceiptNotificationAction]

    init?(receipt: Receipt, undoEligible: Bool) {
        let destination = receipt.finalDestRel ?? receipt.plannedDestRel
        guard receipt.outcome == "moved" || receipt.outcome == "recovered",
              !receipt.id.isEmpty,
              let sourceComponents = Self.components(of: receipt.sourceRel),
              let destinationComponents = Self.components(of: destination),
              let originalName = sourceComponents.last,
              let finalName = destinationComponents.last else {
            return nil
        }

        receiptID = receipt.id
        self.originalName = originalName
        self.finalName = finalName
        destinationCategory = destinationComponents.count > 1 ? destinationComponents[0] : "Watched Folder"
        destinationPath = destination
        actions = undoEligible ? [.reveal, .undo] : [.reveal]
    }

    private static func components(of relativePath: String) -> [String]? {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return components
    }
}

protocol ReceiptNotificationSending: AnyObject {
    func send(_ payload: ReceiptNotificationPayload,
              completion: @escaping (Result<Void, Error>) -> Void)
}

protocol ReceiptNotificationDedupeStore: AnyObject {
    /// Reserves a receipt for delivery. False means it was either delivered or
    /// is currently being delivered by this process.
    func reserve(receiptID: String) -> Bool
    /// Marks a successfully delivered receipt as durable best-effort state.
    func commit(receiptID: String)
    /// Makes a failed delivery retryable.
    func release(receiptID: String)
}

final class InMemoryReceiptNotificationDedupeStore: ReceiptNotificationDedupeStore {
    private var delivered: Set<String> = []
    private var reserved: Set<String> = []
    private let lock = NSLock()

    func reserve(receiptID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !receiptID.isEmpty, !delivered.contains(receiptID), !reserved.contains(receiptID) else {
            return false
        }
        reserved.insert(receiptID)
        return true
    }

    func commit(receiptID: String) {
        lock.lock()
        defer { lock.unlock() }
        reserved.remove(receiptID)
        delivered.insert(receiptID)
    }

    func release(receiptID: String) {
        lock.lock()
        defer { lock.unlock() }
        reserved.remove(receiptID)
    }
}

final class FileReceiptNotificationDedupeStore: ReceiptNotificationDedupeStore {
    private struct Record: Codable {
        let schema: Int
        let receiptIDs: [String]
    }

    private let url: URL
    private let fm: FileManager
    private let lock = NSLock()
    private var loaded = false
    private var delivered: Set<String> = []
    private var reserved: Set<String> = []

    init(receiptsDirectory: URL, fm: FileManager = .default) {
        url = receiptsDirectory.appendingPathComponent("notification-delivery-receipts.json")
        self.fm = fm
    }

    func reserve(receiptID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        guard !receiptID.isEmpty, !delivered.contains(receiptID), !reserved.contains(receiptID) else {
            return false
        }
        reserved.insert(receiptID)
        return true
    }

    func commit(receiptID: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        reserved.remove(receiptID)
        delivered.insert(receiptID)
        persist()
    }

    func release(receiptID: String) {
        lock.lock()
        defer { lock.unlock() }
        reserved.remove(receiptID)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = fm.contents(atPath: url.path),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.schema == 1 else {
            return
        }
        delivered = Set(record.receiptIDs.filter { !$0.isEmpty })
    }

    private func persist() {
        let record = Record(schema: 1, receiptIDs: delivered.sorted())
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

final class ReceiptNotificationService {
    typealias Schedule = (@escaping () -> Void) -> Void

    private let sender: ReceiptNotificationSending
    private let dedupeStore: ReceiptNotificationDedupeStore
    private let undoEligible: (String) -> Bool
    private let schedule: Schedule

    init(sender: ReceiptNotificationSending,
         dedupeStore: ReceiptNotificationDedupeStore,
         undoEligible: @escaping (String) -> Bool,
         schedule: @escaping Schedule = { work in
             DispatchQueue.global(qos: .utility).async(execute: work)
         }) {
        self.sender = sender
        self.dedupeStore = dedupeStore
        self.undoEligible = undoEligible
        self.schedule = schedule
    }

    /// Enqueue only a completed movement receipt. Scheduling keeps notification
    /// delivery out of the command's movement path.
    func enqueue(_ receipt: Receipt) {
        guard receipt.outcome == "moved" || receipt.outcome == "recovered" else { return }
        schedule { [weak self] in
            self?.deliver(receipt)
        }
    }

    private func deliver(_ receipt: Receipt) {
        guard let payload = ReceiptNotificationPayload(
            receipt: receipt,
            undoEligible: undoEligible(receipt.id)
        ),
        dedupeStore.reserve(receiptID: receipt.id) else {
            return
        }
        sender.send(payload) { [weak self] result in
            switch result {
            case .success:
                self?.dedupeStore.commit(receiptID: receipt.id)
            case .failure:
                self?.dedupeStore.release(receiptID: receipt.id)
            }
        }
    }
}

protocol ReceiptNotificationActionHandling: AnyObject {
    func handle(action: ReceiptNotificationAction, receiptID: String)
}

/// The notification delegate has no direct access to MovementService. Both
/// action types first ask the canonical command adapter for the current answer.
final class CanonicalReceiptNotificationActionRouter: ReceiptNotificationActionHandling {
    private let commandAdapter: () -> CanonicalCoreCommandAdapter?
    private let reveal: (URL) -> Void

    init(commandAdapter: @escaping () -> CanonicalCoreCommandAdapter?,
         reveal: @escaping (URL) -> Void) {
        self.commandAdapter = commandAdapter
        self.reveal = reveal
    }

    func handle(action: ReceiptNotificationAction, receiptID: String) {
        guard let adapter = commandAdapter() else { return }
        switch action {
        case .undo:
            _ = adapter.undo(receiptID: receiptID)
        case .reveal:
            guard let destination = adapter.revealDestination(receiptID: receiptID) else { return }
            reveal(destination)
        }
    }
}

enum ReceiptNotificationSenderError: Error {
    case authorizationDenied
}

final class UNUserNotificationCenterReceiptSender: NSObject, ReceiptNotificationSending, UNUserNotificationCenterDelegate {
    static let revealActionIdentifier = "com.desktidy.notification.reveal"
    static let undoActionIdentifier = "com.desktidy.notification.undo"
    static let revealOnlyCategoryIdentifier = "com.desktidy.notification.receipt.reveal"
    static let undoCategoryIdentifier = "com.desktidy.notification.receipt.undo"

    typealias AuthorizationRequest = (UNAuthorizationOptions, @escaping (Bool, Error?) -> Void) -> Void
    typealias RequestAdder = (UNNotificationRequest, @escaping (Error?) -> Void) -> Void

    private let authorizationRequest: AuthorizationRequest
    private let addRequest: RequestAdder
    private let actionHandler: ReceiptNotificationActionHandling

    init(center: UNUserNotificationCenter = .current(),
         actionHandler: ReceiptNotificationActionHandling) {
        authorizationRequest = { options, completion in
            center.requestAuthorization(options: options, completionHandler: completion)
        }
        addRequest = { request, completion in
            center.add(request, withCompletionHandler: completion)
        }
        self.actionHandler = actionHandler
        super.init()
        center.delegate = self
        center.setNotificationCategories(Self.categories)
    }

    init(actionHandler: ReceiptNotificationActionHandling,
         requestAuthorization: @escaping AuthorizationRequest,
         addRequest: @escaping RequestAdder) {
        authorizationRequest = requestAuthorization
        self.addRequest = addRequest
        self.actionHandler = actionHandler
        super.init()
    }

    func send(_ payload: ReceiptNotificationPayload,
              completion: @escaping (Result<Void, Error>) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "DeskTidy moved \(payload.originalName)"
        content.subtitle = payload.destinationCategory
        content.body = payload.finalName == payload.originalName
            ? payload.destinationPath
            : "\(payload.finalName) → \(payload.destinationPath)"
        content.categoryIdentifier = payload.actions.contains(.undo)
            ? Self.undoCategoryIdentifier
            : Self.revealOnlyCategoryIdentifier
        content.userInfo = ["receiptID": payload.receiptID]
        let request = UNNotificationRequest(identifier: payload.receiptID, content: content, trigger: nil)
        authorizationRequest([.alert, .badge, .sound]) { [addRequest] granted, error in
            if let error {
                completion(.failure(error))
            } else if !granted {
                completion(.failure(ReceiptNotificationSenderError.authorizationDenied))
            } else {
                addRequest(request) { error in
                    if let error {
                        completion(.failure(error))
                    } else {
                        completion(.success(()))
                    }
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let receiptID = response.notification.request.content.userInfo["receiptID"] as? String,
              !receiptID.isEmpty else {
            return
        }
        switch response.actionIdentifier {
        case Self.revealActionIdentifier:
            actionHandler.handle(action: .reveal, receiptID: receiptID)
        case Self.undoActionIdentifier:
            actionHandler.handle(action: .undo, receiptID: receiptID)
        default:
            return
        }
    }

    private static var categories: Set<UNNotificationCategory> {
        let reveal = UNNotificationAction(identifier: revealActionIdentifier, title: "Reveal", options: [])
        let undo = UNNotificationAction(identifier: undoActionIdentifier, title: "Undo", options: [])
        return [
            UNNotificationCategory(identifier: revealOnlyCategoryIdentifier, actions: [reveal], intentIdentifiers: []),
            UNNotificationCategory(identifier: undoCategoryIdentifier, actions: [reveal, undo], intentIdentifiers: [])
        ]
    }
}

/// Production-only composition retained by a live core. The bridge weakly
/// references the core so action callbacks can only use its command adapter.
final class ProductionReceiptNotificationBridge {
    private weak var core: CanonicalApplicationCore?
    private let receiptsDirectory: URL

    private lazy var service: ReceiptNotificationService = {
        let router = CanonicalReceiptNotificationActionRouter(
            commandAdapter: { [weak self] in
                guard let core = self?.core else { return nil }
                return CanonicalCoreCommandAdapter(core: core)
            },
            reveal: { destination in
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        )
        let sender = UNUserNotificationCenterReceiptSender(actionHandler: router)
        return ReceiptNotificationService(
            sender: sender,
            dedupeStore: FileReceiptNotificationDedupeStore(receiptsDirectory: receiptsDirectory),
            undoEligible: { [weak self] receiptID in
                self?.core?.isUndoEligible(receiptID: receiptID) ?? false
            }
        )
    }()

    init(receiptsDirectory: URL) {
        self.receiptsDirectory = receiptsDirectory
    }

    func bind(core: CanonicalApplicationCore) {
        self.core = core
    }

    func receive(_ receipt: Receipt) {
        service.enqueue(receipt)
    }
}
