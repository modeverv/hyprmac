import AppKit
import HyprMacCore

let arguments = CommandLine.arguments

func argumentValue(_ flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    hyprmac — Hyprland-like tiling window manager for macOS

      hyprmac                       run (menu bar app)
      hyprmac --config PATH         use another config file
      hyprmac --settings [TAB]      open only the settings window (general|binds|rules|startup)
      hyprmac --check-config [PATH] validate a config and exit
      hyprmac --print-default-config
    """)
    exit(0)
}

if arguments.contains("--print-default-config") {
    print(HyprConfig.defaultText)
    exit(0)
}

if arguments.contains("--check-config") {
    let store = ConfigStore(path: argumentValue("--check-config").flatMap { $0.hasPrefix("-") ? nil : $0 })
    let config = store.load()
    print("\(store.url.path): \(config.binds.count) binds, \(config.rules.count) rules, gaps_in=\(config.gapsIn) gaps_out=\(config.gapsOut)")
    for e in config.errors { print("error: \(e)") }
    exit(config.errors.isEmpty ? 0 : 1)
}

if arguments.contains("--settings") {
    // Settings window only: no window management, no Accessibility prompt.
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = SettingsOnlyDelegate(configPath: argumentValue("--config"),
                                            tab: argumentValue("--settings").flatMap { $0.hasPrefix("-") ? nil : $0 })
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(configPath: argumentValue("--config"))
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
