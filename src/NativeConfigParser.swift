import Foundation

// ============================================================================
//  Strict native-config parser (schema 1).
//
//  Operates on raw UTF-8 bytes *before* any dictionary conversion.
//  JSONSerialization / JSONDecoder collapse duplicate keys and cannot
//  enforce uniqueness.
//
//  Schema-1 exact key set: `schema` and `target` only.
//  Duplicate keys are rejected after JSON string-escape decoding, so
//  "target" and "targ\u0065t" are the same key.
// ============================================================================

enum NativeConfigParser {
    enum Outcome: Equatable {
        case ok(target: String)
        case failed(String)
    }

    static func parse(_ data: Data) -> Outcome {
        guard let text = String(data: data, encoding: .utf8) else {
            return .failed("native config is not valid UTF-8")
        }
        var i = text.startIndex
        skipWS(text, &i)
        guard i < text.endIndex, text[i] == "{" else {
            return .failed("native config is not a JSON object")
        }
        text.formIndex(after: &i)
        skipWS(text, &i)

        var seen = Set<String>()
        var schema: Int?
        var target: String?

        if i < text.endIndex, text[i] == "}" {
            text.formIndex(after: &i)
            return finish(text, i, schema: schema, target: target)
        }

        var expectPair = true
        while expectPair {
            skipWS(text, &i)
            guard let key = parseString(text, &i) else {
                return .failed("native config has a malformed key")
            }
            if seen.contains(key) {
                return .failed("native config has a duplicate key")
            }
            seen.insert(key)
            skipWS(text, &i)
            guard i < text.endIndex, text[i] == ":" else {
                return .failed("native config is malformed")
            }
            text.formIndex(after: &i)
            skipWS(text, &i)

            switch key {
            case "schema":
                guard let n = parseInteger(text, &i) else {
                    return .failed("native config schema has the wrong field type")
                }
                schema = n
            case "target":
                guard let s = parseString(text, &i) else {
                    return .failed("native config target has the wrong field type")
                }
                target = s
            default:
                return .failed("native config has an unknown field")
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
        guard i < text.endIndex, text[i] == "}" else {
            return .failed("native config is malformed")
        }
        text.formIndex(after: &i)
        return finish(text, i, schema: schema, target: target)
    }

    private static func finish(_ text: String, _ i: String.Index, schema: Int?, target: String?) -> Outcome {
        var j = i
        skipWS(text, &j)
        if j != text.endIndex {
            return .failed("native config has trailing non-whitespace")
        }
        guard let schema else { return .failed("native config missing schema") }
        guard schema == 1 else { return .failed("native config unknown schema") }
        guard let target else { return .failed("native config missing target") }
        if target.isEmpty { return .failed("native config target is empty") }
        return .ok(target: target)
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
            if c == "\"" {
                text.formIndex(after: &i)
                return out
            }
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
                default:
                    return nil
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

    /// JSON integer token only (no fraction/exponent). Schema must be an integer.
    private static func parseInteger(_ text: String, _ i: inout String.Index) -> Int? {
        guard i < text.endIndex else { return nil }
        let start = i
        if text[i] == "-" { text.formIndex(after: &i) }
        guard i < text.endIndex, text[i].isASCII && text[i].isNumber else {
            i = start
            return nil
        }
        if text[i] == "0" {
            text.formIndex(after: &i)
        } else {
            while i < text.endIndex, text[i].isASCII && text[i].isNumber {
                text.formIndex(after: &i)
            }
        }
        if i < text.endIndex, text[i] == "." || text[i] == "e" || text[i] == "E" {
            i = start
            return nil
        }
        return Int(text[start..<i])
    }
}
