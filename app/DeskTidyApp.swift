import AppKit
import SwiftUI

// The menu is a presentation boundary. It never derives target, authority, or
// receipt state itself: every product-state read and mutation goes through the
// injected CanonicalApplicationCore.

enum NativeMenuTarget {
    case available(path: String, source: String)
    case unavailable(path: String, source: String)
    case invalid(reason: String, source: String, attemptedPath: String?)
}

enum NativeMenuConfiguration {
    case missing
    case configured(String)
    case invalid(String)
}

@MainActor
final class NativeMenuModel: ObservableObject {
    @Published private(set) var effectiveState: CanonicalEffectiveState
    @Published private(set) var target: NativeMenuTarget
    @Published private(set) var configuration: NativeMenuConfiguration
    @Published private(set) var lifecycle: CanonicalLifecycleStatus
    @Published private(set) var lastCommandMessage: String?

    private var core: CanonicalApplicationCore

    init(core: CanonicalApplicationCore) {
        self.core = core
        effectiveState = core.effectiveState()
        target = .invalid(reason: "Loading target", source: "loading", attemptedPath: nil)
        configuration = .missing
        lifecycle = core.installationStatus()
        refresh()
    }

    func refresh() {
        effectiveState = core.effectiveState()
        refreshTarget()
        refreshConfiguration()
        lifecycle = core.installationStatus()
    }

    func setTarget(_ path: String) -> CanonicalCommandResult {
        let result = core.setTarget(path)
        record(result)
        refresh()
        return result
    }

    func pause() {
        record(core.pause())
        refresh()
    }

    func resume() {
        record(core.resume())
        refresh()
    }

    func replaceCore(with replacement: CanonicalApplicationCore, retaining message: String?) {
        core = replacement
        lastCommandMessage = message
        refresh()
    }

    func diagnostic() -> String { core.diagnostic() }

    func receiptsDirectory() -> URL { core.receiptsDirectory() }

    func hasRevealableReceipts() -> Bool {
        !core.history().receipts.isEmpty || !core.commandHistory().isEmpty
    }

    private func refreshTarget() {
        switch core.target() {
        case .resolved(let path, let source, true):
            target = .available(path: path, source: source.rawValue)
        case .resolved(let path, let source, false):
            target = .unavailable(path: path, source: source.rawValue)
        case .invalid(let reason, let source, let attemptedPath):
            target = .invalid(reason: reason, source: source.rawValue, attemptedPath: attemptedPath)
        }
    }

    private func refreshConfiguration() {
        switch core.targetConfiguration() {
        case nil:
            configuration = .missing
        case .ok(let target):
            configuration = .configured(target)
        case .failed(let reason):
            configuration = .invalid(reason)
        }
    }

    private func record(_ result: CanonicalCommandResult) {
        if let refusal = result.refusal {
            lastCommandMessage = "DeskTidy refused \(result.command.rawValue): \(describe(refusal))"
            return
        }
        let receipt = result.receiptID.map { " Receipt \($0)." } ?? ""
        lastCommandMessage = "\(result.command.rawValue) \(result.outcome.rawValue).\(receipt)"
    }

    private func describe(_ refusal: CanonicalCoreRefusal) -> String {
        switch refusal {
        case .invalidTargetConfiguration:
            return "the saved target configuration is invalid."
        case .unresolvedTarget(let reason):
            return "the target cannot be resolved: \(reason)"
        case .targetMismatch:
            return "the configured target changed before the command could run."
        case .targetUnavailable:
            return "the target is unavailable."
        case .paused:
            return "DeskTidy is paused."
        case .invalidPauseDuration:
            return "the requested pause duration is invalid."
        case .unauthorized(let reason):
            return reason
        case .invalidTarget(let path):
            return "\(path) is not an available folder."
        case .invalidReceipt(let id):
            return "receipt \(id) is invalid."
        case .receiptUnavailable:
            return "no receipt is available."
        }
    }
}

/// The only product composition root. Production construction and target-driven
/// core replacement happen here; the model is given an already-built core.
@MainActor
final class DeskTidyApplicationBoundary: ObservableObject {
    @Published private(set) var model: NativeMenuModel
    private let coreFactory: () -> CanonicalApplicationCore

    init(coreFactory: @escaping () -> CanonicalApplicationCore) {
        self.coreFactory = coreFactory
        model = NativeMenuModel(core: coreFactory())
    }

    func setTarget(_ path: String) {
        let result = model.setTarget(path)
        guard result.outcome == .completed, result.refusal == nil else { return }
        let message = model.lastCommandMessage
        model.replaceCore(with: coreFactory(), retaining: message)
    }
}

@main
struct DeskTidyApp: App {
    @StateObject private var boundary: DeskTidyApplicationBoundary

    /// Production dependency construction occurs only at this app boundary.
    init() {
        // Headless CI smoke stays read-only and exits before the menu scene
        // can be constructed. It exercises the same state derivation as CLI.
        if CommandLine.arguments.contains("--smoke") {
            let report = EffectiveState.compute()
            print(EffectiveState.diagnostic(report))
            print("SMOKE overall=\(report.overall.rawValue)")
            exit(0)
        }
        _boundary = StateObject(
            wrappedValue: DeskTidyApplicationBoundary(coreFactory: { CanonicalApplicationCore.live() })
        )
    }

    /// Deterministic UI/test injection. Callers provide an isolated fixture core,
    /// so constructing this app never reads or writes the user's Desktop.
    init(fixtureCore: CanonicalApplicationCore) {
        _boundary = StateObject(
            wrappedValue: DeskTidyApplicationBoundary(coreFactory: { fixtureCore })
        )
    }

    var body: some Scene {
        MenuBarExtra {
            NativeMenuContent(boundary: boundary)
        } label: {
            Image(systemName: EffectiveState.menuBarSymbol(for: boundary.model.effectiveState.effective.overall))
                .accessibilityLabel("DeskTidy status")
        }
        .menuBarExtraStyle(.window)
    }
}

struct NativeMenuContent: View {
    @ObservedObject var boundary: DeskTidyApplicationBoundary
    @ObservedObject private var model: NativeMenuModel
    private let ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    init(boundary: DeskTidyApplicationBoundary) {
        self.boundary = boundary
        _model = ObservedObject(wrappedValue: boundary.model)
    }

    private var report: EffectiveStateReport { model.effectiveState.effective }
    private var conflict: Bool { report.overall == .foreignConflict }
    private var setupRequired: Bool {
        switch (model.configuration, model.target) {
        case (.missing, _), (.invalid, _), (_, .invalid), (_, .unavailable):
            return true
        case (.configured, .available):
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headline
            Divider()
            details
            configuration
            if let message = model.lastCommandMessage {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(conflict ? .orange : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Configuration result: \(message)")
            }
            if conflict {
                Text("DeskTidy will not sort this folder while another automation owns it. DeskTidy cannot disable that automation; choose a different folder or use its own controls.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Authority conflict")
            }
            if report.suggestionsPresent {
                Text("Smart-triage suggestions are waiting in Inbox. Suggestions never move files automatically.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Divider()
            diagnostics
            footer
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { model.refresh() }
        .onReceive(ticker) { _ in model.refresh() }
    }

    private var headline: some View {
        HStack(spacing: 8) {
            Image(systemName: EffectiveState.menuBarSymbol(for: report.overall))
                .foregroundStyle(color(for: report.overall))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(headlineStatus)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(lifecycleDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DeskTidy status: \(headlineStatus). \(lifecycleDescription)")
    }

    private var details: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Text("Watching").gridLabel()
                Text(targetDescription).gridValue()
            }
            GridRow {
                Text("Authority").gridLabel()
                Text(report.effectiveMoverLabel ?? "unprovable").gridValue()
            }
            GridRow {
                Text("Agent").gridLabel()
                Text(report.productAgentState).gridValue()
            }
            GridRow {
                Text("Receipts").gridLabel()
                Text(report.ledger).gridValue()
            }
        }
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(setupRequired ? "Onboarding" : "Settings")
                .font(.system(size: 11, weight: .semibold))
            Text(configurationDescription)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(setupRequired ? "Choose Folder…" : "Change Folder…") {
                    chooseTarget()
                }
                .accessibilityLabel(setupRequired ? "Choose DeskTidy folder" : "Change DeskTidy folder")
                .accessibilityHint("Opens a folder picker. The selected folder is checked by DeskTidy before it is configured.")

                if !conflict {
                    Button(model.effectiveState.isPaused ? "Resume DeskTidy" : "Pause DeskTidy") {
                        if model.effectiveState.isPaused {
                            model.resume()
                        } else {
                            model.pause()
                        }
                    }
                    .accessibilityLabel(model.effectiveState.isPaused ? "Resume DeskTidy" : "Pause DeskTidy")
                    .accessibilityHint("Changes only DeskTidy's own paused state.")
                }
            }
            .controlSize(.small)
        }
    }

    private var diagnostics: some View {
        HStack(spacing: 8) {
            Button("Reveal Folder") { revealTarget() }
                .disabled(!report.targetExists)
                .accessibilityHint("Reveals the configured DeskTidy folder in Finder.")
            Button("Reveal Receipts") { revealReceipts() }
                .disabled(!model.hasRevealableReceipts())
                .accessibilityHint("Reveals DeskTidy receipt history in Finder.")
            Button("Copy Diagnostic") { copyDiagnostic() }
                .accessibilityHint("Copies DeskTidy's current diagnostic text to the clipboard.")
        }
        .controlSize(.small)
    }

    private var footer: some View {
        HStack {
            Button("Refresh") { model.refresh() }
                .controlSize(.small)
                .accessibilityHint("Re-reads the current DeskTidy state.")
            Spacer()
            Text(report.moverVersion)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
    }

    private var configurationDescription: String {
        switch model.configuration {
        case .missing:
            return "No native target configuration is saved. Choose a folder to finish onboarding."
        case .configured(let target):
            return "Native configuration targets \(EffectiveState.shortPath(target))."
        case .invalid(let reason):
            return "Saved target configuration is invalid: \(reason). Choose a valid folder to replace it."
        }
    }

    private var targetDescription: String {
        switch model.target {
        case .available(let path, let source):
            return "\(EffectiveState.shortPath(path)) — \(source)"
        case .unavailable(let path, let source):
            return "\(EffectiveState.shortPath(path)) — \(source) (unavailable)"
        case .invalid(let reason, let source, let attemptedPath):
            let attempted = attemptedPath.map { ": \(EffectiveState.shortPath($0))" } ?? ""
            return "\(source) invalid\(attempted) — \(reason)"
        }
    }
    private var headlineStatus: String {
        if case .notLoaded(let reason) = model.lifecycle {
            return "Not loaded — \(reason)"
        }
        return EffectiveState.statusLine(for: report)
    }

    private var lifecycleDescription: String {
        switch model.lifecycle {
        case .active:
            return "DeskTidy is active."
        case .notLoaded(let reason):
            return "DeskTidy is not loaded: \(reason)"
        case .fixture(let description):
            return description
        case .unavailable(let reason):
            return "Unavailable: \(reason)"
        }
    }

    private func color(for state: OverallState) -> Color {
        switch state {
        case .runningHealthy: return .green
        case .pausedNotLoaded: return .secondary
        case .foreignConflict, .degradedLedger: return .orange
        case .ambiguous: return .yellow
        }
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.message = "Choose the folder DeskTidy may organize"
        panel.prompt = "Use This Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let path = panel.url?.path else { return }
            Task { @MainActor in boundary.setTarget(path) }
        }
    }

    private func revealTarget() {
        guard case .available(let path, _) = model.target else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func revealReceipts() {
        NSWorkspace.shared.activateFileViewerSelecting([model.receiptsDirectory()])
    }

    private func copyDiagnostic() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(model.diagnostic(), forType: .string)
    }
}


private extension Text {
    func gridLabel() -> some View {
        font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
    }

    func gridValue() -> some View {
        font(.system(size: 10.5, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
