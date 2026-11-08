import AppKit
import ApplicationServices
import HyprMacCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store: ConfigStore
    private var config: HyprConfig
    private let wm: WindowManager
    private let keyboard = KeyboardTap()
    private var statusBar: StatusBar!
    private lazy var settingsModel = SettingsModel(store: store)
    private lazy var settingsWindow = SettingsWindowController(model: settingsModel)
    private var paused = false
    private var pollTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    init(configPath: String?) {
        store = ConfigStore(path: configPath)
        config = store.load()
        wm = WindowManager(config: config)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBar()
        statusBar.onReload = { [weak self] in self?.reloadConfig() }
        statusBar.onOpenConfig = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.store.url)
        }
        statusBar.onTogglePause = { [weak self] in self?.togglePause() }
        statusBar.onSettings = { [weak self] in self?.settingsWindow.show() }
        statusBar.onWorkspace = { [weak self] n in self?.wm.switchWorkspace(n) }
        statusBar.onToggleSpecial = { [weak self] in self?.wm.toggleSpecial() }

        wm.onStateChange = { [weak self] in self?.updateStatus() }
        wm.onReloadRequest = { [weak self] in self?.reloadConfig() }
        keyboard.onBind = { [weak self] bind in self?.wm.dispatch(bind.dispatcher, bind.argument) }
        keyboard.setBinds(config.binds)
        settingsModel.onSaved = { [weak self] in self?.reloadConfig() }
        settingsModel.onRecordingChanged = { [weak self] recording in
            guard let self else { return }
            // Let the settings window see combos that are currently bound.
            self.keyboard.setBinds(recording || self.paused ? [] : self.config.binds)
        }
        installMainMenu()

        for e in config.errors { log("config: \(e)") }
        installSignalHandlers()

        // Prompt for Accessibility permission, then wait until it is granted.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startManaging()
        } else {
            log("waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)")
            updateStatus()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        wm.stop()
    }

    private func poll() {
        if !wm.enabled && !paused && AXIsProcessTrusted() { startManaging() }
        if store.hasChanged() { reloadConfig() }
    }

    private func startManaging() {
        guard !paused else { return }
        if !keyboard.start() {
            log("could not create the keyboard event tap (Accessibility permission missing?)")
            updateStatus()
            return
        }
        wm.start()
        log("managing windows — \(config.binds.count) binds loaded from \(store.url.path)")
        updateStatus()
    }

    private func togglePause() {
        paused.toggle()
        if paused {
            wm.stop()
            keyboard.setBinds([])
        } else {
            keyboard.setBinds(config.binds)
            startManaging()
        }
        updateStatus()
    }

    private func reloadConfig() {
        config = store.load()
        wm.config = config
        if !paused { keyboard.setBinds(config.binds) }
        wm.configDidChange()
        log("config reloaded (\(config.binds.count) binds, \(config.rules.count) rules, \(config.errors.count) errors)")
        for e in config.errors { log("config: \(e)") }
        updateStatus()
    }

    private func updateStatus() {
        statusBar?.update(snapshot: wm.enabled ? wm.snapshot() : nil, paused: paused,
                          trusted: AXIsProcessTrusted(), configErrors: config.errors, configPath: store.url.path)
    }

    /// An accessory app has no menu bar, but text fields need Edit-menu shortcuts (⌘C/⌘V/⌘Z...).
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "ウィンドウを閉じる", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "HyprMac を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() { settingsWindow.show() }

    /// Ctrl-C / kill must not leave windows parked off-screen.
    private func installSignalHandlers() {
        for sig in [SIGINT, SIGTERM, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.wm.stop() }
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("[hyprmac] \(message)\n".utf8))
}
