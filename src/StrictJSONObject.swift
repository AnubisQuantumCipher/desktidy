import Foundation

// ============================================================================
//  Strict flat JSON object parser — same uniqueness discipline as
//  NativeConfigParser. Duplicate keys after escape decoding fail closed.
//  Values are strings or integers only (no JSONDecoder).
// ============================================================================

enum StrictJSONValue: Equatable {
    case string(String)
    case integer(Int)
}

enum StrictJSONObject {
    enum Outcome: Equatable {
        case ok([String: StrictJSONValue])
        case failed(String)
    }

    static func parse(_ data: Data) -> Outcome {
        guard let text = String(data: data, encoding: .utf8) else {
            return .failed("not valid UTF-8")
        }
        var i = text.startIndex
        skipWS(text, &i)
        guard i < text.endIndex, text[i] == "{" else { return .failed("not a JSON object") }
        text.formIndex(after: &i)
        skipWS(text, &i)
        var seen = Set<String>()
        var out: [String: StrictJSONValue] = [:]
        if i < text.endIndex, text[i] == "}" {
            text.formIndex(after: &i)
            return finish(text, i, out)
        }
        var expectPair = true
        while expectPair {
            skipWS(text, &i)
            guard let key = parseString(text, &i) else { return .failed("malformed key") }
            if seen.contains(key) { return .failed("duplicate key") }
            seen.insert(key)
            skipWS(text, &i)
            guard i < text.endIndex, text[i] == ":" else { return .failed("malformed object") }
            text.formIndex(after: &i)
            skipWS(text, &i)
            if let s = parseString(text, &i) {
                out[key] = .string(s)
            } else if let n = parseInteger(text, &i) {
                out[key] = .integer(n)
            } else {
                return .failed("unsupported value type")
            }
            skipWS(text, &i)
            if i < text.endIndex, text[i] == "," {
                text.formIndex(after: &i)
                expectPair = true
                continue
            }
            expectPair = false
        }
        skipWS(text, &i)
        guard i < text.endIndex, text[i] == "}" else { return .failed("malformed object") }
        text.formIndex(after: &i)
        return finish(text, i, out)
    }

    private static func finish(_ text: String, _ i: String.Index, _ out: [String: StrictJSONValue]) -> Outcome {
        var j = i
        skipWS(text, &j)
        if j != text.endIndex { return .failed("trailing non-whitespace") }
        return .ok(out)
    }

    private static func skipWS(_ text: String, _ i: inout String.Index) {
        while i < text.endIndex {
            switch text[i] {
            case " ", "\t", "\n", "\r": text.formIndex(after: &i)
            default: return
            }
        }
    }

    private static func parseString(_ text: String, _ i: inout String.Index) -> String? {
        guard i < text.endIndex, text[i] == "\"" else { return nil }
        text.formIndex(after: &i)
        var out = ""
        while i < text.endIndex {
            let c = text[i]
            if c == "\"" { text.formIndex(after: &i); return out }
            if c == "\\" {
                text.formIndex(after: &i)
                guard i < text.endIndex else { return nil }
                let e = text[i]
                text.formIndex(after: &i)
                switch e {
                case "\"", "\\", "/": out.append(e)
                case "b": out.append("\u{0008}")
                case "f": out.append("\u{000C}")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "u":
                    guard let scalar = parseUnicodeEscape(text, &i) else { return nil }
                    out.unicodeScalars.append(scalar)
                default: return nil
                }
                continue
            }
            if let v = c.asciiValue, v < 0x20 { return nil }
            out.append(c)
            text.formIndex(after: &i)
        }
        return nil
    }

    private static func parseUnicodeEscape(_ text: String, _ i: inout String.Index) -> Unicode.Scalar? {
        guard let unit = parseHex4(text, &i) else { return nil }
        if (0xD800...0xDBFF).contains(unit) {
            guard i < text.endIndex, text[i] == "\\" else { return nil }
            text.formIndex(after: &i)
            guard i < text.endIndex, text[i] == "u" else { return nil }
            text.formIndex(after: &i)
            guard let low = parseHex4(text, &i), (0xDC00...0xDFFF).contains(low) else { return nil }
            let combined = 0x10000 + (Int(unit) - 0xD800) * 0x400 + (Int(low) - 0xDC00)
            return Unicode.Scalar(combined)
        }
        if (0xDC00...0xDFFF).contains(unit) { return nil }
        return Unicode.Scalar(unit)
    }

    private static func parseHex4(_ text: String, _ i: inout String.Index) -> UInt32? {
        var n: UInt32 = 0
        for _ in 0..<4 {
            guard i < text.endIndex, let v = text[i].hexDigitValue else { return nil }
            n = (n << 4) + UInt32(v)
            text.formIndex(after: &i)
        }
        return n
    }

    private static func parseInteger(_ text: String, _ i: inout String.Index) -> Int? {
        guard i < text.endIndex else { return nil }
        let start = i
        if text[i] == "-" { text.formIndex(after: &i) }
        guard i < text.endIndex, text[i].isASCII && text[i].isNumber else { i = start; return nil }
        if text[i] == "0" {
            text.formIndex(after: &i)
        } else {
            while i < text.endIndex, text[i].isASCII && text[i].isNumber { text.formIndex(after: &i) }
        }
        if i < text.endIndex, text[i] == "." || text[i] == "e" || text[i] == "E" {
            i = start
            return nil
        }
        return Int(text[start..<i])
    }
}
