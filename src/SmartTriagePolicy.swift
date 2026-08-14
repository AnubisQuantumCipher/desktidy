import Foundation

// ============================================================================
// Phase K — pure safety boundary for optional SmartTriage intelligence.
//
// This file deliberately contains data and decisions only. It has no file,
// network, model, target, rule, authorization, receipt, or movement dependency.
// A caller may use an approved request to start its own deterministic flow; this
// policy cannot perform that flow and therefore cannot move a user file.
// ============================================================================

enum SmartTriageRunGate: Equatable {
    case compiledOut
    case rateLimited
    case lowPowerDeferred
    case backendUnavailable
    case mayRequestBackend
}

enum SmartTriageSuggestionProvenance: String, Codable, Equatable {
    case onDeviceModel
    case backendUnavailable
    case lowPowerDeferred
}

/// Caller-owned bytes supplied to an optional intelligence backend. These are
/// data, never instructions or authority. The preview is intentionally omitted
/// from a resulting suggestion so it cannot become an action payload.
struct SmartTriageUntrustedInput: Equatable {
    let name: String
    let preview: String
}

/// A presentation record, not a routing decision. `destination` is proposed
/// display data and cannot select a target, alter a rule, or invoke a mover.
struct SmartTriageSuggestion: Equatable {
    let itemName: String
    let destination: String
    let certainty: String
    let reason: String
    let provenance: SmartTriageSuggestionProvenance

    init(
        input: SmartTriageUntrustedInput,
        destination: String,
        certainty: String,
        reason: String,
        provenance: SmartTriageSuggestionProvenance
    ) {
        itemName = input.name
        self.destination = destination
        self.certainty = certainty
        self.reason = reason
        self.provenance = provenance
    }
}

/// Explicit approval does not execute a suggestion. It returns an inert request
/// that a distinct deterministic action and receipt path must independently
/// validate before any user-file operation is possible.
struct SmartTriageDeterministicActionRequest: Equatable {
    let itemName: String
    let proposedDestination: String
}

enum SmartTriageApproval: Equatable {
    case requiresExplicitApproval
    case requiresDeterministicAction(SmartTriageDeterministicActionRequest)

    static func requestDeterministicAction(
        for suggestion: SmartTriageSuggestion,
        explicitlyApproved: Bool
    ) -> SmartTriageApproval {
        guard explicitlyApproved else { return .requiresExplicitApproval }
        return .requiresDeterministicAction(
            SmartTriageDeterministicActionRequest(
                itemName: suggestion.itemName,
                proposedDestination: suggestion.destination
            )
        )
    }
}

enum SmartTriageControl {
    /// Capability is intentionally not a guarantee. Any unavailable, deferred,
    /// or rate-limited state leaves the deterministic organizer untouched.
    static func runGate(
        compiledIn: Bool,
        isDue: Bool,
        lowPowerMode: Bool,
        backendAvailable: Bool
    ) -> SmartTriageRunGate {
        guard compiledIn else { return .compiledOut }
        guard isDue else { return .rateLimited }
        guard !lowPowerMode else { return .lowPowerDeferred }
        guard backendAvailable else { return .backendUnavailable }
        return .mayRequestBackend
    }
}
