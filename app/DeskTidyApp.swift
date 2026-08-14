import AppKit
import SwiftUI

// ============================================================================
//  DeskTidy menu-bar app — R1A: a read-only trust surface.
//
//  Everything shown is EffectiveState.compute() — the same derivation the CLI
//  prints with `--effective-state`. This file contains presentation only:
//  no file moves, no launchd mutation, no receipt writes, no model calls.
//
//  R1A actions (all read-only):
//    • Reveal watched folder in Finder
//    • Reveal receipts folder (only when it exists)
//    • Copy diagnostic to clipboard
//    • Refresh, Quit
//
//  Compiled with the shared sources: Config.swift, Authority.swift,
//  Receipts.swift, EffectiveState.swift (see scripts/build-app.sh).
// ============================================================================

@MainActor
final class StateStore: ObservableObject {
    @Published var report: EffectiveStateReport = EffectiveState.compute()

    func refresh() { report = EffectiveState.compute() }
}

@main
struct DeskTidyApp: App {
    @StateObject private var store = StateStore()

    init() {
        // Headless CI smoke: prove the app binary computes the same effective
        // state as the CLI, without needing a GUI session. Prints the shared
        // model's diagnostic and exits before any Scene is built.
        if CommandLine.arguments.contains("--smoke") {
            let report = EffectiveState.compute()
            print(EffectiveState.diagnostic(report))
            print("SMOKE overall=\(report.overall.rawValue)")
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            // Template-rendered SF Symbol: legible on any wallpaper, filled
            // triangle/pause variants signal non-healthy states at a glance.
            Image(systemName: EffectiveState.menuBarSymbol(for: store.report.overall))
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var store: StateStore
    // Periodic re-derivation on the main runloop — SwiftUI keeps the closure
    // main-actor isolated, which also satisfies the macOS 14 toolchain's
    // stricter concurrency checking (no manual Timer/Task capture).
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var r: EffectiveStateReport { store.report }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // -- headline state (fail-closed wording from the shared model)
            HStack(spacing: 8) {
                Image(systemName: EffectiveState.menuBarSymbol(for: r.overall))
                    .foregroundStyle(color(for: r.overall))
                Text(EffectiveState.statusLine(for: r))
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            grid
            if r.overall == .foreignConflict {
                Text("DeskTidy refuses to sort a folder another automation watches. Use that service's own controls, or point DeskTidy at a different folder.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if r.suggestionsPresent {
                Text("Smart-triage suggestions are waiting in Inbox (suggestions only — nothing is moved automatically).")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // -- read-only actions
            HStack(spacing: 8) {
                Button("Reveal Folder") { reveal(path: r.watchedTarget) }
                    .disabled(!r.targetExists)
                Button("Reveal Receipts") { revealReceipts() }
                    .disabled(!receiptsExist())
                Button("Copy Diagnostic") { copyDiagnostic() }
            }
            .controlSize(.small)

            HStack {
                Button("Refresh") { store.refresh() }.controlSize(.small)
                Spacer()
                Text(r.moverVersion).font(.system(size: 10)).foregroundStyle(.tertiary)
                Button("Quit") { NSApplication.shared.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { store.refresh() }
        .onReceive(ticker) { _ in store.refresh() }
    }

    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("Watching").gridLabel()
                Text(EffectiveState.shortPath(r.watchedTarget)).gridValue()
            }
            GridRow {
                Text("Authority").gridLabel()
                Text(r.effectiveMoverLabel ?? "unprovable").gridValue()
            }
            GridRow {
                Text("Agent").gridLabel()
                Text(r.productAgentState).gridValue()
            }
            GridRow {
                Text("Receipts").gridLabel()
                Text(r.ledger).gridValue()
            }
        }
    }

    private func color(for state: OverallState) -> Color {
        switch state {
        case .runningHealthy:  return .green
        case .pausedNotLoaded: return .secondary
        case .foreignConflict, .degradedLedger: return .orange
        case .ambiguous:       return .yellow
        }
    }

    // -- read-only actions ---------------------------------------------------
    private func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func receiptsDir() -> URL {
        let env = ProcessInfo.processInfo.environment
        let base: URL
        if let a = env["DESKTIDY_APP_DIR"], !a.isEmpty {
            base = URL(fileURLWithPath: (a as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/DeskTidy", isDirectory: true)
        }
        return base.appendingPathComponent("receipts", isDirectory: true)
    }

    private func receiptsExist() -> Bool {
        FileManager.default.fileExists(atPath: receiptsDir().appendingPathComponent("ledger.jsonl").path)
    }

    private func revealReceipts() {
        NSWorkspace.shared.activateFileViewerSelecting(
            [receiptsDir().appendingPathComponent("ledger.jsonl")])
    }

    private func copyDiagnostic() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(EffectiveState.diagnostic(r), forType: .string)
    }
}

private extension Text {
    func gridLabel() -> some View {
        self.font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
    }
    func gridValue() -> some View {
        self.font(.system(size: 10.5, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
