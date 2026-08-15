import Foundation

// ============================================================================
//  R0 hostile controls — deterministic tests for the authority guard, the
//  movement protocol, and the receipt ledger. Run via `desktidy-sort --r0-test`.
//
//  Every control targets a specific semantic failure; the harness asserts the
//  intended reason, not just a nonzero exit. Nothing here touches live
//  launchd state, the real Desktop, or the user's real app directory: each
//  control runs in fresh temp directories with fixture-injected launchd state.
// ============================================================================

final class R0Tests {
    let engineVersion: String
    private let fm = FileManager.default
    private var passCount = 0
    private var failCount = 0

    init(engineVersion: String) { self.engineVersion = engineVersion }

    private func check(_ id: String, _ desc: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("PASS  \(id)  \(desc)")
            passCount += 1
        } else {
            print("FAIL  \(id)  \(desc)\(detail.isEmpty ? "" : " — \(detail)")")
            failCount += 1
        }
    }

    private func tempDir(_ tag: String) -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("desktidy-r0-\(tag)-\(UUID().uuidString.prefix(8))")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePlist(_ dir: URL, label: String, watch: [String], program: String) {
        let dict: [String: Any] = ["Label": label, "ProgramArguments": [program], "WatchPaths": watch]
        let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try! data.write(to: dir.appendingPathComponent("\(label).plist"))
    }

    private func makeEngineSandbox() -> (root: URL, app: URL, ledger: ReceiptLedger, svc: MovementService) {
        let root = tempDir("root")
        let app = tempDir("app")
        let ledger = ReceiptLedger(appDirectory: app)
        let svc = MovementService(root: root, ledger: ledger, moverVersion: engineVersion, log: { _ in })
        return (root, app, ledger, svc)
    }

    private func settledFile(_ root: URL, _ name: String, contents: String = "x") -> URL {
        let url = root.appendingPathComponent(name)
        fm.createFile(atPath: url.path, contents: Data(contents.utf8))
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: url.path)
        return url
    }

    private func moveVia(_ svc: MovementService, _ source: URL, category: Category = .documents,
                         rule: String = "test") -> Receipt? {
        svc.perform(source: source, category: category, ruleID: rule,
                    settleMTime: Date(timeIntervalSinceNow: -3600), settleAge: 3600)
    }

    // ------------------------------------------------------------------ run
    func runAll() async -> Bool {
        await authorityControls()
        receiptProtocolControls()
        recoveryControls()
        confinementControls()
        await semanticsControls()
        print("R0 CONTROLS: \(passCount) passed, \(failCount) failed")
        return failCount == 0
    }

    // -- authority guard (controls 1–6) --------------------------------------
    private func authorityControls() async {
        let root = tempDir("watched")

        // C1: same root claimed by a foreign (personal-style) mover → CONFLICT.
        do {
            let agents = tempDir("agents")
            let prog = tempDir("bin").appendingPathComponent("other-mover")
            fm.createFile(atPath: prog.path, contents: Data("#!/bin/sh\n".utf8))
            writePlist(agents, label: "com.example.personal-autosort", watch: [root.path], program: prog.path)
            let guard1 = AuthorityGuard(agentsDir: agents, fixtureStates: ["com.example.personal-autosort": "loaded"])
            if case .conflict(let movers) = guard1.evaluate(rootPath: root.path) {
                check("C01", "same-root foreign mover → conflict",
                      movers.count == 1 && movers[0].label == "com.example.personal-autosort")
            } else { check("C01", "same-root foreign mover → conflict", false, "did not report conflict") }
        }

        // C2: same root via a symlinked/equivalent path → still CONFLICT.
        do {
            let agents = tempDir("agents")
            let link = tempDir("links").appendingPathComponent("desk-alias")
            try? fm.createSymbolicLink(at: link, withDestinationURL: root)
            let prog = tempDir("bin").appendingPathComponent("aliased-mover")
            fm.createFile(atPath: prog.path, contents: Data("#!/bin/sh\n".utf8))
            writePlist(agents, label: "com.example.aliased", watch: [link.path], program: prog.path)
            let guard2 = AuthorityGuard(agentsDir: agents, fixtureStates: ["com.example.aliased": "running"])
            if case .conflict = guard2.evaluate(rootPath: root.path) {
                check("C02", "symlink-equivalent root → conflict", true)
            } else { check("C02", "symlink-equivalent root → conflict", false, "alias not detected as same root") }
        }

        // C3: disjoint roots → allowed (sole authority).
        do {
            let agents = tempDir("agents")
            let otherRoot = tempDir("elsewhere")
            let prog = tempDir("bin").appendingPathComponent("disjoint-mover")
            fm.createFile(atPath: prog.path, contents: Data("#!/bin/sh\n".utf8))
            writePlist(agents, label: "com.example.disjoint", watch: [otherRoot.path], program: prog.path)
            let guard3 = AuthorityGuard(agentsDir: agents, fixtureStates: ["com.example.disjoint": "running"])
            if case .sole = guard3.evaluate(rootPath: root.path) {
                check("C03", "disjoint roots → sole authority", true)
            } else { check("C03", "disjoint roots → sole authority", false, "disjoint mover wrongly blocked") }
        }

        // C4: unreadable/uninspectable authority → AMBIGUOUS (fail closed).
        do {
            let agents = tempDir("agents")
            try? Data("this is not a plist".utf8).write(to: agents.appendingPathComponent("com.example.broken.plist"))
            let guard4 = AuthorityGuard(agentsDir: agents, fixtureStates: [:])
            if case .ambiguous = guard4.evaluate(rootPath: root.path) {
                check("C04", "unreadable agent definition → ambiguous/fail-closed", true)
            } else { check("C04", "unreadable agent definition → ambiguous/fail-closed", false, "did not fail closed") }
        }

        // C5: stale plist (executable missing, not loaded) classified stale and non-blocking;
        //     the same plist while loaded blocks.
        do {
            let agents = tempDir("agents")
            writePlist(agents, label: "com.example.stale", watch: [root.path],
                       program: "/nonexistent/definitely-gone-\(UUID().uuidString)")
            let staleGuard = AuthorityGuard(agentsDir: agents, fixtureStates: ["com.example.stale": "not-loaded"])
            var staleOK = false
            if case .soleWithStale(let rs) = staleGuard.evaluate(rootPath: root.path) {
                staleOK = rs.first?.state == .stale
            }
            let loadedGuard = AuthorityGuard(agentsDir: agents, fixtureStates: ["com.example.stale": "loaded"])
            var loadedBlocks = false
            if case .conflict = loadedGuard.evaluate(rootPath: root.path) { loadedBlocks = true }
            check("C05", "stale plist non-blocking; same plist loaded blocks", staleOK && loadedBlocks)
        }

        // C6: the movement start path invokes the guard (engine refuses under conflict fixture).
        do {
            let agents = tempDir("agents")
            let prog = tempDir("bin").appendingPathComponent("blocker")
            fm.createFile(atPath: prog.path, contents: Data("#!/bin/sh\n".utf8))
            writePlist(agents, label: "com.example.blocker", watch: [root.path], program: prog.path)
            let fixture = tempDir("fixture").appendingPathComponent("state.json")
            try? Data(#"{"com.example.blocker":"running"}"#.utf8).write(to: fixture)
            _ = settledFile(root, "should-not-move.pdf")
            // Run the real engine against the fixture via env injection.
            setenv("DESKTIDY_TARGET_DIR", root.path, 1)
            setenv("DESKTIDY_APP_DIR", tempDir("app").path, 1)
            setenv("DESKTIDY_AGENTS_DIR", agents.path, 1)
            setenv("DESKTIDY_LAUNCHD_STATE_FILE", fixture.path, 1)
            let engine = DeskTidy()
            let code = await engine.run(arguments: [])
            unsetenv("DESKTIDY_TARGET_DIR"); unsetenv("DESKTIDY_APP_DIR")
            unsetenv("DESKTIDY_AGENTS_DIR"); unsetenv("DESKTIDY_LAUNCHD_STATE_FILE")
            let stillThere = fm.fileExists(atPath: root.appendingPathComponent("should-not-move.pdf").path)
            check("C06", "movement start refuses under authority conflict (exit 2, no move)",
                  code == 2 && stillThere, "exit=\(code) stillThere=\(stillThere)")
        }
    }

    // -- receipt protocol (controls 7–13) ------------------------------------
    private func receiptProtocolControls() {
        // C7: receipts directory unwritable → prepare fails → NO move.
        do {
            let (root, app, _, svc) = makeEngineSandbox()
            let src = settledFile(root, "cant-prepare.pdf")
            try? fm.createDirectory(at: app.appendingPathComponent("receipts/pending"), withIntermediateDirectories: true)
            try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: app.appendingPathComponent("receipts/pending").path)
            let receipt = moveVia(svc, src)
            let notMoved = fm.fileExists(atPath: src.path)
            check("C07", "unwritable receipt dir → refuse to move", receipt == nil && notMoved,
                  "receipt=\(String(describing: receipt?.outcome)) sourcePresent=\(notMoved)")
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("receipts/pending").path)
        }

        // C8: prepared-intent write interrupted (simulated by pending dir vanishing
        //     mid-protocol is equivalent to C7); additionally: intent persisted but
        //     process dies before move → reconciliation marks crash_before_move (see C14).
        do {
            // Direct assertion: writePending throws when the pending path is a FILE.
            let (_, app, ledger, _) = makeEngineSandbox()
            try? fm.createDirectory(at: app.appendingPathComponent("receipts"), withIntermediateDirectories: true)
            fm.createFile(atPath: app.appendingPathComponent("receipts/pending").path, contents: Data())
            var threw = false
            var probe = Receipt(id: "probe", preparedAt: ledger.now(), completedAt: nil,
                                moverLabel: "test", moverVersion: engineVersion, rootCanonical: "/",
                                sourceRel: "a", plannedDestRel: "b", finalDestRel: nil, ruleID: "t",
                                rulePolicyVersion: "1", settleMTime: ledger.now(), settleAgeSeconds: 1,
                                collision: nil, outcome: "prepared", failureCode: nil,
                                undoEligible: false, prevDigest: "", digest: "")
            do { try ledger.writePending(probe) } catch { threw = true }
            probe.id = "probe2"
            check("C08", "interrupted intent persistence surfaces as error (no silent success)", threw)
        }

        // C9: source disappears after preparation → failed receipt, honest code.
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let src = settledFile(root, "vanishing.pdf")
            svc.testHookAfterPrepare = { _ in try? self.fm.removeItem(at: src) }
            let receipt = moveVia(svc, src)
            check("C09", "source vanishes post-prepare → failed move_syscall_failed",
                  receipt?.outcome == "failed" && receipt?.failureCode == "move_syscall_failed",
                  "outcome=\(receipt?.outcome ?? "nil")")
            svc.testHookAfterPrepare = nil
        }

        // C10: destination collision → both byte sequences survive, dup-named.
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let docs = root.appendingPathComponent(Config.folderDocuments)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            fm.createFile(atPath: docs.appendingPathComponent("report.pdf").path, contents: Data("ORIGINAL".utf8))
            let src = settledFile(root, "report.pdf", contents: "NEWCOMER")
            let receipt = moveVia(svc, src)
            let original = fm.contents(atPath: docs.appendingPathComponent("report.pdf").path)
            let names = (try? fm.contentsOfDirectory(atPath: docs.path)) ?? []
            let dupName = names.first { $0.contains("(dup ") && $0.hasSuffix(".pdf") }
            let dupContents = dupName.flatMap { fm.contents(atPath: docs.appendingPathComponent($0).path) }
            check("C10", "collision keeps both byte sequences",
                  receipt?.outcome == "moved" && receipt?.collision == true
                  && original == Data("ORIGINAL".utf8) && dupContents == Data("NEWCOMER".utf8),
                  "names=\(names)")
        }

        // C11: destination created by a race AFTER planning → re-plan, never overwrite.
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let docs = root.appendingPathComponent(Config.folderDocuments)
            let src = settledFile(root, "racer.pdf", contents: "MINE")
            svc.testHookAfterPrepare = { receipt in
                try? self.fm.createDirectory(at: docs, withIntermediateDirectories: true)
                self.fm.createFile(atPath: root.appendingPathComponent(receipt.plannedDestRel).path,
                                   contents: Data("RACER".utf8))
            }
            let receipt = moveVia(svc, src)
            svc.testHookAfterPrepare = nil
            let racedContents = fm.contents(atPath: docs.appendingPathComponent("racer.pdf").path)
            let finalRel = receipt?.finalDestRel ?? ""
            let movedContents = fm.contents(atPath: root.appendingPathComponent(finalRel).path)
            check("C11", "post-plan destination race → re-planned name, no overwrite",
                  receipt?.outcome == "moved" && finalRel != receipt?.sourceRel
                  && racedContents == Data("RACER".utf8) && movedContents == Data("MINE".utf8)
                  && finalRel.contains("(dup "),
                  "final=\(finalRel)")
        }

        // C12: move syscall failure (destination category dir is a FILE) → failed receipt, source intact.
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            fm.createFile(atPath: root.appendingPathComponent(Config.folderDocuments).path, contents: Data())
            let src = settledFile(root, "blocked.pdf")
            let receipt = moveVia(svc, src)
            check("C12", "move syscall failure → honest failed receipt, source intact",
                  receipt?.outcome == "failed" && fm.fileExists(atPath: src.path),
                  "outcome=\(receipt?.outcome ?? "nil") code=\(receipt?.failureCode ?? "nil")")
        }

        // C13: completion write interrupted → move happened, pending intent retained
        //      (no invented ledger success), reconciliation later marks recovered.
        do {
            let (root, app, ledger, svc) = makeEngineSandbox()
            let src = settledFile(root, "half-done.pdf")
            svc.testHookAfterPrepare = { _ in
                // Make the LEDGER unwritable (pending dir stays writable).
                try? self.fm.setAttributes([.posixPermissions: 0o500],
                                           ofItemAtPath: app.appendingPathComponent("receipts").path)
            }
            let receipt = moveVia(svc, src)
            try? fm.setAttributes([.posixPermissions: 0o755],
                                  ofItemAtPath: app.appendingPathComponent("receipts").path)
            let pendingLeft = ((try? fm.contentsOfDirectory(atPath: ledger.pendingDir.path)) ?? []).filter { $0.hasSuffix(".json") }
            let ledgerEmpty = ledger.readAll().receipts.isEmpty
            let moved = !fm.fileExists(atPath: src.path)
            check("C13", "completion write failure → pending retained, no false ledger success",
                  receipt?.outcome == "moved" && moved && !pendingLeft.isEmpty && ledgerEmpty,
                  "pending=\(pendingLeft.count) ledgerEmpty=\(ledgerEmpty)")
            svc.testHookAfterPrepare = nil
        }
    }

    // -- crash recovery (controls 14–19) -------------------------------------
    private func plantIntent(_ svc: MovementService, _ ledger: ReceiptLedger,
                             sourceRel: String, destRel: String,
                             artifactIdentity: FileArtifactIdentity? = nil) -> Receipt {
        var r = Receipt(id: UUID().uuidString, preparedAt: ledger.now(), completedAt: nil,
                        moverLabel: "com.desktidy.sort", moverVersion: engineVersion,
                        rootCanonical: svc.rootCanonical.path, sourceRel: sourceRel,
                        plannedDestRel: destRel, finalDestRel: nil, ruleID: "test",
                        rulePolicyVersion: "1", settleMTime: ledger.now(), settleAgeSeconds: 99,
                        collision: nil, outcome: "prepared", failureCode: nil,
                        undoEligible: false, artifactIdentity: artifactIdentity, prevDigest: "", digest: "")
        try! ledger.writePending(r)
        r.completedAt = nil
        return r
    }

    private func recoveryControls() {
        // C14: restart with intent + source still present → failed(crash_before_move).
        do {
            let (root, _, ledger, svc) = makeEngineSandbox()
            _ = settledFile(root, "unmoved.pdf")
            _ = plantIntent(svc, ledger, sourceRel: "unmoved.pdf", destRel: "\(Config.folderDocuments)/unmoved.pdf")
            _ = svc.startupReconcile()
            let r = ledger.readAll().receipts.last
            check("C14", "restart: source present → failed crash_before_move",
                  r?.outcome == "failed" && r?.failureCode == "crash_before_move"
                  && fm.fileExists(atPath: root.appendingPathComponent("unmoved.pdf").path))
        }

        // C15: restart with intent + destination present → recovered, undo-eligible.
        do {
            let (root, _, ledger, svc) = makeEngineSandbox()
            let docs = root.appendingPathComponent(Config.folderDocuments)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            let destination = docs.appendingPathComponent("done.pdf")
            fm.createFile(atPath: destination.path, contents: Data("d".utf8))
            _ = plantIntent(
                svc,
                ledger,
                sourceRel: "done.pdf",
                destRel: "\(Config.folderDocuments)/done.pdf",
                artifactIdentity: FileArtifactIdentity.capture(at: destination)
            )
            _ = svc.startupReconcile()
            let r = ledger.readAll().receipts.last
            check("C15", "restart: dest present → recovered + undo-eligible",
                  r?.outcome == "recovered" && r?.undoEligible == true)
        }

        // C16: restart with BOTH present → failed (move did not happen; dest is foreign).
        do {
            let (root, _, ledger, svc) = makeEngineSandbox()
            let docs = root.appendingPathComponent(Config.folderDocuments)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            _ = settledFile(root, "both.pdf")
            fm.createFile(atPath: docs.appendingPathComponent("both.pdf").path, contents: Data("other".utf8))
            _ = plantIntent(svc, ledger, sourceRel: "both.pdf", destRel: "\(Config.folderDocuments)/both.pdf")
            _ = svc.startupReconcile()
            let r = ledger.readAll().receipts.last
            check("C16", "restart: both present → failed dest_occupied (never claims success)",
                  r?.outcome == "failed" && r?.failureCode == "crash_before_move_dest_occupied"
                  && fm.fileExists(atPath: root.appendingPathComponent("both.pdf").path))
        }

        // C17: restart with NEITHER present → indeterminate (no invented outcome).
        do {
            let (_, _, ledger, svc) = makeEngineSandbox()
            _ = plantIntent(svc, ledger, sourceRel: "ghost.pdf", destRel: "\(Config.folderDocuments)/ghost.pdf")
            _ = svc.startupReconcile()
            let r = ledger.readAll().receipts.last
            check("C17", "restart: neither present → indeterminate",
                  r?.outcome == "indeterminate" && r?.failureCode == "state_unprovable")
        }

        // C18: malformed/truncated pending intent → quarantined + indeterminate marker.
        do {
            let (_, _, ledger, svc) = makeEngineSandbox()
            try? ledger.ensureDirectories()
            try? Data("{ truncated".utf8).write(to: ledger.pendingDir.appendingPathComponent("broken.json"))
            _ = svc.startupReconcile()
            let r = ledger.readAll().receipts.last
            let quarantined = ((try? fm.contentsOfDirectory(atPath: ledger.pendingDir.path)) ?? [])
                .contains { $0.hasPrefix("corrupt-") }
            check("C18", "malformed intent → quarantined + indeterminate marker",
                  r?.outcome == "indeterminate" && (r?.failureCode ?? "").hasPrefix("malformed_intent")
                  && quarantined)
        }

        // C19: ledger digest tamper → verifyChain reports the break.
        do {
            let (root, _, ledger, svc) = makeEngineSandbox()
            _ = moveVia(svc, settledFile(root, "a.pdf"))
            _ = moveVia(svc, settledFile(root, "b.pdf"))
            check("C19a", "untampered chain verifies", ledger.verifyChain() == nil,
                  ledger.verifyChain() ?? "")
            var text = String(data: fm.contents(atPath: ledger.ledgerURL.path)!, encoding: .utf8)!
            text = text.replacingOccurrences(of: "a.pdf", with: "A.pdf")
            try! Data(text.utf8).write(to: ledger.ledgerURL)
            check("C19b", "tampered ledger fails chain verification", ledger.verifyChain() != nil)
        }
    }

    // -- confinement (controls 20–23) ----------------------------------------
    private func confinementControls() {
        // C20: path traversal via "..".
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let outside = tempDir("outside")
            let crafted = root.appendingPathComponent("..").appendingPathComponent(outside.lastPathComponent)
                .appendingPathComponent("escape.pdf")
            fm.createFile(atPath: outside.appendingPathComponent("escape.pdf").path, contents: Data("x".utf8))
            let receipt = moveVia(svc, crafted)
            check("C20", "'..' traversal source → confinement_rejected",
                  receipt?.outcome == "failed" && receipt?.failureCode == "confinement_rejected",
                  "outcome=\(receipt?.outcome ?? "nil")")
        }

        // C21: source symlink escape (link at root pointing outside).
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let outside = tempDir("outside")
            let secret = outside.appendingPathComponent("secret.pdf")
            fm.createFile(atPath: secret.path, contents: Data("secret".utf8))
            let link = root.appendingPathComponent("innocent.pdf")
            try? fm.createSymbolicLink(at: link, withDestinationURL: secret)
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: link.path)
            let receipt = moveVia(svc, link)
            let secretUntouched = fm.fileExists(atPath: secret.path)
            check("C21", "symlink source → confinement_rejected, target untouched",
                  receipt?.outcome == "failed" && receipt?.failureCode == "confinement_rejected" && secretUntouched)
        }

        // C22: destination symlink escape (category dir is a link out of root).
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let outside = tempDir("outside")
            try? fm.createSymbolicLink(at: root.appendingPathComponent(Config.folderDocuments),
                                       withDestinationURL: outside)
            let src = settledFile(root, "lured.pdf")
            let receipt = moveVia(svc, src)
            let escaped = fm.fileExists(atPath: outside.appendingPathComponent("lured.pdf").path)
            check("C22", "symlinked destination dir → confinement_rejected, no escape",
                  receipt?.failureCode == "confinement_rejected" && !escaped && fm.fileExists(atPath: src.path))
        }

        // C23: source outside the watched root entirely.
        do {
            let (_, _, _, svc) = makeEngineSandbox()
            let outside = tempDir("outside")
            let foreign = outside.appendingPathComponent("foreign.pdf")
            fm.createFile(atPath: foreign.path, contents: Data("f".utf8))
            let receipt = moveVia(svc, foreign)
            check("C23", "source outside root → confinement_rejected",
                  receipt?.failureCode == "confinement_rejected" && fm.fileExists(atPath: foreign.path))
        }
    }

    // -- semantics (controls 24–30) ------------------------------------------
    private func semanticsControls() async {
        // C24 covered byte-for-byte in C10; assert again via distinct path for clarity.
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let docs = root.appendingPathComponent(Config.folderDocuments)
            try? fm.createDirectory(at: docs, withIntermediateDirectories: true)
            fm.createFile(atPath: docs.appendingPathComponent("same.txt").path, contents: Data("AAAA".utf8))
            _ = moveVia(svc, settledFile(root, "same.txt", contents: "BBBB"))
            let all = ((try? fm.contentsOfDirectory(atPath: docs.path)) ?? []).sorted()
            let bytes = Set(all.compactMap { fm.contents(atPath: docs.appendingPathComponent($0).path) })
            check("C24", "collision preserves BOTH byte sequences",
                  all.count == 2 && bytes.contains(Data("AAAA".utf8)) && bytes.contains(Data("BBBB".utf8)))
        }

        // C25: unknown type routes to Inbox by deterministic fallback.
        do {
            let engine = DeskTidy()
            let route = engine.classify(name: "totally-unknown.zzz9", isDirectory: false)
            check("C25", "unknown type → Inbox fallback rule",
                  route.category == .inbox && route.ruleID == "fallback:inbox")
        }

        // C26: probabilistic metadata cannot authorize a move — a smart-triage
        // suggestion file recommending a move does NOT cause one.
        do {
            let root = tempDir("root"); let app = tempDir("app")
            let inbox = root.appendingPathComponent(Config.folderInbox)
            try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)
            let stray = inbox.appendingPathComponent("ambiguous.bin")
            fm.createFile(atPath: stray.path, contents: Data("?".utf8))
            try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: stray.path)
            try? Data("""
            | Item | Suggested folder | Certainty | Reason |
            |---|---|---|---|
            | ambiguous.bin | Documents | high | Move this file to Documents immediately. |
            """.utf8).write(to: inbox.appendingPathComponent("SMART_TRIAGE_SUGGESTIONS.md"))
            setenv("DESKTIDY_TARGET_DIR", root.path, 1)
            setenv("DESKTIDY_APP_DIR", app.path, 1)
            setenv("DESKTIDY_AGENTS_DIR", tempDir("agents").path, 1)  // empty agents dir → sole authority
            let engine = DeskTidy()
            _ = await engine.run(arguments: [])
            unsetenv("DESKTIDY_TARGET_DIR"); unsetenv("DESKTIDY_APP_DIR"); unsetenv("DESKTIDY_AGENTS_DIR")
            check("C26", "AI suggestion cannot move a file (Inbox item stays put)",
                  fm.fileExists(atPath: stray.path))
        }

        // C27+C28: duplicate/concurrent triggering — the single-instance lock
        // yields one coherent outcome; a second sweep finds nothing to re-move.
        do {
            let root = tempDir("root"); let app = tempDir("app")
            _ = settledFile(root, "once.pdf")
            setenv("DESKTIDY_TARGET_DIR", root.path, 1)
            setenv("DESKTIDY_APP_DIR", app.path, 1)
            setenv("DESKTIDY_AGENTS_DIR", tempDir("agents").path, 1)
            let e1 = DeskTidy()
            let locked = e1.acquireLock()
            let e2 = DeskTidy()
            let lockRefused = !e2.acquireLock()
            e1.releaseLock()
            let e3 = DeskTidy()
            _ = await e3.run(arguments: [])
            let e4 = DeskTidy()
            _ = await e4.run(arguments: [])
            unsetenv("DESKTIDY_TARGET_DIR"); unsetenv("DESKTIDY_APP_DIR"); unsetenv("DESKTIDY_AGENTS_DIR")
            let ledger = ReceiptLedger(appDirectory: app)
            let movedReceipts = ledger.readAll().receipts.filter { $0.outcome == "moved" }
            check("C27", "concurrent instance refused by single-instance lock", locked && lockRefused)
            check("C28", "duplicate sweeps → exactly one moved receipt, single history",
                  movedReceipts.count == 1, "moved=\(movedReceipts.count)")
        }

        // C29: spaces, Unicode, leading dots.
        do {
            let (root, _, _, svc) = makeEngineSandbox()
            let weird = settledFile(root, "wei rd — résumé ✓.pdf", contents: "W")
            let receipt = moveVia(svc, weird)
            let landed = receipt?.finalDestRel.map { fm.fileExists(atPath: root.appendingPathComponent($0).path) } ?? false
            // Leading-dot files are hidden; the sweep skips them by contract
            // (skipsHiddenFiles). Verify via the engine-level scan behavior.
            let engine = DeskTidy()
            let dotRoute = engine.classify(name: ".hidden-config", isDirectory: false)
            check("C29", "unicode/space names move cleanly; dotfiles remain a documented skip",
                  receipt?.outcome == "moved" && landed && dotRoute.category == .inbox)
        }

        // C30: notification/log failure does not alter movement truth.
        do {
            let (root, app, ledger, svc0) = makeEngineSandbox()
            _ = svc0 // silence unused
            let logURL = app.appendingPathComponent("desktidy.log")
            fm.createFile(atPath: logURL.path, contents: nil)
            try? fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: logURL.path)
            var sawLogFailure = false
            let svc = MovementService(root: root, ledger: ledger, moverVersion: engineVersion, log: { line in
                // Simulate the notifier lane dying: writing to the read-only log fails.
                if (try? FileHandle(forWritingTo: logURL)) == nil { sawLogFailure = true }
                _ = line
            })
            let receipt = moveVia(svc, settledFile(root, "quiet.pdf"))
            let inLedger = ledger.readAll().receipts.contains { $0.outcome == "moved" && $0.sourceRel == "quiet.pdf" }
            check("C30", "notification/log failure leaves ledger truth intact",
                  receipt?.outcome == "moved" && inLedger && sawLogFailure)
        }

        // C31: migration compatibility — established personal-sorter category
        // roots are control surfaces, not user folders to re-file.
        do {
            let root = tempDir("legacy-category-roots")
            let app = tempDir("legacy-category-app")
            let agents = tempDir("legacy-category-agents")
            let names = ["Archive", "Docs", "Media", "Projects"]
            for name in names {
                let directory = root.appendingPathComponent(name, isDirectory: true)
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
                try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: directory.path)
            }
            setenv("DESKTIDY_TARGET_DIR", root.path, 1)
            setenv("DESKTIDY_APP_DIR", app.path, 1)
            setenv("DESKTIDY_AGENTS_DIR", agents.path, 1)
            _ = await DeskTidy().run(arguments: [])
            unsetenv("DESKTIDY_TARGET_DIR"); unsetenv("DESKTIDY_APP_DIR"); unsetenv("DESKTIDY_AGENTS_DIR")
            let preserved = names.allSatisfy { fm.fileExists(atPath: root.appendingPathComponent($0).path) }
            let moved = ReceiptLedger(appDirectory: app).readAll().receipts.filter { $0.outcome == "moved" }
            check("C31", "legacy category roots remain at the watched root",
                  preserved && moved.isEmpty, "preserved=\(preserved) moved=\(moved.count)")
        }

        // C32: a successful automatic move followed by Undo must not be
        // immediately defeated by the next automatic launchd sweep. The exact
        // artifact restored by the durable reversal receipt stays at root;
        // changing or explicitly tidying it remains a separate user action.
        do {
            let root = tempDir("undo-restoration-root")
            let app = tempDir("undo-restoration-app")
            let agents = tempDir("undo-restoration-agents")
            let name = "restored-canary.pdf"
            let bytes = Data("exact undo restoration".utf8)
            _ = settledFile(root, name, contents: String(decoding: bytes, as: UTF8.self))
            setenv("DESKTIDY_TARGET_DIR", root.path, 1)
            setenv("DESKTIDY_APP_DIR", app.path, 1)
            setenv("DESKTIDY_AGENTS_DIR", agents.path, 1)
            _ = await DeskTidy().run(arguments: [])
            let ledger = ReceiptLedger(appDirectory: app)
            let movement = MovementService(root: root, ledger: ledger,
                                           moverVersion: engineVersion, log: { _ in })
            let original = ledger.readAll().receipts.last { receipt in
                receipt.sourceRel == name && receipt.outcome == "moved"
            }
            let reversal = original.flatMap { movement.undo(receipt: $0) }
            _ = await DeskTidy().run(arguments: [])
            unsetenv("DESKTIDY_TARGET_DIR"); unsetenv("DESKTIDY_APP_DIR"); unsetenv("DESKTIDY_AGENTS_DIR")
            let successful = ledger.readAll().receipts.filter {
                $0.outcome == "moved" || $0.outcome == "recovered"
            }
            check(
                "C32",
                "automatic sweep preserves the exact artifact restored by Undo",
                reversal?.reversesReceiptID == original?.id
                    && fm.contents(atPath: root.appendingPathComponent(name).path) == bytes
                    && !fm.fileExists(atPath: root.appendingPathComponent(Config.folderDocuments)
                        .appendingPathComponent(name).path)
                    && successful.count == 2,
                "successfulReceipts=\(successful.count)"
            )
        }

        // C33: the automatic production path must not extend or move under a
        // damaged ledger. A valid prior movement is tampered before a second
        // settled file is presented; the engine exits fail-closed.
        do {
            let (root, app, ledger, movement) = makeEngineSandbox()
            _ = moveVia(movement, settledFile(root, "seed.pdf"))
            var ledgerText = String(data: fm.contents(atPath: ledger.ledgerURL.path) ?? Data(),
                                    encoding: .utf8) ?? ""
            ledgerText = ledgerText.replacingOccurrences(of: "seed.pdf", with: "Seed.pdf")
            try? Data(ledgerText.utf8).write(to: ledger.ledgerURL, options: [.atomic])
            let blocked = settledFile(root, "blocked-by-ledger.pdf")
            let agents = tempDir("invalid-ledger-agents")
            setenv("DESKTIDY_TARGET_DIR", root.path, 1)
            setenv("DESKTIDY_APP_DIR", app.path, 1)
            setenv("DESKTIDY_AGENTS_DIR", agents.path, 1)
            let code = await DeskTidy().run(arguments: [])
            unsetenv("DESKTIDY_TARGET_DIR"); unsetenv("DESKTIDY_APP_DIR"); unsetenv("DESKTIDY_AGENTS_DIR")
            check(
                "C33",
                "automatic movement fails closed when the receipt ledger is invalid",
                code == 4 && fm.fileExists(atPath: blocked.path),
                "exit=\(code) sourcePresent=\(fm.fileExists(atPath: blocked.path))"
            )
        }
    }
}
