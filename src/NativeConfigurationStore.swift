import CryptoKit
import Darwin
import Foundation

struct NativeConfigurationOperationReceipt: Codable, Equatable {
    enum Operation: String, Codable { case write, migration, rollback }
    let id: String
    let timestamp: String
    let operation: Operation
    let beforeSchema: Int?
    let afterSchema: Int
    let previousDigest: String?
    let configurationDigest: String
    let backupFile: String?
}

struct NativeConfigurationStoreResult: Equatable {
    let configuration: NativeConfiguration?
    let receipt: NativeConfigurationOperationReceipt?
    let failure: String?
}

/// The only owner of native configuration persistence. A pending receipt is
/// durable before replacement; a later load finalizes an interrupted write.
final class NativeConfigurationStore {
    private let url: URL
    private let fm: FileManager
    private let iso: ISO8601DateFormatter

    init(url: URL, fm: FileManager = .default) {
        self.url = url
        self.fm = fm
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        iso = formatter
    }

    func load(migratingSchema1: Bool = false) -> NativeConfigurationStoreResult {
        if let reason = validateExistingRoot() { return failed(reason) }
        _ = recoverPending()
        guard fm.fileExists(atPath: url.path) else { return .init(configuration: nil, receipt: nil, failure: nil) }
        guard let data = fm.contents(atPath: url.path) else { return failed("native config exists but is unreadable") }
        let parsed = NativeConfigParser.parseConfiguration(data)
        guard let configuration = parsed.configuration else { return failed(parsed.failure ?? "native config is malformed") }
        guard migratingSchema1, configuration.schema == .v1 else { return .init(configuration: configuration, receipt: nil, failure: nil) }
        let upgraded = NativeConfiguration.defaultV2(target: configuration.target)
        return persist(data: NativeConfigurationCodec.encode(upgraded)!, configuration: upgraded, operation: .migration, previousData: data, beforeSchema: .v1)
    }

    func save(_ configuration: NativeConfiguration) -> NativeConfigurationStoreResult {
        guard configuration.schema == .v2, let data = NativeConfigurationCodec.encode(configuration) else { return failed("only schema-2 configuration is writable") }
        let previous = fm.contents(atPath: url.path)
        let priorSchema = previous.flatMap { NativeConfigParser.parseConfiguration($0).configuration?.schema }
        return persist(data: data, configuration: configuration, operation: priorSchema == .v1 ? .migration : .write, previousData: previous, beforeSchema: priorSchema)
    }

    func receipts() -> [NativeConfigurationOperationReceipt] {
        guard let data = fm.contents(atPath: receiptsURL.path), let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { try? JSONDecoder().decode(NativeConfigurationOperationReceipt.self, from: Data($0.utf8)) }
    }

    func rollbackMigration(receiptID: String) -> NativeConfigurationStoreResult? {
        guard safeIdentifier(receiptID), let migration = receipts().first(where: { $0.id == receiptID && $0.operation == .migration }), let backup = migration.backupFile,
              let data = fm.contents(atPath: backupsURL.appendingPathComponent(backup).path), let configuration = NativeConfigParser.parseConfiguration(data).configuration,
              configuration.schema == .v1 else { return nil }
        return persist(data: data, configuration: configuration, operation: .rollback, previousData: fm.contents(atPath: url.path), beforeSchema: .v2)
    }

    private func persist(data: Data, configuration: NativeConfiguration, operation: NativeConfigurationOperationReceipt.Operation, previousData: Data?, beforeSchema: NativeConfigurationSchema?) -> NativeConfigurationStoreResult {
        if let rootFailure = prepareRoot() { return failed("native config root is unsafe: \(rootFailure)") }
        if let targetFailure = validateTarget(configuration.target) { return failed("native config target is unsafe: \(targetFailure)") }
        if let configFailure = validateExistingConfig() { return failed(configFailure) }
        let id = UUID().uuidString.lowercased()
        let backup = operation == .migration ? "\(id).json" : nil
        let receipt = NativeConfigurationOperationReceipt(id: id, timestamp: iso.string(from: Date()), operation: operation, beforeSchema: beforeSchema?.rawValue, afterSchema: configuration.schema.rawValue, previousDigest: previousData.map(digest), configurationDigest: digest(data), backupFile: backup)
        do {
            if let backup, let previousData { try ensurePrivateDirectory(backupsURL); try writeAtomically(previousData, to: backupsURL.appendingPathComponent(backup)) }
            try ensurePrivateDirectory(pendingURL)
            try writeAtomically(try JSONEncoder.sortedConfiguration.encode(receipt), to: pendingURL.appendingPathComponent("\(id).json"))
            try writeAtomically(data, to: url)
            try append(receipt)
            try fm.removeItem(at: pendingURL.appendingPathComponent("\(id).json"))
            return .init(configuration: configuration, receipt: receipt, failure: nil)
        } catch { return failed("native config persistence failed: \(error.localizedDescription)") }
    }

    private func recoverPending() -> String? {
        guard fm.fileExists(atPath: pendingURL.path), let entries = try? fm.contentsOfDirectory(at: pendingURL, includingPropertiesForKeys: nil) else { return nil }
        for entry in entries {
            guard let data = fm.contents(atPath: entry.path), let receipt = try? JSONDecoder().decode(NativeConfigurationOperationReceipt.self, from: data) else { return "unreadable pending configuration receipt" }
            guard let current = fm.contents(atPath: url.path), digest(current) == receipt.configurationDigest else { continue }
            if !receipts().contains(where: { $0.id == receipt.id }) { do { try append(receipt) } catch { return "cannot finalize pending configuration receipt" } }
            try? fm.removeItem(at: entry)
        }
        return nil
    }

    private var rootURL: URL { url.deletingLastPathComponent() }
    private var receiptsURL: URL { rootURL.appendingPathComponent("config-receipts.jsonl") }
    private var pendingURL: URL { rootURL.appendingPathComponent("config-pending", isDirectory: true) }
    private var backupsURL: URL { rootURL.appendingPathComponent("config-backups", isDirectory: true) }
    private func failed(_ reason: String) -> NativeConfigurationStoreResult { .init(configuration: nil, receipt: nil, failure: reason) }

    private func validateExistingRoot() -> String? {
        guard !protected(rootURL.path), noSymlink(rootURL) else { return "protected or symlinked root" }
        return fm.fileExists(atPath: rootURL.path) ? ownerFailure(rootURL, requirePrivate: false) : nil
    }

    // Nil denotes success. Only this product's root and files are mode-tightened.
    private func prepareRoot() -> String? {
        if let failure = validateExistingRoot() { return failure }
        do {
            try fm.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rootURL.path)
        } catch { return "cannot create private root" }
        return ownerFailure(rootURL, requirePrivate: true)
    }

    private func validateExistingConfig() -> String? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        guard !symbolicLink(url) else { return "native config is a symlink" }
        // Schema-1 files may predate private writes; atomic replacement below
        // produces a 0600 file after first owner-authorized migration.
        return ownerFailure(url, requirePrivate: false)
    }

    private func validateTarget(_ target: String) -> String? {
        let path = TargetResolver.standardize(target)
        guard path.hasPrefix("/"), !protected(path), noSymlink(URL(fileURLWithPath: path)) else { return "protected, relative, or symlinked target" }
        var directory: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue ? nil : "target is not an existing directory"
    }

    private func ensurePrivateDirectory(_ directory: URL) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if let failure = ownerFailure(directory, requirePrivate: true) { throw StoreError.unsafe(failure) }
    }

    private func writeAtomically(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at: temporary) }
        guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw StoreError.write }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
        guard Darwin.rename(temporary.path, destination.path) == 0 else { throw StoreError.write }
        try synchronize(destination.deletingLastPathComponent())
    }

    private func append(_ receipt: NativeConfigurationOperationReceipt) throws {
        if !fm.fileExists(atPath: receiptsURL.path) {
            guard fm.createFile(atPath: receiptsURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw StoreError.write }
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receiptsURL.path)
        let handle = try FileHandle(forWritingTo: receiptsURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: try JSONEncoder.sortedConfiguration.encode(receipt) + Data("\n".utf8))
        try handle.synchronize()
        try synchronize(rootURL)
    }

    private func synchronize(_ directory: URL) throws {
        let descriptor = Darwin.open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw StoreError.write }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw StoreError.write }
    }

    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func noSymlink(_ candidate: URL) -> Bool {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in candidate.pathComponents.dropFirst() {
            current.appendPathComponent(component, isDirectory: true)
            var metadata = stat()
            guard Darwin.lstat(current.path, &metadata) == 0 else { break }
            if metadata.st_mode & S_IFMT == S_IFLNK { return false }
        }
        return true
    }
    private func symbolicLink(_ candidate: URL) -> Bool { (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true || (try? fm.attributesOfItem(atPath: candidate.path)[.type] as? FileAttributeType) == .typeSymbolicLink }
    private func ownerFailure(_ candidate: URL, requirePrivate: Bool) -> String? {
        guard let attributes = try? fm.attributesOfItem(atPath: candidate.path), let owner = attributes[.ownerAccountID] as? NSNumber, owner.uint32Value == Darwin.getuid() else { return "path is not owned by the current user" }
        if requirePrivate, let permissions = attributes[.posixPermissions] as? NSNumber, permissions.intValue & 0o077 != 0 { return "path is not private" }
        return nil
    }
    private func protected(_ path: String) -> Bool { ["/", "/System", "/Library", "/usr", "/bin", "/sbin", "/Applications", "/private"].contains(URL(fileURLWithPath: path).standardizedFileURL.path) }
    private func safeIdentifier(_ id: String) -> Bool { id.range(of: "^[0-9a-f-]{36}$", options: .regularExpression) != nil }
}

private enum StoreError: Error { case unsafe(String), write }
private extension JSONEncoder { static var sortedConfiguration: JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder } }
