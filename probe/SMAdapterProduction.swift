import Foundation
import ServiceManagement

// Production adapter. Construction has no side effect.
// register/unregister exist so Phase 1B can call them *only* after the
// MutationInterlock grants. Phase 1A never executes those methods.
final class ProductionSMAdapter: ServiceManagementAdapting {
    init() {
        ProductionMutationLedger.constructions += 1
    }

    func status(plistName: String) -> Result<SMAdapterStatus, SMAdapterError> {
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: plistName)
            switch service.status {
            case .enabled: return .success(.enabled)
            case .requiresApproval: return .success(.requiresApproval)
            case .notRegistered: return .success(.notRegistered)
            case .notFound: return .success(.notFound)
            default: return .success(.unknown(String(describing: service.status)))
            }
        }
        return .failure(.unavailable)
    }

    func requestRegister(plistName: String) -> Result<Void, SMAdapterError> {
        ProductionMutationLedger.registerInvocations += 1
        return .failure(.failedClosed("Phase 1A.1 sealed: production mutation is not connected"))
    }

    func requestRegister(plistName: String, grant: PreparedMutationGrant) -> Result<Void, SMAdapterError> {
        _ = grant
        return requestRegister(plistName: plistName)
    }

    func requestUnregister(plistName: String) -> Result<Void, SMAdapterError> {
        ProductionMutationLedger.unregisterInvocations += 1
        return .failure(.failedClosed("Phase 1A.1 sealed: production mutation is not connected"))
    }

    func requestUnregister(plistName: String, grant: PreparedMutationGrant) -> Result<Void, SMAdapterError> {
        _ = grant
        return requestUnregister(plistName: plistName)
    }
}
