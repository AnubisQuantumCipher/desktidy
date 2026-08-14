import Foundation

// ============================================================================
//  Product identity catalog.
//
//  Phase 0 accepts exactly the existing self-label set. A future SMAppService
//  label is not self. See docs/R1B_SERVICE_IDENTITY_PROPOSAL.md.
// ============================================================================

enum ProductIdentity {
    static let sortLabel = ServiceIdentityRegistry.record(role: .sortCLI).label
    static let notifyLabel = ServiceIdentityRegistry.record(role: .notifyCLI).label
    static let selfLabels: Set<String> = ServiceIdentityRegistry.productionSelfLabels
    static let expectedProgramBasenames: Set<String> = Set(
        ServiceIdentityRegistry.records.filter { $0.acceptedSelf || $0.role == .menuBarApp }.map(\.expectedProgram)
    )

    static func isSelf(label: String, programPath: String?, programExists: Bool) -> Bool {
        guard selfLabels.contains(label) else { return false }
        guard programExists, let programPath, !programPath.isEmpty else { return true }
        let base = URL(fileURLWithPath: programPath).lastPathComponent
        return expectedProgramBasenames.contains(base)
    }
}
