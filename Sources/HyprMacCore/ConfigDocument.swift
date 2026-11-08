import Foundation

/// Editable, round-trippable form of hyprmac.conf used by the settings GUI.
/// Unlike `HyprConfig`, variables are kept unexpanded (`$mod` stays `$mod`).
public struct ConfigDocument: Equatable {
    public struct Variable: Identifiable, Equatable {
        public var id = UUID()
        public var name: String      // without the leading `$`
        public var value: String
        public init(name: String, value: String) { self.name = name; self.value = value }
    }

    public struct Bind: Identifiable, Equatable {
        public var id = UUID()
        public var mods: String      // e.g. "$mod SHIFT"
        public var key: String
        public var dispatcher: String
        public var argument: String
        public init(mods: String, key: String, dispatcher: String, argument: String) {
            self.mods = mods; self.key = key; self.dispatcher = dispatcher; self.argument = argument
        }
    }

    public struct Rule: Identifiable, Equatable {
        public var id = UUID()
        public var action: String    // float | tile | workspace N | workspace special
        public var classPattern: String
        public var titlePattern: String
        public init(action: String, classPattern: String, titlePattern: String) {
            self.action = action; self.classPattern = classPattern; self.titlePattern = titlePattern
        }
    }

    public var variables: [Variable] = []
    public var gapsIn: Double = 5
    public var gapsOut: Double = 10
    public var specialScale: Double = 0.85
    public var execOnce: [String] = []
    public var rules: [Rule] = []
    public var binds: [Bind] = []
    /// Lines the GUI does not model; written back verbatim.
    public var extraLines: [String] = []

    public init() {}

    // MARK: - Variables helpers

    public func variable(_ name: String) -> String? {
        variables.first { $0.name == name }?.value
    }

    public mutating func setVariable(_ name: String, _ value: String) {
        if let i = variables.firstIndex(where: { $0.name == name }) {
            variables[i].value = value
        } else {
            variables.insert(Variable(name: name, value: value), at: 0)
        }
    }

    /// Expands `$vars` like the real parser does.
    public func expand(_ text: String) -> String {
        var result = text
        for v in variables.sorted(by: { $0.name.count > $1.name.count }) {
            result = result.replacingOccurrences(of: "$" + v.name, with: v.value)
        }
        return result
    }

    // MARK: - Parse

    public static func parse(_ text: String) -> ConfigDocument {
        var doc = ConfigDocument()
        var sections: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = HyprConfig.stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "}" { _ = sections.popLast(); continue }
            if line.hasSuffix("{") {
                sections.append(line.dropLast().trimmingCharacters(in: .whitespaces).lowercased())
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { doc.extraLines.append(line); continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("$") {
                doc.variables.append(Variable(name: String(key.dropFirst()), value: value))
                continue
            }
            let fullKey = (sections + [key.lowercased()]).joined(separator: ":")
            switch fullKey {
            case "general:gaps_in": doc.gapsIn = Double(value) ?? doc.gapsIn
            case "general:gaps_out": doc.gapsOut = Double(value) ?? doc.gapsOut
            case "special:scale": doc.specialScale = Double(value) ?? doc.specialScale
            case "exec-once": doc.execOnce.append(value)
            case "bind":
                let p = value.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if p.count >= 3 {
                    doc.binds.append(Bind(mods: p[0], key: p[1], dispatcher: p[2], argument: p.count > 3 ? p[3] : ""))
                } else {
                    doc.extraLines.append("bind = \(value)")
                }
            case "windowrule", "windowrulev2":
                let p = value.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                var rule = Rule(action: p.first ?? "float", classPattern: "", titlePattern: "")
                var ok = p.count >= 2
                for m in p.dropFirst() {
                    if m.lowercased().hasPrefix("class:") { rule.classPattern = String(m.dropFirst(6)) }
                    else if m.lowercased().hasPrefix("title:") { rule.titlePattern = String(m.dropFirst(6)) }
                    else { ok = false }
                }
                if ok { doc.rules.append(rule) } else { doc.extraLines.append("windowrule = \(value)") }
            default:
                let prefix = sections.isEmpty ? "" : sections.joined(separator: ":") + ":"
                doc.extraLines.append("\(prefix)\(key) = \(value)")
            }
        }
        return doc
    }

    // MARK: - Serialize

    public func serialize() -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "#", with: "##") }
        func num(_ d: Double) -> String {
            d == d.rounded() ? String(Int(d)) : String(format: "%g", d)
        }
        var out: [String] = [
            "# ~/.config/hyprmac/hyprmac.conf",
            "# HyprMac — Hyprland-like tiling for macOS. Syntax follows hyprland.conf.",
            "# This file was written by the HyprMac settings window (comments are not preserved).",
            "",
        ]
        if !variables.isEmpty {
            out += variables.map { "$\($0.name) = \(esc($0.value))" }
            out.append("")
        }
        out += ["general {", "    gaps_in = \(num(gapsIn))", "    gaps_out = \(num(gapsOut))", "}", ""]
        out += ["special {", "    scale = \(num(specialScale))", "}", ""]
        let execs = execOnce.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !execs.isEmpty {
            out += execs.map { "exec-once = \(esc($0))" }
            out.append("")
        }
        if !rules.isEmpty {
            for r in rules {
                var parts = [r.action]
                if !r.classPattern.isEmpty { parts.append("class:" + esc(r.classPattern)) }
                if !r.titlePattern.isEmpty { parts.append("title:" + esc(r.titlePattern)) }
                out.append("windowrule = " + parts.joined(separator: ", "))
            }
            out.append("")
        }
        for b in binds {
            var parts = [b.mods, b.key, b.dispatcher]
            if !b.argument.isEmpty { parts.append(esc(b.argument)) }
            out.append("bind = " + parts.joined(separator: ", "))
        }
        if !extraLines.isEmpty {
            out += ["", "# Lines not editable in the settings window"]
            out += extraLines.map(esc)
        }
        return out.joined(separator: "\n") + "\n"
    }
}

extension KeyCodes {
    /// Canonical key names for pickers (one name per key code).
    public static let canonicalNames: [String] = {
        let preferred = ["return", "escape", "backspace", "quote"]
        var byCode: [UInt16: String] = [:]
        for (name, code) in table where name.count > 1 || name.first!.isLetter || name.first!.isNumber {
            if let existing = byCode[code] {
                if preferred.contains(name) || (!preferred.contains(existing) && name < existing) { byCode[code] = name }
            } else {
                byCode[code] = name
            }
        }
        return byCode.values.sorted { a, b in
            func rank(_ s: String) -> Int { s.count == 1 ? (s.first!.isLetter ? 0 : 1) : (s.hasPrefix("f") && Int(s.dropFirst()) != nil ? 3 : 2) }
            return (rank(a), a.count, a) < (rank(b), b.count, b)
        }
    }()

    public static func name(for code: UInt16) -> String? {
        canonicalNames.first { table[$0] == code }
    }
}
