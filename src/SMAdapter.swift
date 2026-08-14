import Foundation

// ============================================================================
//  ServiceManagement adapter seam (Phase 1A).
//
//  Automated tests MUST use FakeSMAdapter only. The production adapter lives
//  in probe/ and is never selected by ambient environment.
//  Construction has no registration side effect. Status is read-only.
// ============================================================================

enum SMAdapterStatus: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound
    case unknown(String)
}

enum SMAdapterError: Error, Equatable {
    case unavailable
    case failedClosed(String)
}

protocol ServiceManagementAdapting: AnyObject {
    func status(plistName: String) -> Result<SMAdapterStatus, SMAdapterError>
    func requestRegister(plistName: String) -> Result<Void, SMAdapterError>
    func requestUnregister(plistName: String) -> Result<Void, SMAdapterError>
}

final class FakeSMAdapter: ServiceManagementAdapting {
    enum Call: Equatable {
        case status(String)
        case register(String)
        case unregister(String)
    }
    private(set) var calls: [Call] = []
    var statusResult: Result<SMAdapterStatus, SMAdapterError> = .success(.notRegistered)
    var registerResult: Result<Void, SMAdapterError> = .success(())
    var unregisterResult: Result<Void, SMAdapterError> = .success(())

    func status(plistName: String) -> Result<SMAdapterStatus, SMAdapterError> {
        calls.append(.status(plistName))
        return statusResult
    }
    func requestRegister(plistName: String) -> Result<Void, SMAdapterError> {
        calls.append(.register(plistName))
        return registerResult
    }
    func requestUnregister(plistName: String) -> Result<Void, SMAdapterError> {
        calls.append(.unregister(plistName))
        return unregisterResult
    }

    var registerCount: Int { calls.filter { if case .register = $0 { return true }; return false }.count }
    var unregisterCount: Int { calls.filter { if case .unregister = $0 { return true }; return false }.count }
}

final class UnavailableSMAdapter: ServiceManagementAdapting {
    func status(plistName: String) -> Result<SMAdapterStatus, SMAdapterError> { .failure(.unavailable) }
    func requestRegister(plistName: String) -> Result<Void, SMAdapterError> { .failure(.unavailable) }
    func requestUnregister(plistName: String) -> Result<Void, SMAdapterError> { .failure(.unavailable) }
}

enum SMAdapterSelection {
    /// Automated tests and the CLI harness may only obtain a fake or unavailable adapter.
    static func forAutomatedTests() -> FakeSMAdapter { FakeSMAdapter() }
    static func unavailable() -> UnavailableSMAdapter { UnavailableSMAdapter() }
}
