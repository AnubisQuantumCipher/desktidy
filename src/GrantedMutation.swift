import Foundation

// ============================================================================
//  Phase 1B: a prepared grant is necessary but not sufficient. The production
//  adapter may invoke SMAppService only after this check accepts the grant.
//  Ungranted overloads stay disconnected.
// ============================================================================

enum GrantedMutation {
    static let sacrificialPlistName = "com.desktidy.sacrificial.plist"

    enum Outcome: Equatable {
        case accept
        case refuse(String)
    }

    static func accept(
        grant: PreparedMutationGrant,
        requested: InterlockOperation,
        plistName: String
    ) -> Outcome {
        if grant.operation != requested {
            return .refuse("grant operation does not match requested mutation")
        }
        if plistName != sacrificialPlistName {
            return .refuse("plist is not the sacrificial probe plist")
        }
        if MutationInterlock.personalLabels.contains(plistName)
            || plistName.contains("desktop-autosort")
            || plistName.contains("com.desktidy.sort")
            || plistName.contains("com.desktidy.notify") {
            return .refuse("protected or production plist is never a mutation target")
        }
        if grant.executableSHA256 == String(repeating: "0", count: 64) {
            return .refuse("grant executable hash is the zero placeholder")
        }
        if grant.sourceCommit.count != 40 || !MutationInterlock.isCommitHex(grant.sourceCommit) {
            return .refuse("grant source commit is not a 40-hex SHA")
        }
        return .accept
    }
}
