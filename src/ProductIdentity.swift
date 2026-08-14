import Foundation

// ============================================================================
//  Product identity catalog.
//
//  Phase 0 accepts exactly the existing self-label set. A future SMAppService
//  label is not self. See docs/R1B_SERVICE_IDENTITY_PROPOSAL.md.
// ============================================================================

enum ProductIdentity {
    static let sortLabel = "com.desktidy.sort"
    static let notifyLabel = "com.desktidy.notify"
    static let selfLabels: Set<String> = [sortLabel, notifyLabel]
    static let expectedProgramBasenames: Set<String> = ["desktidy-sort", "desktidy-notify", "DeskTidy"]

    static func isSelf(label: String, programPath: String?, programExists: Bool) -> Bool {
        guard selfLabels.contains(label) else { return false }
        guard programExists, let programPath, !programPath.isEmpty else { return true }
        let base = URL(fileURLWithPath: programPath).lastPathComponent
        return expectedProgramBasenames.contains(base)
    }
}
