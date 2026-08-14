import Foundation

// ============================================================================
//  Read-only production evidence. The sacrificial probe constructs this
//  provider explicitly in source. It never reads DESKTIDY_* fixture env.
//  Tests inject FakeAuthoritySnapshot.
// ============================================================================

struct FakeAuthoritySnapshot: AuthoritySnapshotProviding {
    var result: AuthoritySnapResult
    func snapshot(rootPath: String) -> AuthoritySnapResult {
        _ = rootPath
        return result
    }
}

enum ProductionAuthoritySnapshot: AuthoritySnapshotProviding {
    case live

    func snapshot(rootPath: String) -> AuthoritySnapResult {
        // Live home LaunchAgents only — never DESKTIDY_* fixture env.
        let root = AuthorityGuard.canonicalize(rootPath)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
        if !exists { return .failed("sacrificial root does not exist") }
        if !isDir.boolValue { return .failed("sacrificial root is not a directory") }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let guard_ = AuthorityGuard(agentsDir: agents, fixtureStates: nil)
        switch guard_.evaluate(rootPath: root.path) {
        case .ambiguous:
            return .ok(AuthoritySnapshot(
                foreignOverlap: false, uninspectable: true, dualDeskTidy: false,
                rootCanonical: root.path))
        case .conflict(let movers):
            let personal = movers.contains { MutationInterlock.personalLabels.contains($0.label) }
            let foreign = movers.contains { !$0.isSelf }
            return .ok(AuthoritySnapshot(
                foreignOverlap: foreign || personal, uninspectable: false, dualDeskTidy: false,
                rootCanonical: root.path))
        case .sole, .soleWithStale:
            let (records, unread) = guard_.relevantMovers(for: root)
            if !unread.isEmpty {
                return .ok(AuthoritySnapshot(
                    foreignOverlap: false, uninspectable: true, dualDeskTidy: false,
                    rootCanonical: root.path))
            }
            let selfCount = records.filter(\.isSelf).count
            let appObserved = records.contains { $0.label.contains("sacrificial") || $0.label.contains("com.desktidy.app") }
            let cli = records.contains { ProductIdentity.selfLabels.contains($0.label) }
            return .ok(AuthoritySnapshot(
                foreignOverlap: false, uninspectable: false,
                dualDeskTidy: cli && appObserved && selfCount >= 1,
                rootCanonical: root.path))
        }
    }
}

enum ProtectedInventory {
    struct Loaded: Equatable {
        var desktop: CanonicalPath
        var protected: [CanonicalPath]
        var production: CanonicalPath?
    }
    enum Outcome: Equatable {
        case ok(Loaded)
        case failed(String)
    }
}

enum ProtectedRootInventory {
    static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> ProtectedInventory.Outcome {
        let desktop = AuthorityGuard.canonicalize(home.appendingPathComponent("Desktop").path)
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        var protected: [CanonicalPath] = [desktop]
        for label in MutationInterlock.personalLabels {
            let plist = agents.appendingPathComponent("\(label).plist")
            // Missing plist: that mover is not installed. Existing-but-unreadable refuses.
            guard FileManager.default.fileExists(atPath: plist.path) else { continue }
            guard let data = FileManager.default.contents(atPath: plist.path) else {
                return .failed("unable to inspect protected label \(label)")
            }
            guard let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                return .failed("unable to decode protected label \(label)")
            }
            var watched: [String] = []
            for key in ["WatchPaths", "QueueDirectories"] {
                if let arr = obj[key] as? [String] { watched.append(contentsOf: arr) }
            }
            for w in watched { protected.append(AuthorityGuard.canonicalize(w)) }
        }
        let prodPlist = agents.appendingPathComponent("\(ProductIdentity.sortLabel).plist")
        var production: CanonicalPath?
        if let data = FileManager.default.contents(atPath: prodPlist.path),
           let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let env = obj["EnvironmentVariables"] as? [String: String],
           let t = env["DESKTIDY_TARGET_DIR"], !t.isEmpty {
            production = AuthorityGuard.canonicalize(t)
        }
        return .ok(ProtectedInventory.Loaded(desktop: desktop, protected: protected, production: production))
    }
}
