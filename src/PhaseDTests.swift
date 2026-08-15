import Foundation

// ============================================================================
// Phase D native configuration contracts. These tests are hermetic and never
// point a store at a user directory.
// ============================================================================

final class PhaseDTests {
    private let fm = FileManager.default
    private var pass = 0
    private var fail = 0

    private func check(_ id: String, _ description: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            print("PASS  \(id)  \(description)")
            pass += 1
        } else {
            print("FAIL  \(id)  \(description)\(detail.isEmpty ? "" : " — \(detail)")")
            fail += 1
        }
    }

    private func temporaryDirectory(_ label: String) -> URL {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("desktidy-phased-\(label)-\(UUID().uuidString)", isDirectory: true)
        try! fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func runAll() -> Bool {
        runSchemaOneReadCompatibility()
        runStrictSchemaTwoValidation()
        runStoreWriteAndMigrationContract()
        runSymlinkAndProtectedRootContract()
        print("PHASE D GATES: \(pass) passed, \(fail) failed")
        return pass > 0 && fail == 0
    }

    private func runSchemaOneReadCompatibility() {
        let parsed = NativeConfigParser.parseConfiguration(Data("{\"schema\":1,\"target\":\"/tmp/target\"}".utf8))
        check(
            "D01",
            "schema-1 target-only configuration remains read-compatible",
            parsed.configuration?.schema == .v1 && parsed.configuration?.target == "/tmp/target"
        )
    }

    private func runStrictSchemaTwoValidation() {
        let good = NativeConfiguration.defaultV2(target: "/tmp/target")
        let encoded = NativeConfigurationCodec.encode(good)!
        let duplicate = Data("{\"schema\":2,\"target\":\"/tmp/target\",\"settleSeconds\":15,\"categories\":{},\"rules\":{},\"suggestionsEnabled\":true,\"target\":\"/tmp/other\"}".utf8)
        let trailing = encoded + Data(" x".utf8)
        let unknown = Data("{\"schema\":2,\"target\":\"/tmp/target\",\"settleSeconds\":15,\"categories\":{},\"rules\":{},\"suggestionsEnabled\":true,\"extra\":1}".utf8)
        var traversalObject = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        var traversalCategories = traversalObject["categories"] as! [String: String]
        traversalCategories["documents"] = "Docs/../Escape"
        traversalObject["categories"] = traversalCategories
        let traversal = try! JSONSerialization.data(withJSONObject: traversalObject)
        check(
            "D02",
            "schema-2 accepts safe nested categories and rejects duplicate, trailing, unknown, and traversal data",
            NativeConfigParser.parseConfiguration(encoded).configuration == good
                && NativeConfigParser.parseConfiguration(duplicate).configuration == nil
                && NativeConfigParser.parseConfiguration(trailing).configuration == nil
                && NativeConfigParser.parseConfiguration(unknown).configuration == nil
                && NativeConfigParser.parseConfiguration(traversal).configuration == nil
        )
    }

    private func runStoreWriteAndMigrationContract() {
        let sandbox = temporaryDirectory("store")
        defer { try? fm.removeItem(at: sandbox) }
        let target = sandbox.appendingPathComponent("target", isDirectory: true)
        let app = sandbox.appendingPathComponent("app", isDirectory: true)
        try! fm.createDirectory(at: target, withIntermediateDirectories: true)
        try! fm.createDirectory(at: app, withIntermediateDirectories: true)
        let configURL = app.appendingPathComponent("config.json")
        try! Data("{\"schema\":1,\"target\":\"\(target.path)\"}".utf8).write(to: configURL)
        let store = NativeConfigurationStore(url: configURL, fm: fm)

        let migrated = store.load(migratingSchema1: true)
        let receipts = store.receipts()
        let permissions = (try? fm.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber)?.intValue
        let rollback = receipts.first(where: { $0.operation == .migration }).flatMap { store.rollbackMigration(receiptID: $0.id) }
        check(
            "D03",
            "an injected store migrates schema-1 through a durable receipt, writes private schema-2 data, and can receipt-backed rollback",
            migrated.configuration?.schema == .v2
                && receipts.contains { $0.operation == .migration }
                && permissions.map { $0 & 0o077 == 0 } == true
                && rollback?.configuration?.schema == .v1
                && store.receipts().contains { $0.operation == .rollback },
            "config=\(configURL.path), migrated=\(String(describing: migrated.configuration?.schema)), failure=\(String(describing: migrated.failure)), receipts=\(receipts.map(\.operation)), permissions=\(String(describing: permissions)), rollback=\(String(describing: rollback?.configuration?.schema))"
        )
    }

    private func runSymlinkAndProtectedRootContract() {
        let sandbox = temporaryDirectory("roots")
        defer { try? fm.removeItem(at: sandbox) }
        let actual = sandbox.appendingPathComponent("actual", isDirectory: true)
        let linked = sandbox.appendingPathComponent("linked", isDirectory: true)
        let target = sandbox.appendingPathComponent("target", isDirectory: true)
        try! fm.createDirectory(at: actual, withIntermediateDirectories: true)
        try! fm.createDirectory(at: target, withIntermediateDirectories: true)
        try! fm.createSymbolicLink(atPath: linked.path, withDestinationPath: actual.path)
        let symlinkedStore = NativeConfigurationStore(url: linked.appendingPathComponent("config.json"), fm: fm)
        let rootStore = NativeConfigurationStore(url: URL(fileURLWithPath: "/config.json"), fm: fm)
        let configuration = NativeConfiguration.defaultV2(target: target.path)
        check(
            "D04",
            "configuration writes reject symlinked and protected storage roots before persisting data",
            symlinkedStore.save(configuration).configuration == nil
                && rootStore.save(configuration).configuration == nil
        )
    }
}
