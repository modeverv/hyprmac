import AppKit
import HyprMacCore

/// State behind the settings window: an editable `ConfigDocument` plus save/revert.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var doc = ConfigDocument()
    @Published private(set) var savedText = ""
    @Published var recordingBind: UUID?
    @Published var lastSaveMessage: String?
    // View state (kept here: the CLT toolchain lacks the SwiftUI @State macro plugin).
    @Published var bindFilter = ""
    @Published var showErrors = false
    @Published var confirmReset = false
    @Published var selectedTab = "general"

    let store: ConfigStore
    var onSaved: (() -> Void)?
    /// true while a key combination is being recorded (global binds must be suspended).
    var onRecordingChanged: ((Bool) -> Void)?
    private var keyMonitor: Any?

    init(store: ConfigStore) {
        self.store = store
        reloadFromDisk()
    }

    var currentText: String { doc.serialize() }
    var isDirty: Bool { currentText != savedText }
    var errors: [String] { HyprConfig.parse(currentText).errors }

    /// The `$mod` variable expanded to modifiers.
    var modModifiers: Modifiers { Modifiers.parse(doc.variable("mod") ?? "").0 }

    func reloadFromDisk() {
        let text = store.readText() ?? HyprConfig.defaultText
        doc = ConfigDocument.parse(text)
        savedText = doc.serialize()
        lastSaveMessage = nil
    }

    func revert() { reloadFromDisk() }

    func resetToDefaults() {
        doc = ConfigDocument.parse(HyprConfig.defaultText)
    }

    func save() {
        let text = currentText
        do {
            try store.write(text)
            savedText = text
            lastSaveMessage = "保存して適用しました"
            onSaved?()
        } catch {
            lastSaveMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - Bind conflicts

    /// IDs of binds whose (expanded modifiers, key) collide with another bind.
    var conflictingBinds: Set<UUID> {
        var seen: [String: [UUID]] = [:]
        for b in doc.binds {
            let mods = Modifiers.parse(doc.expand(b.mods)).0.rawValue
            let code = KeyCodes.code(for: b.key).map(String.init) ?? b.key.lowercased()
            seen["\(mods)-\(code)", default: []].append(b.id)
        }
        return Set(seen.values.filter { $0.count > 1 }.flatMap { $0 })
    }

    // MARK: - Key recording

    func startRecording(_ id: UUID) {
        stopRecording()
        recordingBind = id
        onRecordingChanged?(true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.record(event) }
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if recordingBind != nil {
            recordingBind = nil
            onRecordingChanged?(false)
        }
    }

    private func record(_ event: NSEvent) {
        guard let id = recordingBind, let index = doc.binds.firstIndex(where: { $0.id == id }) else {
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 && flags.intersection([.command, .option, .control, .shift]).isEmpty {
            stopRecording()   // plain Escape cancels
            return
        }
        guard let key = KeyCodes.name(for: event.keyCode) else { return }
        var mods: Modifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        doc.binds[index].mods = Self.modsString(mods, mod: modModifiers)
        doc.binds[index].key = key
        stopRecording()
    }

    /// Writes modifiers using `$mod` when they include it.
    static func modsString(_ mods: Modifiers, mod: Modifiers) -> String {
        var rest = mods
        var tokens: [String] = []
        if !mod.isEmpty && mods.isSuperset(of: mod) {
            tokens.append("$mod")
            rest.subtract(mod)
        }
        if rest.contains(.command) { tokens.append("SUPER") }
        if rest.contains(.option) { tokens.append("ALT") }
        if rest.contains(.control) { tokens.append("CTRL") }
        if rest.contains(.shift) { tokens.append("SHIFT") }
        return tokens.joined(separator: " ")
    }
}
