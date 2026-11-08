import Foundation
import HyprMacCore

/// Loads ~/.config/hyprmac/hyprmac.conf (created with defaults on first run)
/// and detects edits by polling the modification date.
final class ConfigStore {
    let url: URL
    private var lastModified: Date?

    init(path: String? = nil) {
        if let path {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
            url = base.appendingPathComponent("hyprmac/hyprmac.conf")
        }
    }

    func load() -> HyprConfig {
        ensureExists()
        lastModified = modificationDate()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            var c = HyprConfig.parse(HyprConfig.defaultText)
            c.errors.append("could not read \(url.path); using defaults")
            return c
        }
        return HyprConfig.parse(text)
    }

    func readText() -> String? {
        ensureExists()
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// True when the file changed since the last load.
    func hasChanged() -> Bool {
        let m = modificationDate()
        return m != nil && m != lastModified
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func ensureExists() {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? HyprConfig.defaultText.write(to: url, atomically: true, encoding: .utf8)
    }
}
