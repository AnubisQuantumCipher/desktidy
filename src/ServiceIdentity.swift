import Foundation

// ============================================================================
//  One product-owned service identity registry.
//
//  Production accepted self-labels remain the CLI pair. The sacrificial
//  SMAppService label was observed once on this Mac and is recorded here
//  as observation evidence, not as a production self-label.
// ============================================================================

enum ServiceIdentityRole: String, Equatable {
    case sortCLI
    case notifyCLI
    case menuBarApp
    case sacrificialProbe
    case sacrificialHelper
    case personalMover
    case personalNotify
}

enum ServiceIdentityObservation: String, Equatable {
    case coded
    case observedOnce
    case hypothesizedUnobserved
    case neverTarget
}

struct ServiceIdentityRecord: Equatable {
    var role: ServiceIdentityRole
    var label: String
    var bundleID: String?
    var plistName: String?
    var expectedProgram: String
    var acceptedSelf: Bool
    var observation: ServiceIdentityObservation
}

enum ServiceIdentityRegistry {
    static let records: [ServiceIdentityRecord] = [
        .init(role: .sortCLI, label: "com.desktidy.sort", bundleID: nil,
              plistName: "com.desktidy.sort.plist", expectedProgram: "desktidy-sort",
              acceptedSelf: true, observation: .coded),
        .init(role: .notifyCLI, label: "com.desktidy.notify", bundleID: nil,
              plistName: "com.desktidy.notify.plist", expectedProgram: "desktidy-notify",
              acceptedSelf: true, observation: .coded),
        .init(role: .menuBarApp, label: "com.desktidy.app", bundleID: "com.desktidy.app",
              plistName: nil, expectedProgram: "DeskTidy",
              acceptedSelf: false, observation: .coded),
        .init(role: .sacrificialProbe, label: "com.desktidy.sacrificial",
              bundleID: "com.desktidy.sacrificial-probe",
              plistName: "com.desktidy.sacrificial.plist",
              expectedProgram: "SacrificialHelper",
              acceptedSelf: false, observation: .observedOnce),
        .init(role: .sacrificialHelper, label: "com.desktidy.sacrificial",
              bundleID: "com.desktidy.sacrificial-probe",
              plistName: "com.desktidy.sacrificial.plist",
              expectedProgram: "SacrificialHelper",
              acceptedSelf: false, observation: .observedOnce),
        .init(role: .personalMover, label: "com.sicarii.desktop-autosort",
              bundleID: nil, plistName: "com.sicarii.desktop-autosort.plist",
              expectedProgram: "desktop-autosort-helper",
              acceptedSelf: false, observation: .neverTarget),
        .init(role: .personalNotify, label: "com.sicarii.desktop-autosort-notify",
              bundleID: nil, plistName: "com.sicarii.desktop-autosort-notify.plist",
              expectedProgram: "desktidy-notify",
              acceptedSelf: false, observation: .neverTarget),
    ]

    static var productionSelfLabels: Set<String> {
        Set(records.filter(\.acceptedSelf).map(\.label))
    }

    static var neverTargetLabels: Set<String> {
        Set(records.filter { $0.observation == .neverTarget }.map(\.label))
    }

    static var sacrificialObservedLabel: String {
        records.first { $0.role == .sacrificialProbe }!.label
    }

    static func record(role: ServiceIdentityRole) -> ServiceIdentityRecord {
        records.first { $0.role == role }!
    }

    /// Configured identity must equal the observed identity when both exist.
    static func disagreement(configured: String, observed: String) -> String? {
        if configured != observed {
            return "configured identity disagrees with observed identity"
        }
        return nil
    }

    static func isAcceptedSelf(_ label: String) -> Bool {
        productionSelfLabels.contains(label)
    }

    static func isNeverTarget(_ label: String) -> Bool {
        neverTargetLabels.contains(label) || label.contains("desktop-autosort")
    }

    static func isKnownIdentity(_ name: String) -> Bool {
        records.contains {
            $0.label == name || $0.plistName == name || $0.plistName == name + ".plist"
        }
    }
}
