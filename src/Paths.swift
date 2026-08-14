import Foundation

// ============================================================================
//  Canonical application-support and receipt paths.
//
//  One helper derives the app-support root, receipt directory, ledger file,
//  native config file, and agents directory. Engine, EffectiveState, and the
//  menu-bar app must call this — they must not re-derive the same paths.
//
//  DESKTIDY_APP_DIR and DESKTIDY_AGENTS_DIR remain fixture-injectable.
//  This type never creates, moves, or deletes files.
// ============================================================================

enum DeskTidyPaths {
    static func appDirectory(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let a = env["DESKTIDY_APP_DIR"], !a.isEmpty {
            return URL(fileURLWithPath: (a as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("Library/Application Support/DeskTidy", isDirectory: true)
    }

    static func receiptsDirectory(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        appDirectory(env: env, home: home).appendingPathComponent("receipts", isDirectory: true)
    }

    static func ledgerURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        receiptsDirectory(env: env, home: home).appendingPathComponent("ledger.jsonl")
    }

    static func nativeConfigURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        appDirectory(env: env, home: home).appendingPathComponent("config.json")
    }

    static func agentsDirectory(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let d = env["DESKTIDY_AGENTS_DIR"], !d.isEmpty {
            return URL(fileURLWithPath: (d as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    static func sortPlistURL(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        agentsDirectory(env: env, home: home).appendingPathComponent("com.desktidy.sort.plist")
    }
}
