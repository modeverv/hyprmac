import CoreGraphics
import Foundation

/// The special workspace (Hyprland "special" / Omarchy scratchpad).
public let specialWorkspaceID = -1

public struct Modifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = Modifiers(rawValue: 1)
    public static let option = Modifiers(rawValue: 2)
    public static let control = Modifiers(rawValue: 4)
    public static let shift = Modifiers(rawValue: 8)

    /// Parses "SUPER SHIFT", "ALT_SHIFT", "CMD+CTRL" ...
    public static func parse(_ text: String) -> (Modifiers, [String]) {
        var mods: Modifiers = []
        var unknown: [String] = []
        let tokens = text.split(whereSeparator: { " _+".contains($0) }).map { $0.uppercased() }
        for t in tokens {
            switch t {
            case "SUPER", "CMD", "COMMAND", "META", "WIN", "MOD4": mods.insert(.command)
            case "ALT", "OPT", "OPTION", "MOD1": mods.insert(.option)
            case "CTRL", "CONTROL": mods.insert(.control)
            case "SHIFT": mods.insert(.shift)
            default: unknown.append(t)
            }
        }
        return (mods, unknown)
    }
}

public struct KeyBind: Equatable, Sendable {
    public var modifiers: Modifiers
    public var key: String
    public var keyCode: UInt16
    public var dispatcher: String
    public var argument: String
}

public enum WorkspaceTarget: Equatable, Sendable {
    case number(Int)
    case special
    case relative(Int)   // e+1 / e-1 : next / previous occupied workspace
    case previous        // back and forth

    public init?(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "special" || t.hasPrefix("special:") { self = .special; return }
        if t == "previous" { self = .previous; return }
        if t.hasPrefix("e"), let n = Int(t.dropFirst()) { self = .relative(n); return }
        if let n = Int(t), (1...99).contains(n) { self = .number(n); return }
        return nil
    }
}

public struct WindowRule: Sendable {
    public enum Action: Equatable, Sendable {
        case float
        case tile
        case workspace(Int)
    }

    public var action: Action
    public var classPattern: String?
    public var titlePattern: String?

    /// `class:` matches the app name or the bundle identifier. Case-insensitive.
    public func matches(appName: String, bundleID: String?, title: String) -> Bool {
        if classPattern == nil && titlePattern == nil { return false }
        if let p = classPattern {
            let candidates = [appName, bundleID ?? ""]
            guard candidates.contains(where: { Self.match(p, $0) }) else { return false }
        }
        if let p = titlePattern, !Self.match(p, title) { return false }
        return true
    }

    private static func match(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

public struct HyprConfig: Sendable {
    public var gapsIn: CGFloat = 5
    public var gapsOut: CGFloat = 10
    /// Size of the special workspace relative to the monitor.
    public var specialScale: CGFloat = 0.8
    public var binds: [KeyBind] = []
    public var rules: [WindowRule] = []
    public var execOnce: [String] = []
    public var errors: [String] = []

    public init() {}

    public static let dispatchers: Set<String> = [
        "exec", "killactive", "workspace", "movetoworkspace", "movetoworkspacesilent",
        "togglespecialworkspace", "movefocus", "swapwindow", "movewindow", "togglefloating",
        "fullscreen", "togglesplit", "splitratio", "focusmonitor", "reload", "exit",
    ]

    // MARK: - Parser (Hyprland-like syntax)

    public static func parse(_ text: String) -> HyprConfig {
        var config = HyprConfig()
        var variables: [String: String] = [:]
        var sections: [String] = []

        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let lineNo = index + 1
            let line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "}" {
                if sections.popLast() == nil { config.errors.append("line \(lineNo): unmatched }") }
                continue
            }
            if line.hasSuffix("{") {
                sections.append(line.dropLast().trimmingCharacters(in: .whitespaces).lowercased())
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                config.errors.append("line \(lineNo): expected key = value")
                continue
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = substitute(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces), variables)

            if key.hasPrefix("$") {
                variables[key] = value
                continue
            }
            let fullKey = (sections + [key.lowercased()]).joined(separator: ":")
            switch fullKey {
            case "general:gaps_in":
                if let v = Double(value) { config.gapsIn = CGFloat(v) } else { config.errors.append("line \(lineNo): gaps_in must be a number") }
            case "general:gaps_out":
                if let v = Double(value) { config.gapsOut = CGFloat(v) } else { config.errors.append("line \(lineNo): gaps_out must be a number") }
            case "special:scale":
                if let v = Double(value), v > 0.2, v <= 1 { config.specialScale = CGFloat(v) } else { config.errors.append("line \(lineNo): special scale must be in 0.2...1") }
            case "bind":
                switch parseBind(value) {
                case .success(let b): config.binds.append(b)
                case .failure(let e): config.errors.append("line \(lineNo): \(e.message)")
                }
            case "windowrule", "windowrulev2":
                switch parseRule(value) {
                case .success(let r): config.rules.append(r)
                case .failure(let e): config.errors.append("line \(lineNo): \(e.message)")
                }
            case "exec-once":
                if !value.isEmpty { config.execOnce.append(value) }
            default:
                config.errors.append("line \(lineNo): unknown option '\(fullKey)'")
            }
        }
        if !sections.isEmpty { config.errors.append("unclosed section '\(sections.joined(separator: ":"))'") }
        return config
    }

    public struct ParseError: Error { public let message: String }

    static func parseBind(_ value: String) -> Result<KeyBind, ParseError> {
        let parts = value.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return .failure(ParseError(message: "bind needs MODS, KEY, DISPATCHER[, ARG]")) }
        let (mods, unknown) = Modifiers.parse(parts[0])
        guard unknown.isEmpty else { return .failure(ParseError(message: "unknown modifier \(unknown.joined(separator: " "))")) }
        guard let code = KeyCodes.code(for: parts[1]) else { return .failure(ParseError(message: "unknown key '\(parts[1])'")) }
        let dispatcher = parts[2].lowercased()
        guard dispatchers.contains(dispatcher) else { return .failure(ParseError(message: "unknown dispatcher '\(parts[2])'")) }
        let arg = parts.count > 3 ? parts[3] : ""
        return .success(KeyBind(modifiers: mods, key: parts[1], keyCode: code, dispatcher: dispatcher, argument: arg))
    }

    static func parseRule(_ value: String) -> Result<WindowRule, ParseError> {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return .failure(ParseError(message: "windowrule needs RULE, class:REGEX")) }
        let actionText = parts[0].lowercased()
        let action: WindowRule.Action
        if actionText == "float" {
            action = .float
        } else if actionText == "tile" {
            action = .tile
        } else if actionText.hasPrefix("workspace") {
            let arg = actionText.dropFirst("workspace".count).trimmingCharacters(in: .whitespaces)
            switch WorkspaceTarget(arg) {
            case .number(let n): action = .workspace(n)
            case .special: action = .workspace(specialWorkspaceID)
            default: return .failure(ParseError(message: "bad workspace in rule '\(parts[0])'"))
            }
        } else {
            return .failure(ParseError(message: "unknown rule '\(parts[0])' (float, tile, workspace N|special)"))
        }
        var rule = WindowRule(action: action)
        for matcher in parts.dropFirst() {
            if matcher.lowercased().hasPrefix("class:") {
                rule.classPattern = String(matcher.dropFirst(6))
            } else if matcher.lowercased().hasPrefix("title:") {
                rule.titlePattern = String(matcher.dropFirst(6))
            } else {
                return .failure(ParseError(message: "unknown matcher '\(matcher)' (class:, title:)"))
            }
        }
        for p in [rule.classPattern, rule.titlePattern].compactMap({ $0 }) {
            if (try? NSRegularExpression(pattern: p)) == nil {
                return .failure(ParseError(message: "invalid regex '\(p)'"))
            }
        }
        return .success(rule)
    }

    /// `#` starts a comment, `##` is a literal `#` (Hyprland semantics).
    static func stripComment(_ line: String) -> String {
        var out = ""
        let it = Array(line)
        var i = 0
        while i < it.count {
            if it[i] == "#" {
                if i + 1 < it.count, it[i + 1] == "#" { out.append("#"); i += 2; continue }
                break
            }
            out.append(it[i])
            i += 1
        }
        return out
    }

    static func substitute(_ text: String, _ variables: [String: String]) -> String {
        var result = text
        for name in variables.keys.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: name, with: variables[name]!)
        }
        return result
    }
}
