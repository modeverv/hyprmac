import AppKit
import HyprMacCore

/// Waybar-ish workspace indicator in the macOS menu bar.
@MainActor
final class StatusBar: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    var onReload: (() -> Void)?
    var onOpenConfig: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onWorkspace: ((Int) -> Void)?
    var onToggleSpecial: (() -> Void)?
    var onSettings: (() -> Void)?

    override init() {
        super.init()
        item.menu = menu
        showMessage("HyprMac")
    }

    func showMessage(_ text: String) {
        item.button?.attributedTitle = NSAttributedString(string: text, attributes: [.font: Self.font(bold: false)])
    }

    func update(snapshot s: StatusSnapshot?, paused: Bool, trusted: Bool, configErrors: [String], configPath: String) {
        if !trusted {
            showMessage("⚠︎ HyprMac")
        } else if paused || s == nil {
            showMessage("⏸ HyprMac")
        } else if let s {
            let title = NSMutableAttributedString()
            let shown = s.occupiedWorkspaces.union(s.visibleWorkspaces).union([s.focusedWorkspace]).sorted()
            for (i, n) in shown.enumerated() {
                if i > 0 { title.append(NSAttributedString(string: " ")) }
                title.append(label(n == 10 ? "0" : "\(n)",
                                   active: n == s.focusedWorkspace && !s.specialShown,
                                   visible: s.visibleWorkspaces.contains(n),
                                   occupied: s.occupiedWorkspaces.contains(n)))
            }
            if s.specialOccupied || s.specialShown {
                title.append(NSAttributedString(string: "  "))
                title.append(label("S", active: s.specialShown, visible: s.specialShown, occupied: s.specialOccupied))
            }
            item.button?.attributedTitle = title
        }
        rebuildMenu(snapshot: s, paused: paused, trusted: trusted, configErrors: configErrors, configPath: configPath)
    }

    private func label(_ text: String, active: Bool, visible: Bool, occupied: Bool) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [.font: Self.font(bold: active || visible)]
        if active {
            attrs[.foregroundColor] = NSColor.controlAccentColor
            attrs[.underlineStyle] = NSUnderlineStyle.thick.rawValue
        } else if !occupied {
            attrs[.foregroundColor] = NSColor.tertiaryLabelColor
        }
        return NSAttributedString(string: text, attributes: attrs)
    }

    private static func font(bold: Bool) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: 13, weight: bold ? .bold : .regular)
    }

    private func rebuildMenu(snapshot s: StatusSnapshot?, paused: Bool, trusted: Bool, configErrors: [String], configPath: String) {
        menu.removeAllItems()
        if !trusted {
            menu.addItem(action("アクセシビリティを許可…", #selector(openAccessibility)))
            menu.addItem(.separator())
        }
        if let s, !paused {
            for n in s.occupiedWorkspaces.union([s.focusedWorkspace]).sorted() {
                let mi = action("ワークスペース \(n)", #selector(goWorkspace(_:)))
                mi.tag = n
                mi.state = n == s.focusedWorkspace ? .on : .off
                menu.addItem(mi)
            }
            let special = action(s.specialShown ? "Special workspace を隠す" : "Special workspace を表示", #selector(toggleSpecial))
            menu.addItem(special)
            menu.addItem(.separator())
        }
        let settings = action("設定…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(action("設定を再読み込み", #selector(reload)))
        menu.addItem(action("設定ファイルを開く", #selector(openConfig)))
        let pathItem = NSMenuItem(title: configPath, action: nil, keyEquivalent: "")
        pathItem.isEnabled = false
        menu.addItem(pathItem)
        if !configErrors.isEmpty {
            let errItem = NSMenuItem(title: "設定エラー (\(configErrors.count))", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for e in configErrors.prefix(30) {
                let i = NSMenuItem(title: e, action: nil, keyEquivalent: "")
                i.isEnabled = false
                sub.addItem(i)
            }
            errItem.submenu = sub
            menu.addItem(errItem)
        }
        menu.addItem(.separator())
        menu.addItem(action(paused ? "タイリングを再開" : "タイリングを一時停止(ウィンドウを戻す)", #selector(togglePause)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "HyprMac を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        mi.target = self
        return mi
    }

    @objc private func reload() { onReload?() }
    @objc private func openConfig() { onOpenConfig?() }
    @objc private func openSettings() { onSettings?() }
    @objc private func togglePause() { onTogglePause?() }
    @objc private func toggleSpecial() { onToggleSpecial?() }
    @objc private func goWorkspace(_ sender: NSMenuItem) { onWorkspace?(sender.tag) }
    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
