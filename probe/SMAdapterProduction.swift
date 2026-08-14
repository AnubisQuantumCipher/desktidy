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
        return .failure(.failedClosed("ungranted production mutation is not connected"))
    }

    func requestRegister(plistName: String, grant: PreparedMutationGrant) -> Result<Void, SMAdapterError> {
        switch GrantedMutation.accept(grant: grant, requested: .register, plistName: plistName) {
        case .refuse(let r):
            return .failure(.failedClosed(r))
        case .accept:
            return invokeGrantedRegister(plistName: plistName)
        }
    }

    func requestUnregister(plistName: String) -> Result<Void, SMAdapterError> {
        ProductionMutationLedger.unregisterInvocations += 1
        return .failure(.failedClosed("ungranted production mutation is not connected"))
    }

    func requestUnregister(plistName: String, grant: PreparedMutationGrant) -> Result<Void, SMAdapterError> {
        switch GrantedMutation.accept(grant: grant, requested: .unregister, plistName: plistName) {
        case .refuse(let r):
            return .failure(.failedClosed(r))
        case .accept:
            return invokeGrantedUnregister(plistName: plistName)
        }
    }

    /// Only the grant-accepting overloads may call this.
    private func invokeGrantedRegister(plistName: String) -> Result<Void, SMAdapterError> {
        ProductionMutationLedger.registerInvocations += 1
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: plistName)
            do {
                try service.register()
                return .success(())
            } catch {
                return .failure(.failedClosed("SMAppService.register: \(error)"))
            }
        }
        return .failure(.unavailable)
    }

    /// Only the grant-accepting overloads may call this.
    private func invokeGrantedUnregister(plistName: String) -> Result<Void, SMAdapterError> {
        ProductionMutationLedger.unregisterInvocations += 1
        if #available(macOS 13.0, *) {
            let service = SMAppService.agent(plistName: plistName)
            do {
                try service.unregister()
                return .success(())
            } catch {
                return .failure(.failedClosed("SMAppService.unregister: \(error)"))
            }
        }
        return .failure(.unavailable)
    }
}
