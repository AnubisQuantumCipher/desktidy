import AppIntents
import Foundation

// App Intents are deliberately a thin, bounded presentation layer. They never
// construct a core or accept paths, shell text, or destinations. The one
// filename lookup is validated by the canonical bridge as a bounded basename.
// Every operation crosses the app-installed canonical bridge.

enum DeskTidyPauseDuration: String, AppEnum {
    case fiveMinutes
    case oneHour
    case oneDay
    case indefinitely

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pause Duration")

    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fiveMinutes: "Five Minutes",
        .oneHour: "One Hour",
        .oneDay: "One Day",
        .indefinitely: "Until Resumed"
    ]

    var canonicalDuration: CanonicalIntentPauseDuration {
        switch self {
        case .fiveMinutes: .fiveMinutes
        case .oneHour: .oneHour
        case .oneDay: .oneDay
        case .indefinitely: .indefinitely
        }
    }
}

struct TidyDesktopIntent: AppIntent {
    static let title: LocalizedStringResource = "Tidy Desktop"
    static let description = IntentDescription("Sorts eligible Desktop files using DeskTidy’s configured rules.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = DeskTidyIntentBridge.shared.tidyNow()
        switch result.evidence {
        case .completed:
            return .result(dialog: "DeskTidy sorted \(result.movedCount) files.")
        case .refused:
            return .result(dialog: "DeskTidy could not sort files because the action was refused.")
        case .unavailable:
            return .result(dialog: "DeskTidy is unavailable.")
        default:
            return .result(dialog: "DeskTidy could not complete sorting.")
        }
    }
}

struct PauseTidyingIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Tidying"
    static let description = IntentDescription("Pauses DeskTidy for a fixed duration or until it is resumed.")

    @Parameter(title: "Duration", default: .oneHour)
    var duration: DeskTidyPauseDuration

    static var parameterSummary: some ParameterSummary {
        Summary("Pause tidying for \(\.$duration)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch DeskTidyIntentBridge.shared.pause(duration.canonicalDuration).evidence {
        case .completed:
            return .result(dialog: "DeskTidy is paused.")
        case .refused:
            return .result(dialog: "DeskTidy could not pause because the action was refused.")
        case .unavailable:
            return .result(dialog: "DeskTidy is unavailable.")
        default:
            return .result(dialog: "DeskTidy could not pause.")
        }
    }
}

struct ResumeTidyingIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Tidying"
    static let description = IntentDescription("Resumes DeskTidy after a pause.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch DeskTidyIntentBridge.shared.resume().evidence {
        case .completed:
            return .result(dialog: "DeskTidy resumed.")
        case .refused:
            return .result(dialog: "DeskTidy could not resume because the action was refused.")
        case .unavailable:
            return .result(dialog: "DeskTidy is unavailable.")
        default:
            return .result(dialog: "DeskTidy could not resume.")
        }
    }
}

struct SortingStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Sorting Status"
    static let description = IntentDescription("Reports whether DeskTidy is available and paused.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = DeskTidyIntentBridge.shared.status()
        guard result.evidence == .available else {
            return .result(dialog: "DeskTidy is unavailable.")
        }
        switch result.pause {
        case .running:
            return .result(dialog: "DeskTidy is running.")
        case .pausedIndefinitely, .pausedUntil:
            return .result(dialog: "DeskTidy is paused.")
        case .unreadable:
            return .result(dialog: "DeskTidy’s pause state is unavailable.")
        }
    }
}

struct RecentMovesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recent Moves"
    static let description = IntentDescription("Reports the number of recent DeskTidy moves without exposing file paths.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = DeskTidyIntentBridge.shared.recentMoves()
        switch result.evidence {
        case .available:
            return .result(dialog: "DeskTidy has \(result.entries.count) recent moves.")
        case .ledgerUnavailable:
            return .result(dialog: "DeskTidy’s recent move history is unavailable.")
        case .unavailable:
            return .result(dialog: "DeskTidy is unavailable.")
        default:
            return .result(dialog: "DeskTidy could not read recent moves.")
        }
    }
}

struct WhereDidItGoIntent: AppIntent {
    static let title: LocalizedStringResource = "Where Did It Go?"
    static let description = IntentDescription("Looks up a moved file by its filename without searching outside DeskTidy receipts.")

    @Parameter(title: "File Name")
    var fileName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$fileName) in DeskTidy")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = DeskTidyIntentBridge.shared.whereDidItGo(named: fileName)
        switch result.evidence {
        case .moved:
            return .result(dialog: "DeskTidy found evidence that the file was moved.")
        case .movedElsewhere:
            return .result(dialog: "DeskTidy found the receipt, but another process appears to have moved or changed the file.")
        case .changed:
            return .result(dialog: "DeskTidy found the receipt, but the file changed after it was moved.")
        case .noEvidence:
            return .result(dialog: "DeskTidy found no receipt evidence for that file.")
        case .invalidQuery:
            return .result(dialog: "DeskTidy needs a simple file name, not a path.")
        case .ledgerUnavailable:
            return .result(dialog: "DeskTidy’s receipt ledger is unavailable.")
        case .unavailable:
            return .result(dialog: "DeskTidy is unavailable.")
        default:
            return .result(dialog: "DeskTidy could not look up that file.")
        }
    }
}

struct DeskTidyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TidyDesktopIntent(),
            phrases: ["Tidy my desktop in \(.applicationName)"],
            shortTitle: "Tidy Desktop",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: PauseTidyingIntent(),
            phrases: ["Pause tidying with \(.applicationName)"],
            shortTitle: "Pause Tidying",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeTidyingIntent(),
            phrases: ["Resume tidying with \(.applicationName)"],
            shortTitle: "Resume Tidying",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: SortingStatusIntent(),
            phrases: ["Get sorting status from \(.applicationName)"],
            shortTitle: "Sorting Status",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: RecentMovesIntent(),
            phrases: ["Get recent moves from \(.applicationName)"],
            shortTitle: "Recent Moves",
            systemImageName: "clock.arrow.circlepath"
        )
        AppShortcut(
            intent: WhereDidItGoIntent(),
            phrases: ["Find a moved file in \(.applicationName)"],
            shortTitle: "Where Did It Go?",
            systemImageName: "magnifyingglass"
        )
    }
}
