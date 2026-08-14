import Foundation
import ServiceManagement

// Production adapter. Construction has no side effect.
// register/unregister exist so Phase 1B can call them *only* after the
// MutationInterlock grants. Phase 1A never executes those methods.
final class ProductionSMAdapter: ServiceManagementAdapting {
    init() {}

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
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.agent(plistName: plistName).register()
                return .success(())
            } catch {
                return .failure(.failedClosed(String(describing: error)))
            }
        }
        return .failure(.unavailable)
    }

    func requestUnregister(plistName: String) -> Result<Void, SMAdapterError> {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.agent(plistName: plistName).unregister()
                return .success(())
            } catch {
                return .failure(.failedClosed(String(describing: error)))
            }
        }
        return .failure(.unavailable)
    }
}
