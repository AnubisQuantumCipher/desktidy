import Foundation

// Sacrificial operator probe. Default is read-only plan/status.
// Mutation requires --register or --unregister plus a one-time auth file
// that survives MutationInterlock. Phase 1A does not create a live token
// and automated tests do not execute this binary's mutation path.
@main
struct SacrificialProbe {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--help") || args.count == 1 {
            print(planText())
            exit(0)
        }
        if args.contains("--plan") || args.contains("--status") {
            print(planText())
            print("mode: read-only")
            exit(0)
        }
        let registering = args.contains("--register")
        let unregistering = args.contains("--unregister")
        if registering && unregistering {
            fputs("probe: specify only one of --register or --unregister\n", stderr)
            exit(2)
        }
        guard registering || unregistering else {
            print(planText())
            exit(0)
        }
        guard let idx = args.firstIndex(of: "--auth-file"), idx + 1 < args.count else {
            fputs("probe: mutation requires --auth-file <path>\n", stderr)
            exit(2)
        }
        let authPath = args[idx + 1]
        guard let data = FileManager.default.contents(atPath: authPath) else {
            fputs("probe: authorization file unreadable\n", stderr)
            exit(2)
        }

        // Interlock first. Production adapter is constructed only after a
        // permit decision — still not invoked unless grant exists.
        let desktop = AuthorityGuard.canonicalize(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").path)
        let ctx = InterlockContext(
            isSacrificialProbeExecutable: true,
            requestedOperation: registering ? .register : .unregister,
            plistName: SacrificialIdentity.hypothesizedPlistName,
            actualBundleSHA256: SacrificialIdentity.bundleSHA256Placeholder,
            actualSourceCommit: SacrificialIdentity.sourceCommitPlaceholder,
            now: Date(),
            usedNonces: [],
            foreignOverlap: false,
            desktopCanonical: desktop,
            sacrificialExists: true
        )
        switch MutationInterlock.evaluate(authData: data, context: ctx) {
        case .refuse(let reason):
            fputs("probe: interlock refused — \(reason)\n", stderr)
            exit(3)
        case .permit:
            fputs("probe: interlock would permit, but Phase 1A harness will not invoke the production mutator\n", stderr)
            exit(4)
        }
    }

    static func planText() -> String {
        """
        DeskTidy sacrificial SMAppService probe (NON-PRODUCTION)
        Default: read-only plan. No registration in Phase 1A.
        Hypothesized plist name: \(SacrificialIdentity.hypothesizedPlistName)
        Hypothesized label: \(SacrificialIdentity.hypothesizedLabel) (UNOBSERVED)
        Bundle id: \(SacrificialIdentity.bundleID)
        Ad-hoc signing only — not Developer ID / not notarized.
        Mutation later requires a Phase 1B one-time authorization file.
        """
    }
}

enum SacrificialIdentity {
    static let bundleID = "com.desktidy.sacrificial-probe"
    static let hypothesizedPlistName = "com.desktidy.sacrificial.plist"
    static let hypothesizedLabel = "com.desktidy.sacrificial"
    static let bundleSHA256Placeholder = String(repeating: "00", count: 32)
    static let sourceCommitPlaceholder = "0b11c652e364cf47668ba87b4228a0f4ab7974ec"
}
