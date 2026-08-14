import Foundation

enum ProductServiceRole: String, CaseIterable, Hashable, Codable {
    case legacySorter
    case legacyNotifier
    case menuBarApp
    case plannedAppAgent
    case observedSacrificialProbe
}

enum ProductIdentityAcceptance: Equatable {
    case acceptedLegacySelf
    case bundleOnly
    case plannedUnaccepted
    case observedSacrificialNonProduction
}

struct ProductServiceIdentity: Equatable {
    let role: ProductServiceRole
    let bundleIdentifier: String?
    let serviceLabel: String?
    let embeddedPlistName: String?
    let expectedProgramBasenames: Set<String>
    let acceptance: ProductIdentityAcceptance

    var isAcceptedSelfService: Bool { acceptance == .acceptedLegacySelf }
}

enum ProductIdentityClassification: Equatable {
    case acceptedSelf(ProductServiceRole)
    case knownBundle(ProductServiceRole)
    case observedNonProduction(ProductServiceRole)
    case foreign
}

struct ProductServiceRegistry {
    let identities: [ProductServiceRole: ProductServiceIdentity]

    func identity(for role: ProductServiceRole) -> ProductServiceIdentity? {
        identities[role]
    }

    func classify(
        serviceLabel: String?,
        bundleIdentifier: String?,
        programBasename: String
    ) -> ProductIdentityClassification {
        guard let identity = identities.values.first(where: {
            $0.serviceLabel == serviceLabel
                && $0.bundleIdentifier == bundleIdentifier
                && $0.expectedProgramBasenames.contains(programBasename)
        }) else {
            return .foreign
        }
        switch identity.acceptance {
        case .acceptedLegacySelf:
            return .acceptedSelf(identity.role)
        case .bundleOnly:
            return .knownBundle(identity.role)
        case .plannedUnaccepted:
            return .foreign
        case .observedSacrificialNonProduction:
            return .observedNonProduction(identity.role)
        }
    }

    static let canonical = ProductServiceRegistry(identities: [
        .legacySorter: ProductServiceIdentity(
            role: .legacySorter,
            bundleIdentifier: nil,
            serviceLabel: "com.desktidy.sort",
            embeddedPlistName: "com.desktidy.sort.plist",
            expectedProgramBasenames: ["desktidy-sort"],
            acceptance: .acceptedLegacySelf
        ),
        .legacyNotifier: ProductServiceIdentity(
            role: .legacyNotifier,
            bundleIdentifier: nil,
            serviceLabel: "com.desktidy.notify",
            embeddedPlistName: "com.desktidy.notify.plist",
            expectedProgramBasenames: ["desktidy-notify", "desktidy-notify.sh"],
            acceptance: .acceptedLegacySelf
        ),
        .menuBarApp: ProductServiceIdentity(
            role: .menuBarApp,
            bundleIdentifier: "com.desktidy.app",
            serviceLabel: nil,
            embeddedPlistName: nil,
            expectedProgramBasenames: ["DeskTidy"],
            acceptance: .bundleOnly
        ),
        .plannedAppAgent: ProductServiceIdentity(
            role: .plannedAppAgent,
            bundleIdentifier: "com.desktidy.app",
            serviceLabel: "com.desktidy.app.sort",
            embeddedPlistName: "com.desktidy.app.sort.plist",
            expectedProgramBasenames: ["DeskTidyService"],
            acceptance: .plannedUnaccepted
        ),
        .observedSacrificialProbe: ProductServiceIdentity(
            role: .observedSacrificialProbe,
            bundleIdentifier: "com.desktidy.sacrificial-probe",
            serviceLabel: "com.desktidy.sacrificial",
            embeddedPlistName: "com.desktidy.sacrificial.plist",
            expectedProgramBasenames: ["SacrificialHelper"],
            acceptance: .observedSacrificialNonProduction
        )
    ])
}

// Compatibility facade. All values are derived from the typed registry so
// existing authority/state consumers cannot drift into a second identity list.
enum ProductIdentity {
    private static let registry = ProductServiceRegistry.canonical
    static let sortLabel = registry.identity(for: .legacySorter)!.serviceLabel!
    static let notifyLabel = registry.identity(for: .legacyNotifier)!.serviceLabel!
    static let selfLabels: Set<String> = Set(
        registry.identities.values.compactMap { identity in
            identity.isAcceptedSelfService ? identity.serviceLabel : nil
        }
    )
    static let expectedProgramBasenames: Set<String> = Set(
        [ProductServiceRole.legacySorter, .legacyNotifier, .menuBarApp].flatMap { role in
            registry.identity(for: role)?.expectedProgramBasenames ?? []
        }
    )

    static func isSelf(label: String, programPath: String?, programExists: Bool) -> Bool {
        guard selfLabels.contains(label) else { return false }
        guard programExists, let programPath, !programPath.isEmpty else { return true }
        let base = URL(fileURLWithPath: programPath).lastPathComponent
        return expectedProgramBasenames.contains(base)
    }
}
