import Foundation

// ============================================================================
//  One target-resolution model for the movement engine and EffectiveState.
//
//  Precedence (first selected source wins; invalid selected source does not
//  fall through):
//    1. native config  ~/Library/Application Support/DeskTidy/config.json
//       (or $DESKTIDY_APP_DIR/config.json) — schema 1, field `target`
//    2. installed com.desktidy.sort plist EnvironmentVariables.DESKTIDY_TARGET_DIR
//    3. process DESKTIDY_TARGET_DIR
//    4. ~/Desktop
//
//  Phase 0 implements the reader only. Nothing here writes a native config.
// ============================================================================

enum TargetSource: String, Codable {
    case nativeConfig
    case installedPlist
    case environment
    case defaultDesktop
}

enum TargetResolution: Equatable {
    case resolved(path: String, source: TargetSource, exists: Bool)
    case invalid(reason: String, source: TargetSource, attemptedPath: String?)
}

enum TargetResolver {
    static let nativeSchema = 1

    static func resolve(
        env: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fm: FileManager = .default
    ) -> TargetResolution {
        let configURL = DeskTidyPaths.nativeConfigURL(env: env, home: home)
        if fm.fileExists(atPath: configURL.path) {
            return finish(readNativeConfig(configURL, fm: fm), source: .nativeConfig, fm: fm)
        }

        let plistURL = DeskTidyPaths.sortPlistURL(env: env, home: home)
        if fm.fileExists(atPath: plistURL.path) {
            switch readPlistTarget(plistURL, fm: fm) {
            case .value(let path):
                return finish(.ok(path), source: .installedPlist, fm: fm)
            case .noTargetKey:
                break
            case .failed(let reason):
                return .invalid(reason: reason, source: .installedPlist, attemptedPath: nil)
            }
        }

        if let raw = env["DESKTIDY_TARGET_DIR"] {
            if raw.isEmpty {
                return .invalid(reason: "empty DESKTIDY_TARGET_DIR", source: .environment, attemptedPath: nil)
            }
            return finish(.ok(raw), source: .environment, fm: fm)
        }

        let fallback = home.appendingPathComponent(Config.targetDirName).path
        return finish(.ok(fallback), source: .defaultDesktop, fm: fm)
    }

    static func standardize(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    // -- internals -----------------------------------------------------------
    private enum Parsed {
        case ok(String)
        case failed(String, String?)
    }

    private enum PlistRead {
        case value(String)
        case noTargetKey
        case failed(String)
    }

    private static func finish(_ parsed: Parsed, source: TargetSource, fm: FileManager) -> TargetResolution {
        switch parsed {
        case .ok(let raw):
            let path = standardize(raw)
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            return .resolved(path: path, source: source, exists: exists)
        case .failed(let reason, let attempted):
            return .invalid(reason: reason, source: source, attemptedPath: attempted)
        }
    }

    private static func readNativeConfig(_ url: URL, fm: FileManager) -> Parsed {
        guard let data = fm.contents(atPath: url.path) else {
            return .failed("native config exists but is unreadable", nil)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else {
            return .failed("native config is malformed or not a JSON object", nil)
        }
        if dict["schema"] == nil {
            return .failed("native config missing schema", nil)
        }
        let schema: Int?
        if let i = dict["schema"] as? Int { schema = i }
        else if let n = dict["schema"] as? NSNumber { schema = n.intValue }
        else { return .failed("native config schema has the wrong field type", nil) }
        guard schema == nativeSchema else {
            return .failed("native config unknown schema", nil)
        }
        if let alt = dict["watchedTarget"] {
            if let altStr = alt as? String, let t = dict["target"] as? String, altStr != t {
                return .failed("native config has duplicate/ambiguous target fields", nil)
            }
            if !(alt is String) {
                return .failed("native config has duplicate/ambiguous target fields", nil)
            }
        }
        guard let target = dict["target"] else {
            return .failed("native config missing target", nil)
        }
        guard let path = target as? String else {
            return .failed("native config target has the wrong field type", nil)
        }
        if path.isEmpty {
            return .failed("native config target is empty", path)
        }
        return .ok(path)
    }

    private static func readPlistTarget(_ url: URL, fm: FileManager) -> PlistRead {
        guard let data = fm.contents(atPath: url.path) else {
            return .failed("installed sort plist exists but is unreadable")
        }
        guard let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else {
            return .failed("installed sort plist is malformed")
        }
        guard let envDict = dict["EnvironmentVariables"] as? [String: String] else {
            return .noTargetKey
        }
        guard let t = envDict["DESKTIDY_TARGET_DIR"] else { return .noTargetKey }
        if t.isEmpty { return .failed("installed sort plist DESKTIDY_TARGET_DIR is empty") }
        return .value(t)
    }
}
