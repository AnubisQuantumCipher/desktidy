import Foundation

enum NativeConfigurationSchema: Int, Codable, Equatable { case v1 = 1, v2 = 2 }

struct NativeConfiguration: Codable, Equatable {
    let schema: NativeConfigurationSchema
    let target: String
    let settleSeconds: Int
    let categories: [String: String]
    let rules: [String: [String]]
    let suggestionsEnabled: Bool

    static let categoryKeys = ["inbox", "documents", "images", "screenshots", "videos", "audio", "archives", "code", "folders"]
    static let ruleKeys = ["documents", "images", "videos", "audio", "archives", "code"]

    static func defaultV2(target: String) -> NativeConfiguration {
        NativeConfiguration(schema: .v2, target: target, settleSeconds: Int(Config.settleSeconds), categories: categories, rules: rules, suggestionsEnabled: Config.enableSmartTriage)
    }

    static func legacyV1(target: String) -> NativeConfiguration {
        NativeConfiguration(schema: .v1, target: target, settleSeconds: Int(Config.settleSeconds), categories: categories, rules: rules, suggestionsEnabled: Config.enableSmartTriage)
    }

    func withTarget(_ newTarget: String) -> NativeConfiguration {
        NativeConfiguration(schema: .v2, target: newTarget, settleSeconds: settleSeconds, categories: categories, rules: rules, suggestionsEnabled: suggestionsEnabled)
    }

    private static let categories: [String: String] = [
        "inbox": Config.folderInbox, "documents": Config.folderDocuments, "images": Config.folderImages,
        "screenshots": Config.folderScreenshots, "videos": Config.folderVideos, "audio": Config.folderAudio,
        "archives": Config.folderArchives, "code": Config.folderCode, "folders": Config.folderFolders
    ]
    private static let rules: [String: [String]] = [
        "documents": Config.documentExts.sorted(), "images": Config.imageExts.sorted(), "videos": Config.videoExts.sorted(),
        "audio": Config.audioExts.sorted(), "archives": Config.archiveExts.sorted(), "code": Config.codeExts.sorted()
    ]
}

enum NativeConfigurationCodec {
    static func parse(_ data: Data) -> NativeConfigParser.ConfigurationOutcome {
        guard let text = String(data: data, encoding: .utf8) else { return .init(configuration: nil, failure: "native config is not valid UTF-8") }
        var parser = StrictNativeJSON(text)
        guard let value = parser.document() else { return .init(configuration: nil, failure: parser.failure ?? "native config is malformed") }
        guard case .object(let fields) = value else { return .init(configuration: nil, failure: "native config is not a JSON object") }
        let values = Dictionary(uniqueKeysWithValues: fields)
        guard case .integer(let rawSchema)? = values["schema"], let schema = NativeConfigurationSchema(rawValue: rawSchema) else {
            return .init(configuration: nil, failure: "native config missing or invalid schema")
        }
        switch schema {
        case .v1:
            guard exact(values, ["schema", "target"]), case .string(let target)? = values["target"], !target.isEmpty else {
                return .init(configuration: nil, failure: "schema-1 native config has an unknown, missing, or invalid field")
            }
            return .init(configuration: .legacyV1(target: target), failure: nil)
        case .v2:
            let expected = ["schema", "target", "settleSeconds", "categories", "rules", "suggestionsEnabled"]
            guard exact(values, expected), case .string(let target)? = values["target"], !target.isEmpty,
                  case .integer(let settle)? = values["settleSeconds"], (1...3600).contains(settle),
                  case .object(let rawCategories)? = values["categories"], case .object(let rawRules)? = values["rules"],
                  case .bool(let suggestions)? = values["suggestionsEnabled"], let categories = decodeCategories(rawCategories), let rules = decodeRules(rawRules) else {
                return .init(configuration: nil, failure: "schema-2 native config has an unknown, missing, or invalid field")
            }
            return .init(configuration: NativeConfiguration(schema: .v2, target: target, settleSeconds: settle, categories: categories, rules: rules, suggestionsEnabled: suggestions), failure: nil)
        }
    }

    static func encode(_ configuration: NativeConfiguration) -> Data? {
        if configuration.schema == .v1 { return try? JSONSerialization.data(withJSONObject: ["schema": 1, "target": configuration.target], options: [.sortedKeys]) }
        return try? JSONSerialization.data(withJSONObject: ["schema": 2, "target": configuration.target, "settleSeconds": configuration.settleSeconds, "categories": configuration.categories, "rules": configuration.rules, "suggestionsEnabled": configuration.suggestionsEnabled], options: [.sortedKeys])
    }

    private static func exact(_ values: [String: StrictNativeValue], _ expected: [String]) -> Bool { values.count == expected.count && Set(values.keys) == Set(expected) }
    private static func decodeCategories(_ fields: [(String, StrictNativeValue)]) -> [String: String]? {
        let values = Dictionary(uniqueKeysWithValues: fields); guard exact(values, NativeConfiguration.categoryKeys) else { return nil }
        var output: [String: String] = [:]; var names = Set<String>()
        for key in NativeConfiguration.categoryKeys {
            guard case .string(let name)? = values[key], validRelativeCategoryPath(name), names.insert(name).inserted else { return nil }
            output[key] = name
        }
        return output
    }
    private static func validRelativeCategoryPath(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128,
              name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.hasPrefix("/"), !name.hasSuffix("/"), !name.contains("//"),
              !name.contains("\\"),
              !name.unicodeScalars.contains(where: { $0.value < 0x20 }) else { return false }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        return components.allSatisfy { component in
            !component.isEmpty && component != "." && component != ".."
                && component == component.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    private static func decodeRules(_ fields: [(String, StrictNativeValue)]) -> [String: [String]]? {
        let values = Dictionary(uniqueKeysWithValues: fields); guard exact(values, NativeConfiguration.ruleKeys) else { return nil }
        var output: [String: [String]] = [:]; var unique = Set<String>()
        for key in NativeConfiguration.ruleKeys {
            guard case .array(let raw)? = values[key], !raw.isEmpty else { return nil }
            var extensions: [String] = []
            for value in raw {
                guard case .string(let ext) = value, !ext.isEmpty, ext.count <= 16, ext == ext.lowercased(), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }), unique.insert(ext).inserted else { return nil }
                extensions.append(ext)
            }
            guard extensions == extensions.sorted() else { return nil }
            output[key] = extensions
        }
        return output
    }
}

private indirect enum StrictNativeValue { case object([(String, StrictNativeValue)]), array([StrictNativeValue]), string(String), integer(Int), bool(Bool) }

private struct StrictNativeJSON {
    let text: String
    var index: String.Index
    var failure: String?
    init(_ text: String) { self.text = text; index = text.startIndex }

    mutating func document() -> StrictNativeValue? { whitespace(); guard let result = value() else { return nil }; whitespace(); return index == text.endIndex ? result : fail("native config has trailing non-whitespace") }
    private mutating func value() -> StrictNativeValue? {
        guard index < text.endIndex else { return fail("native config is malformed") }
        switch text[index] { case "{": return object(); case "[": return array(); case "\"": return string().map(StrictNativeValue.string); case "t": return literal("true", .bool(true)); case "f": return literal("false", .bool(false)); case "-", "0"..."9": return integer().map(StrictNativeValue.integer); default: return fail("native config is malformed") }
    }
    private mutating func object() -> StrictNativeValue? {
        advance(); whitespace(); var fields: [(String, StrictNativeValue)] = []; var keys = Set<String>(); if consume("}") { return .object(fields) }
        while true { guard let key = string() else { return fail("native config has a malformed key") }; guard keys.insert(key).inserted else { return fail("native config has a duplicate key") }; whitespace(); guard consume(":") else { return fail("native config is malformed") }; whitespace(); guard let parsed = value() else { return nil }; fields.append((key, parsed)); whitespace(); if consume("}") { return .object(fields) }; guard consume(",") else { return fail("native config is malformed") }; whitespace() }
    }
    private mutating func array() -> StrictNativeValue? {
        advance(); whitespace(); var values: [StrictNativeValue] = []; if consume("]") { return .array(values) }
        while true { guard let parsed = value() else { return nil }; values.append(parsed); whitespace(); if consume("]") { return .array(values) }; guard consume(",") else { return fail("native config is malformed") }; whitespace() }
    }
    private mutating func string() -> String? {
        guard consume("\"") else { return nil }; var result = ""
        while index < text.endIndex { let char = text[index]; if char == "\"" { advance(); return result }; if char == "\\" { advance(); guard index < text.endIndex else { return nil }; let escape = text[index]; advance(); switch escape { case "\"", "\\", "/": result.append(escape); case "b": result.append("\u{8}"); case "f": result.append("\u{c}"); case "n": result.append("\n"); case "r": result.append("\r"); case "t": result.append("\t"); case "u": guard let scalar = unicode() else { return nil }; result.unicodeScalars.append(scalar); default: return nil } } else { guard char.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else { return nil }; result.append(char); advance() } }
        return nil
    }
    private mutating func unicode() -> Unicode.Scalar? { guard let high = hex4() else { return nil }; if (0xD800...0xDBFF).contains(high) { guard consume("\\"), consume("u"), let low = hex4(), (0xDC00...0xDFFF).contains(low) else { return nil }; return Unicode.Scalar(0x10000 + (Int(high) - 0xD800) * 0x400 + Int(low) - 0xDC00) }; return (0xDC00...0xDFFF).contains(high) ? nil : Unicode.Scalar(high) }
    private mutating func hex4() -> UInt32? { var result: UInt32 = 0; for _ in 0..<4 { guard index < text.endIndex, let digit = text[index].hexDigitValue else { return nil }; result = result << 4 | UInt32(digit); advance() }; return result }
    private mutating func integer() -> Int? { let start = index; _ = consume("-"); guard index < text.endIndex, text[index].isASCII && text[index].isNumber else { index = start; return nil }; if text[index] == "0" { advance() } else { while index < text.endIndex, text[index].isASCII && text[index].isNumber { advance() } }; guard index == text.endIndex || (text[index] != "." && text[index] != "e" && text[index] != "E") else { index = start; return nil }; return Int(text[start..<index]) }
    private mutating func literal(_ literal: String, _ value: StrictNativeValue) -> StrictNativeValue? { guard text[index...].hasPrefix(literal) else { return fail("native config is malformed") }; text.formIndex(&index, offsetBy: literal.count); return value }
    private mutating func whitespace() { while index < text.endIndex, [" ", "\t", "\n", "\r"].contains(text[index]) { advance() } }
    private mutating func consume(_ char: Character) -> Bool { guard index < text.endIndex, text[index] == char else { return false }; advance(); return true }
    private mutating func advance() { text.formIndex(after: &index) }
    private mutating func fail<T>(_ message: String) -> T? { failure = message; return nil }
}
