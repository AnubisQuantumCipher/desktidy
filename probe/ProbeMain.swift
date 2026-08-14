import Foundation

// Sacrificial operator probe. Default is read-only plan/status.
// Phase 1A.1: measure evidence, prepare a sealed grant, then STOP.
// Does not construct ProductionSMAdapter or invoke mutation methods.
@main
struct SacrificialProbe {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--help") || args.count == 1 || args.contains("--plan") || args.contains("--status") {
            print(planText())
            if args.contains("--plan") || args.contains("--status") { print("mode: read-only") }
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
        switch SecureAuthFile.openOnce(path: authPath) {
        case .refused(let r):
            fputs("probe: \(r)\n", stderr)
            exit(3)
        case .ok(let authBytes):
            guard let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]) as URL? else {
                fputs("probe: cannot locate running executable\n", stderr)
                exit(3)
            }
            switch ProbeIdentity.measureRunning(executableURL: exe, bundle: Bundle.main) {
            case .refused(let r):
                fputs("probe: \(r)\n", stderr)
                exit(3)
            case .ok(let identity):
                switch ProtectedRootInventory.load() {
                case .failed(let r):
                    fputs("probe: \(r)\n", stderr)
                    exit(3)
                case .ok(let inv):
                    guard case .ok(let parsed) = MutationInterlock.parseAuthorization(authBytes) else {
                        fputs("probe: authorization parse failed\n", stderr)
                        exit(3)
                    }
                    let first = ProductionAuthoritySnapshot.live.snapshot(rootPath: parsed.sacrificialRoot)
                    let second = ProductionAuthoritySnapshot.live.snapshot(rootPath: parsed.sacrificialRoot)
                    guard case .ok(let a1) = first, case .ok(let a2) = second else {
                        fputs("probe: sacrificial root/authority observation failed\n", stderr)
                        exit(3)
                    }
                    let home = AuthorityGuard.canonicalize(FileManager.default.homeDirectoryForCurrentUser.path)
                    switch MutationBoundary.prepare(
                        authBytes: authBytes,
                        identity: identity,
                        compiledSourceCommit: CompiledProbeIdentity.sourceCommit,
                        operation: registering ? .register : .unregister,
                        first: a1, second: a2,
                        desktop: inv.desktop, home: home,
                        protected: inv.protected, productionTarget: inv.production
                    ) {
                    case .refused(let r):
                        fputs("probe: interlock refused — \(r)\n", stderr)
                        exit(3)
                    case .prepared(let grant):
                        print("GRANT_PREPARED")
                        print("operation=\(grant.operation.rawValue)")
                        print("executableSHA256=\(grant.executableSHA256)")
                        print("sourceCommit=\(grant.sourceCommit)")
                        print("root=\(grant.rootCanonical)")
                        print("nonce=\(grant.nonce)")
                        if !args.contains("--commit-mutation") {
                            print("STOP_BEFORE_PRODUCTION_ADAPTER")
                            print("ledger_constructions=\(ProductionMutationLedger.constructions)")
                            print("ledger_registers=\(ProductionMutationLedger.registerInvocations)")
                            exit(4)
                        }
                        let adapter = ProductionSMAdapter()
                        let plist = SacrificialIdentity.hypothesizedPlistName
                        let mutation: Result<Void, SMAdapterError>
                        if registering {
                            mutation = adapter.requestRegister(plistName: plist, grant: grant)
                        } else {
                            mutation = adapter.requestUnregister(plistName: plist, grant: grant)
                        }
                        let st = adapter.status(plistName: plist)
                        print("MUTATION_ATTEMPTED")
                        switch mutation {
                        case .success:
                            print("adapter_result=success")
                        case .failure(let e):
                            print("adapter_result=failedClosed")
                            print("adapter_error=\(e)")
                        }
                        switch st {
                        case .success(let s): print("status=\(s)")
                        case .failure(let e): print("status_error=\(e)")
                        }
                        print("ledger_constructions=\(ProductionMutationLedger.constructions)")
                        print("ledger_registers=\(ProductionMutationLedger.registerInvocations)")
                        print("ledger_unregisters=\(ProductionMutationLedger.unregisterInvocations)")
                        switch mutation {
                        case .success: exit(0)
                        case .failure: exit(5)
                        }
                    }
                }
            }
        }
    }

    static func planText() -> String {
        """
        DeskTidy sacrificial SMAppService probe (NON-PRODUCTION)
        Default: measure, prepare grant, STOP (exit 4). No adapter construction.
        Phase 1B observation requires --commit-mutation after a sealed grant.
        Hosted CI and the public-boundary suite must not pass that flag
        with a valid authorization.
        Hypothesized plist name: \(SacrificialIdentity.hypothesizedPlistName)
        Hypothesized label: \(SacrificialIdentity.hypothesizedLabel) (UNOBSERVED)
        Bundle id: \(SacrificialIdentity.bundleID)
        Compiled source commit: \(CompiledProbeIdentity.sourceCommit)
        Ad-hoc signing only — not Developer ID / not notarized.
        """
    }
}

enum SacrificialIdentity {
    static let bundleID = "com.desktidy.sacrificial-probe"
    static let hypothesizedPlistName = "com.desktidy.sacrificial.plist"
    static let hypothesizedLabel = "com.desktidy.sacrificial"
}
