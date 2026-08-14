import Foundation
import Darwin

// Fake-only Phase B migration substrate. No production adapter conforms to or
// is accepted by this coordinator. Production wiring remains deliberately
// absent until the planned app-agent identity is observed and accepted.
enum MigrationRecoveryStage: String, Codable, Equatable {
    case prepared
    case registrationPrepared
    case serviceHealthy
    case legacyRemovalPrepared
    case completed
    case rollbackRequired
    case rolledBack
    case refused
}

struct RecoverableMigrationRecord: Codable, Equatable {
    let schema: Int
    let id: String
    let serviceRole: ProductServiceRole
    let serviceLabel: String
    let plistName: String
    let targetCanonical: String
    let priorCLIPresent: Bool
    var ownerUID: UInt32 = Darwin.getuid()
    var stage: MigrationRecoveryStage
}

enum MigrationRecordStoreError: Error, Equatable {
    case missing
    case invalid
    case writeFailed
}

final class FileMigrationRecordStore {
    let url: URL
    var failNextSaveCount = 0
    var failAfterExclusiveCreate = false
    var afterExclusiveCreate: (() -> Void)?

    init(url: URL) {
        self.url = url
    }

    private func ensurePrivateParent() throws {
        let parent = url.deletingLastPathComponent().path
        if Darwin.mkdir(parent, S_IRUSR | S_IWUSR | S_IXUSR) != 0 && errno != EEXIST {
            throw MigrationRecordStoreError.writeFailed
        }
        var metadata = stat()
        guard Darwin.lstat(parent, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFDIR,
              metadata.st_uid == Darwin.getuid() else {
            throw MigrationRecordStoreError.writeFailed
        }
        guard Darwin.chmod(parent, S_IRUSR | S_IWUSR | S_IXUSR) == 0 else {
            throw MigrationRecordStoreError.writeFailed
        }
    }
    private func syncPath(_ path: String) throws {
        let descriptor = Darwin.open(path, O_RDONLY)
        guard descriptor >= 0 else { throw MigrationRecordStoreError.writeFailed }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw MigrationRecordStoreError.writeFailed }
    }



    func load() throws -> RecoverableMigrationRecord? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = FileManager.default.contents(atPath: url.path),
              case .ok(let object) = StrictJSONObject.parse(data),
              Set(object.keys) == ["schema", "id", "serviceRole", "serviceLabel", "plistName", "targetCanonical", "priorCLIPresent", "ownerUID", "stage"],
              case .integer(let schema)? = object["schema"],
              case .string(let id)? = object["id"],
              case .string(let roleRaw)? = object["serviceRole"],
              let role = ProductServiceRole(rawValue: roleRaw),
              case .string(let label)? = object["serviceLabel"],
              case .string(let plist)? = object["plistName"],
              case .string(let target)? = object["targetCanonical"],
              case .integer(let priorRaw)? = object["priorCLIPresent"], priorRaw == 0 || priorRaw == 1,
              case .integer(let ownerRaw)? = object["ownerUID"], ownerRaw == Int(Darwin.getuid()),
              case .string(let stageRaw)? = object["stage"],
              let stage = MigrationRecoveryStage(rawValue: stageRaw) else {
            throw MigrationRecordStoreError.invalid
        }
        return RecoverableMigrationRecord(schema: schema, id: id, serviceRole: role, serviceLabel: label, plistName: plist, targetCanonical: target, priorCLIPresent: priorRaw == 1, stage: stage)
    }

    func save(_ record: RecoverableMigrationRecord) throws {
        do {
            if failNextSaveCount > 0 {
                failNextSaveCount -= 1
                throw MigrationRecordStoreError.writeFailed
            }
            try ensurePrivateParent()
            let data = try serialized(record)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try syncPath(url.path)
            try syncPath(url.deletingLastPathComponent().path)
        } catch {
            throw MigrationRecordStoreError.writeFailed
        }
    }

    func createIfAbsent(_ record: RecoverableMigrationRecord) throws -> Bool {
        do { try ensurePrivateParent() }
        catch { throw MigrationRecordStoreError.writeFailed }
        let data: Data
        do { data = try serialized(record) }
        catch { throw MigrationRecordStoreError.writeFailed }

        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        if descriptor == -1 {
            if errno == EEXIST { return false }
            throw MigrationRecordStoreError.writeFailed
        }
        var created = stat()
        guard Darwin.fstat(descriptor, &created) == 0 else {
            Darwin.close(descriptor)
            throw MigrationRecordStoreError.writeFailed
        }
        afterExclusiveCreate?()
        var completed = false
        defer {
            Darwin.close(descriptor)
            if !completed {
                var current = stat()
                if Darwin.lstat(url.path, &current) == 0,
                   current.st_dev == created.st_dev,
                   current.st_ino == created.st_ino {
                    Darwin.unlink(url.path)
                }
            }
        }
        do {
            if failAfterExclusiveCreate { throw MigrationRecordStoreError.writeFailed }
            try data.withUnsafeBytes { raw in
                guard var pointer = raw.baseAddress else { return }
                var remaining = raw.count
                while remaining > 0 {
                    let count = Darwin.write(descriptor, pointer, remaining)
                    guard count > 0 else { throw MigrationRecordStoreError.writeFailed }
                    remaining -= count
                    pointer = pointer.advanced(by: count)
                }
            }
            guard Darwin.fsync(descriptor) == 0 else { throw MigrationRecordStoreError.writeFailed }
            try syncPath(url.deletingLastPathComponent().path)
            completed = true
            return true
        } catch {
            throw MigrationRecordStoreError.writeFailed
        }
    }

    private func serialized(_ record: RecoverableMigrationRecord) throws -> Data {
        let object: [String: Any] = [
            "schema": record.schema,
            "id": record.id,
            "serviceRole": record.serviceRole.rawValue,
            "ownerUID": Int(record.ownerUID),
            "serviceLabel": record.serviceLabel,
            "plistName": record.plistName,
            "targetCanonical": record.targetCanonical,
            "priorCLIPresent": record.priorCLIPresent ? 1 : 0,
            "stage": record.stage.rawValue
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

final class FakeLegacyCLIAdapter {
    private(set) var present: Bool
    private(set) var removeCount = 0
    private(set) var restoreCount = 0
    var removeSucceeds = true
    var restoreSucceeds = true

    init(present: Bool) {
        self.present = present
    }

    func removeProductOwnedLegacyService() -> Bool {
        removeCount += 1
        guard removeSucceeds else { return false }
        present = false
        return true
    }

    func restoreProductOwnedLegacyService() -> Bool {
        restoreCount += 1
        guard restoreSucceeds else { return false }
        present = true
        return true
    }
}

struct FakeRecoverableMigrationCoordinator {
    let service: FakeSMAdapter
    let legacy: FakeLegacyCLIAdapter
    let store: FileMigrationRecordStore
    let serviceIdentity: ProductServiceIdentity
    private static let transitionLock = NSLock()

    private var hasCanonicalPlannedIdentity: Bool {
        serviceIdentity == ProductServiceRegistry.canonical.identity(for: .plannedAppAgent)
    }

    private func canonicalExistingDirectory(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return AuthorityGuard.canonicalize(path).path
    }

    private func persist(_ record: RecoverableMigrationRecord) -> MigrationRecoveryStage {
        do {
            try store.save(record)
            return record.stage
        } catch {
            var rollback = record
            rollback.stage = .rollbackRequired
            try? store.save(rollback)
            return .rollbackRequired
        }
    }

    func begin(from state: MigrationState, targetCanonical: String) -> MigrationRecoveryStage {
        guard state == .cliOnly || state == .neitherInstalled,
              hasCanonicalPlannedIdentity,
              let label = serviceIdentity.serviceLabel,
              let plist = serviceIdentity.embeddedPlistName,
              let canonicalTarget = canonicalExistingDirectory(targetCanonical) else {
            return .refused
        }
        Self.transitionLock.lock()
        defer { Self.transitionLock.unlock() }
        let record = RecoverableMigrationRecord(
            schema: 1,
            id: UUID().uuidString,
            serviceRole: serviceIdentity.role,
            serviceLabel: label,
            plistName: plist,
            targetCanonical: canonicalTarget,
            priorCLIPresent: state == .cliOnly,
            stage: .prepared
        )
        do { return try store.createIfAbsent(record) ? .prepared : .refused }
        catch { return .rollbackRequired }
    }

    func advance() -> MigrationRecoveryStage {
        Self.transitionLock.lock()
        defer { Self.transitionLock.unlock() }
        guard var record = try? store.load() else {
            return .rollbackRequired
        }
        guard record.schema == 1,
              hasCanonicalPlannedIdentity,
              record.serviceRole == serviceIdentity.role,
              record.serviceLabel == serviceIdentity.serviceLabel,
              record.plistName == serviceIdentity.embeddedPlistName,
              canonicalExistingDirectory(record.targetCanonical) == record.targetCanonical else {
            return .rollbackRequired
        }

        switch record.stage {
        case .prepared:
            record.stage = .registrationPrepared
        case .registrationPrepared:
            switch service.status(plistName: record.plistName) {
            case .success(.enabled):
                record.stage = service.observedTargetCanonical == record.targetCanonical
                    ? .serviceHealthy : .rollbackRequired
            case .success(.notRegistered), .success(.notFound):
                guard case .success = service.requestRegister(plistName: record.plistName) else {
                    record.stage = .rollbackRequired
                    break
                }
                guard case .success(.enabled) = service.status(plistName: record.plistName),
                      service.observedTargetCanonical == record.targetCanonical else {
                    record.stage = .rollbackRequired
                    break
                }
                record.stage = .serviceHealthy
            case .success(.requiresApproval), .success(.unknown), .failure:
                record.stage = .rollbackRequired
            }
        case .serviceHealthy:
            if record.priorCLIPresent {
                record.stage = .legacyRemovalPrepared
            } else {
                record.stage = .completed
            }
        case .legacyRemovalPrepared:
            guard case .success(.enabled) = service.status(plistName: record.plistName),
                  service.observedTargetCanonical == record.targetCanonical else {
                record.stage = .rollbackRequired
                break
            }
            if !legacy.present || legacy.removeProductOwnedLegacyService() {
                record.stage = .completed
            } else {
                record.stage = .rollbackRequired
            }
        case .completed, .rollbackRequired, .rolledBack, .refused:
            return record.stage
        }

        return persist(record)
    }

    func recover() -> MigrationRecoveryStage {
        Self.transitionLock.lock()
        defer { Self.transitionLock.unlock() }
        guard var record = try? store.load() else { return .rollbackRequired }
        guard record.schema == 1,
              hasCanonicalPlannedIdentity,
              record.serviceRole == serviceIdentity.role,
              record.serviceLabel == serviceIdentity.serviceLabel,
              record.plistName == serviceIdentity.embeddedPlistName,
              canonicalExistingDirectory(record.targetCanonical) == record.targetCanonical else {
            return .rollbackRequired
        }
        if record.stage == .rolledBack { return .rolledBack }
        guard record.stage == .prepared
                || record.stage == .registrationPrepared
                || record.stage == .serviceHealthy
                || record.stage == .legacyRemovalPrepared
                || record.stage == .rollbackRequired else { return .refused }

        guard service.observedTargetCanonical == record.targetCanonical else {
            return .rollbackRequired
        }

        switch service.status(plistName: record.plistName) {
        case .success(.enabled), .success(.requiresApproval):
            guard case .success = service.requestUnregister(plistName: record.plistName) else {
                return .rollbackRequired
            }
            switch service.status(plistName: record.plistName) {
            case .success(.notRegistered), .success(.notFound):
                break
            case .success, .failure:
                return .rollbackRequired
            }
        case .success(.notRegistered), .success(.notFound):
            break
        case .success(.unknown), .failure:
            return .rollbackRequired
        }

        if record.priorCLIPresent && !legacy.present {
            guard legacy.restoreProductOwnedLegacyService() else { return .rollbackRequired }
        }
        record.stage = .rolledBack
        do {
            try store.save(record)
            return .rolledBack
        } catch {
            return .rollbackRequired
        }
    }
}
