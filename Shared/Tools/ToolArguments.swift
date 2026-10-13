//
//  ToolArguments.swift
//  Gatita
//

import Foundation

/// The arguments of a tool block, read as text whatever JSON type the model used for each value.
/// One parser for every tool, so a number or a list in one argument can't make the others disappear.
///
/// It forgives the slips models make most: raw line breaks inside a text (common in write_file content),
/// a code fence or words around the object, trailing commas, and the OpenAI shape
/// {"name": ..., "arguments": {...}} in place of {"tool": ..., ...}.
nonisolated enum ToolArguments {
    /// Keys that name the tool when "tool" is missing.
    private static let nameKeys = ["name", "tool_name"]
    /// Keys that hold the arguments one level down, as an object or as JSON text.
    private static let nestedKeys = ["arguments", "args", "parameters", "input"]

    /// The block's JSON object as text values. Numbers and true/false become their text, a list becomes one
    /// item per line, and null and nested objects are left out. Nil when no JSON object can be read.
    static func parse(_ json: String) -> [String: String]? {
        guard let object = object(in: json) else { return nil }
        var arguments: [String: String] = [:]
        for (key, value) in flattened(object) {
            if let text = text(for: value) {
                arguments[key] = text
            }
        }
        return arguments
    }

    /// The JSON object in a block: as written when it is valid, otherwise after `repaired`.
    private static func object(in text: String) -> [String: Any]? {
        decode(text) ?? decode(repaired(text))
    }

    private static func decode(_ text: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
    }

    /// The text from the first "{" to the brace that closes it, with control characters inside strings escaped
    /// and commas just before a "}" or "]" dropped. Text that has no "{" comes back as it was.
    static func repaired(_ text: String) -> String {
        guard let start = text.firstIndex(of: "{") else { return text }
        var output = ""
        var depth = 0
        var inString = false
        var escaped = false
        for character in text[start...] {
            if inString {
                if escaped {
                    escaped = false
                    output.append(character)
                } else if character == "\\" {
                    escaped = true
                    output.append(character)
                } else if character == "\"" {
                    inString = false
                    output.append(character)
                } else if let escape = escape(character) {
                    output += escape
                } else {
                    output.append(character)
                }
                continue
            }
            switch character {
            case "\"":
                inString = true
                output.append(character)
            case "{", "[":
                depth += 1
                output.append(character)
            case "}", "]":
                dropTrailingComma(&output)
                depth -= 1
                output.append(character)
                if depth == 0 { return output }
            default:
                output.append(character)
            }
        }
        return output
    }

    /// The JSON escape for a control character, or nil for any other character.
    private static func escape(_ character: Character) -> String? {
        switch character {
        case "\n": return "\\n"
        case "\r\n": return "\\r\\n"
        case "\r": return "\\r"
        case "\t": return "\\t"
        default:
            guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
                  scalar.value < 0x20 else { return nil }
            return String(format: "\\u%04x", scalar.value)
        }
    }

    /// Removes a comma, and the spaces after it, from the end of the text.
    private static func dropTrailingComma(_ output: inout String) {
        let kept = output.reversed().drop { $0.isWhitespace }
        guard kept.first == "," else { return }
        output = String(kept.dropFirst().reversed())
    }

    /// The tool name under "tool", and every argument at the top. Arguments one level down (the OpenAI shape)
    /// are lifted up; one already at the top wins.
    private static func flattened(_ raw: [String: Any]) -> [String: Any] {
        var object = raw
        // {"function": {"name": ..., "arguments": ...}}
        if let function = object["function"] as? [String: Any] {
            object["function"] = nil
            for (key, value) in function where object[key] == nil {
                object[key] = value
            }
        }
        if object["tool"] == nil, let name = nameKeys.lazy.compactMap({ object[$0] as? String }).first {
            object["tool"] = name
        }
        for key in nestedKeys {
            guard let nested = (object[key] as? [String: Any]) ?? (object[key] as? String).flatMap(decode) else { continue }
            object[key] = nil
            for (name, value) in nested where object[name] == nil {
                object[name] = value
            }
        }
        return object
    }

    private static func text(for value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let list as [Any]:
            return list.compactMap { text(for: $0) }.joined(separator: "\n")
        default:
            return nil
        }
    }
}

/// Notices when the model makes the same tool call twice in a row, so it can be told to use the result it has.
nonisolated enum ToolRepeat {
    static let note = "note: this is the same call as your last one, and its result is below again. Use it, and do not make this call a third time."

    /// Whether two blocks make the same call, comparing their arguments rather than their spacing.
    static func isRepeat(_ block: String, of previous: String?) -> Bool {
        guard let previous, let now = ToolArguments.parse(block), let before = ToolArguments.parse(previous) else { return false }
        return now == before
    }
}
