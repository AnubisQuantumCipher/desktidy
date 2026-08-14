import Foundation
import ServiceManagement

// Production adapter. Construction has no side effect.
// Ungranted overloads stay disconnected. The only ServiceManagement
// register/unregister call sites are executeSealed*, reachable solely
// through SacrificialMutationDispatcher.
final class ProductionSMAdapter: ServiceManagementAdapting, SealedAdapterExecuting {
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

    func requestUnregister(plistName: String) -> Result<Void, SMAdapterError> {
        ProductionMutationLedger.unregisterInvocations += 1
        return .failure(.failedClosed("ungranted production mutation is not connected"))
    }

    func executeSealedRegister(plistName: String) -> Result<Void, SMAdapterError> {
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

    func executeSealedUnregister(plistName: String) -> Result<Void, SMAdapterError> {
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
