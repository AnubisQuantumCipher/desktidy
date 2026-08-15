import Foundation

// ============================================================================
// Phase H — bounded, ledger-derived history and Where Did It Go queries.
// This service never caches receipt data: each query validates the current
// ledger chain before reconstructing a result.
// ============================================================================

enum CanonicalHistoryIntegrity: Equatable {
    case valid
    case degraded(String)
}

enum CanonicalHistoryLiveStatus: Equatable {
    case present
    case missing
    case changed
    case unknown
    case invalidDestination
}

struct CanonicalHistoryEntry {
    let receipt: Receipt
    let originalName: String?
    let finalName: String?
    let category: String?
    let timestamp: String?
    let mover: String?
    let liveStatus: CanonicalHistoryLiveStatus
    let undoEligible: Bool
    let unknownFields: [String]
}

enum CanonicalWhereDidItGoStatus: Equatable {
    case moved
    case movedElsewhere
    case changed
    case noEvidence
    case invalidQuery
    case ledgerUnavailable
}

struct CanonicalWhereDidItGoResult {
    let status: CanonicalWhereDidItGoStatus
    let receipt: Receipt?
    let destination: String?
    /// A presentation-safe category derived by the canonical query. Unlike
    /// destination, this is not a relative path and can cross a system intent boundary.
    let category: String?
}

final class CanonicalHistoryQuery {
    static let maximumPageSize = 100
    static let maximumLedgerBytes = 4 * 1024 * 1024
    static let maximumLedgerRecords = 10_000
    static let maximumNameUTF8Bytes = 255

    private let ledger: ReceiptLedger
    private let movement: MovementService
    private let fm: FileManager

    init(ledger: ReceiptLedger, movement: MovementService, fm: FileManager = .default) {
        self.ledger = ledger
        self.movement = movement
        self.fm = fm
    }

    func history(page requestedPage: Int, limit requestedLimit: Int) -> CanonicalMovementHistory {
        let validation = validatedReceipts()
        guard case .valid(let receipts) = validation else {
            if case .invalid(let reason) = validation {
                return CanonicalMovementHistory(entries: [], integrity: .degraded(reason), hasMore: false)
            }
            return CanonicalMovementHistory(entries: [], integrity: .degraded("ledger validation failed"), hasMore: false)
        }

        let limit = min(max(requestedLimit, 1), Self.maximumPageSize)
        let page = max(requestedPage, 0)
        let ordered = Array(receipts.reversed())
        guard page <= ordered.count / limit else {
            return CanonicalMovementHistory(entries: [], integrity: .valid, hasMore: false)
        }
        let start = page * limit
        let remaining = ordered.dropFirst(start)
        let visible = Array(remaining.prefix(limit))
        let entries = visible.map { entry(for: $0, in: receipts) }
        return CanonicalMovementHistory(entries: entries, integrity: .valid, hasMore: remaining.count > entries.count)
    }

    func whereDidItGo(named rawName: String) -> CanonicalWhereDidItGoResult {
        guard let name = safeName(rawName) else {
            return CanonicalWhereDidItGoResult(status: .invalidQuery, receipt: nil, destination: nil, category: nil)
        }
        guard case .valid(let receipts) = validatedReceipts() else {
            return CanonicalWhereDidItGoResult(status: .ledgerUnavailable, receipt: nil, destination: nil, category: nil)
        }
        guard let receipt = receipts.reversed().first(where: { searchable($0, matches: name) }) else {
            return CanonicalWhereDidItGoResult(status: .noEvidence, receipt: nil, destination: nil, category: nil)
        }
        let destination = receipt.finalDestRel
        let category = destination.flatMap(categoryComponent(of:))
        switch liveStatus(for: receipt) {
        case .present:
            return CanonicalWhereDidItGoResult(status: .moved, receipt: receipt, destination: destination, category: category)
        case .missing:
            return CanonicalWhereDidItGoResult(status: .movedElsewhere, receipt: receipt, destination: destination, category: category)
        case .changed:
            return CanonicalWhereDidItGoResult(status: .changed, receipt: receipt, destination: destination, category: category)
        case .unknown, .invalidDestination:
            return CanonicalWhereDidItGoResult(status: .noEvidence, receipt: nil, destination: nil, category: nil)
        }
    }

    func validatedReceipts() -> ReceiptLedgerValidation {
        ledger.validatedRead(maximumBytes: Self.maximumLedgerBytes, maximumRecords: Self.maximumLedgerRecords)
    }

    private func entry(for receipt: Receipt, in receipts: [Receipt]) -> CanonicalHistoryEntry {
        let originalName = pathComponent(of: receipt.sourceRel)
        let final = receipt.finalDestRel
        let finalName = final.flatMap(pathComponent(of:))
        let category = receipt.reversesReceiptID == nil ? final.flatMap(categoryComponent(of:)) : "Restored"
        let timestamp = receipt.completedAt ?? receipt.preparedAt
        var unknown = [String]()
        if originalName == nil { unknown.append("originalName") }
        if finalName == nil { unknown.append("finalName") }
        if category == nil { unknown.append("category") }
        if receipt.moverLabel.isEmpty { unknown.append("mover") }
        if receipt.completedAt == nil { unknown.append("completedAt") }
        let eligible = receipt.undoEligible
            && !receipts.contains(where: {
                $0.reversesReceiptID == receipt.id && ($0.outcome == "moved" || $0.outcome == "recovered")
            })
            && movement.canUndo(receipt: receipt)
        return CanonicalHistoryEntry(
            receipt: receipt,
            originalName: originalName,
            finalName: finalName,
            category: category,
            timestamp: timestamp,
            mover: receipt.moverLabel.isEmpty ? nil : receipt.moverLabel,
            liveStatus: liveStatus(for: receipt),
            undoEligible: eligible,
            unknownFields: unknown
        )
    }

    private func searchable(_ receipt: Receipt, matches name: String) -> Bool {
        guard receipt.outcome == "moved" || receipt.outcome == "recovered" else { return false }
        return [pathComponent(of: receipt.sourceRel), receipt.finalDestRel.flatMap(pathComponent(of:))]
            .compactMap { $0 }
            .contains { folded($0) == name }
    }

    private func safeName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.lengthOfBytes(using: .utf8) <= Self.maximumNameUTF8Bytes,
              trimmed != ".", trimmed != "..",
              !trimmed.contains("/"), !trimmed.contains("\\"),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return folded(trimmed)
    }

    private func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX"))
    }

    private func pathComponent(of relative: String) -> String? {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard let last = components.last, !last.isEmpty, last != ".", last != ".." else { return nil }
        return String(last)
    }

    private func categoryComponent(of relative: String) -> String? {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard (2...17).contains(components.count),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return String(components[0])
    }

    private func liveStatus(for receipt: Receipt) -> CanonicalHistoryLiveStatus {
        guard receipt.rootCanonical == movement.rootCanonical.path,
              receipt.outcome == "moved" || receipt.outcome == "recovered",
              let final = receipt.finalDestRel,
              let destination = confinedDestination(final, allowsRootLevel: receipt.reversesReceiptID != nil) else {
            return .invalidDestination
        }
        guard fm.fileExists(atPath: destination.path) else { return .missing }
        guard let identity = receipt.artifactIdentity else { return .unknown }
        return FileArtifactIdentity.capture(at: destination) == identity ? .present : .changed
    }

    private func confinedDestination(_ relative: String, allowsRootLevel: Bool) -> URL? {
        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard (allowsRootLevel ? components.count == 1 : (2...17).contains(components.count)),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        let destination = movement.root.appendingPathComponent(relative)
        if allowsRootLevel {
            guard AuthorityGuard.canonicalize(destination.deletingLastPathComponent().path) == movement.rootCanonical,
                  !isSymbolicLink(destination) else { return nil }
        } else {
            var cursor = URL(fileURLWithPath: movement.rootCanonical.path, isDirectory: true)
            for component in components.dropLast() {
                cursor.appendPathComponent(String(component), isDirectory: true)
                if isSymbolicLink(cursor) { return nil }
            }
            guard !isSymbolicLink(destination) else { return nil }
        }
        return destination
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}

extension ReceiptLedger {
    func validatedRead(maximumBytes: Int, maximumRecords: Int) -> ReceiptLedgerValidation {
        guard maximumBytes > 0, maximumRecords > 0 else {
            return .invalid("invalid ledger query bounds")
        }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: ledgerURL.path) else { return .valid([]) }
        guard let attributes = try? fileManager.attributesOfItem(atPath: ledgerURL.path),
              let size = attributes[FileAttributeKey.size] as? NSNumber,
              size.intValue <= maximumBytes else {
            return .invalid("ledger is unavailable or exceeds the bounded query size")
        }
        guard let data = fileManager.contents(atPath: ledgerURL.path),
              let text = String(data: data, encoding: .utf8) else {
            return .invalid("ledger is unreadable")
        }
        var receipts = [Receipt]()
        var previous = "genesis"
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard receipts.count < maximumRecords else {
                return .invalid("ledger exceeds the bounded query record count")
            }
            guard let receipt = try? JSONDecoder().decode(Receipt.self, from: Data(line.utf8)),
                  Receipt.outcomes.contains(receipt.outcome),
                  receipt.prevDigest == previous,
                  computeDigest(receipt) == receipt.digest else {
                return .invalid("ledger integrity verification failed")
            }
            receipts.append(receipt)
            previous = receipt.digest
        }
        return .valid(receipts)
    }
}
