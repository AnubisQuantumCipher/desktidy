import Foundation

// Sacrificial helper: no file movement, no network. Writes one heartbeat
// under an explicitly supplied sacrificial app-support root, then exits.
@main
struct SacrificialHelper {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        guard let app = env["DESKTIDY_PROBE_APP_DIR"], !app.isEmpty,
              let target = env["DESKTIDY_PROBE_TARGET"], !target.isEmpty else {
            fputs("sacrificial helper: refusing — DESKTIDY_PROBE_APP_DIR and DESKTIDY_PROBE_TARGET are required\n", stderr)
            exit(2)
        }
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").path
        if target == desktop || target.hasPrefix(desktop + "/") {
            fputs("sacrificial helper: refusing — target must not be the live Desktop\n", stderr)
            exit(2)
        }
        let dir = URL(fileURLWithPath: (app as NSString).expandingTildeInPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let beat = dir.appendingPathComponent("heartbeat.json")
            let body = "{\"schema\":1,\"ok\":true,\"targetPresent\":true}\n"
            try Data(body.utf8).write(to: beat)
        } catch {
            fputs("sacrificial helper: heartbeat write failed\n", stderr)
            exit(1)
        }
        exit(0)
    }
}
