import CryptoKit
import Foundation

// ============================================================================
//  Measured sacrificial-probe identity. Never taken from argv/env.
// ============================================================================

enum ProbeIdentity {
    static let expectedBundleID = "com.desktidy.sacrificial-probe"
    static let expectedExecutableName = "DeskTidySacrificialProbe"
    static let expectedPlistRel = "Contents/Library/LaunchAgents/com.desktidy.sacrificial.plist"

    struct Measurement: Equatable {
        var executableURL: URL
        var basename: String
        var appBundleURL: URL
        var bundleIdentifier: String
        var plistURL: URL
        var executableSHA256: String
    }

    enum Outcome: Equatable {
        case ok(Measurement)
        case refused(String)
    }

    static func sha256File(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func measureRunning(executableURL: URL, bundle: Bundle?) -> Outcome {
        let name = executableURL.lastPathComponent
        guard name == expectedExecutableName else {
            return .refused("executable basename is not the sacrificial probe")
        }
        // Walk up to *.app
        var app: URL?
        var cursor = executableURL.deletingLastPathComponent()
        for _ in 0..<6 {
            if cursor.pathExtension == "app" { app = cursor; break }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }
        guard let appURL = app else { return .refused("executable is not inside a .app bundle") }
        let info = bundle ?? Bundle(url: appURL)
        let bid = info?.bundleIdentifier ?? ""
        guard bid == expectedBundleID else {
            return .refused("bundle identifier is not the sacrificial probe")
        }
        let plist = appURL.appendingPathComponent(expectedPlistRel)
        guard FileManager.default.fileExists(atPath: plist.path) else {
            return .refused("embedded sacrificial plist missing")
        }
        guard let digest = sha256File(executableURL) else {
            return .refused("unable to hash running executable")
        }
        if digest == String(repeating: "0", count: 64) {
            return .refused("executable hash is the zero placeholder")
        }
        return .ok(Measurement(
            executableURL: executableURL, basename: name, appBundleURL: appURL,
            bundleIdentifier: bid, plistURL: plist, executableSHA256: digest
        ))
    }
}
