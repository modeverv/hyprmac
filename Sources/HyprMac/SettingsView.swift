import AppKit
import HyprMacCore
import SwiftUI

// MARK: - Window controller

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "HyprMac 設定"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 860, height: 600))
            w.minSize = NSSize(width: 720, height: 460)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        if !model.isDirty { model.reloadFromDisk() }
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.stopRecording()
    }
}

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $model.selectedTab) {
                GeneralTab(model: model).tabItem { Label("一般", systemImage: "gearshape") }.tag("general")
                BindsTab(model: model).tabItem { Label("キー割り当て", systemImage: "keyboard") }.tag("binds")
                RulesTab(model: model).tabItem { Label("ウィンドウルール", systemImage: "macwindow.on.rectangle") }.tag("rules")
                StartupTab(model: model).tabItem { Label("起動時コマンド", systemImage: "play.circle") }.tag("startup")
            }
            .padding([.horizontal, .top], 12)

            Divider().padding(.top, 8)
            footer.padding(12)
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    private var footer: some View {
        let errors = model.errors
        return HStack(spacing: 10) {
            if errors.isEmpty {
                Label(model.isDirty ? "未保存の変更があります" : (model.lastSaveMessage ?? "設定は有効です"),
                      systemImage: model.isDirty ? "pencil.circle" : "checkmark.circle")
                    .foregroundStyle(model.isDirty ? Color.orange : Color.green)
            } else {
                Button {
                    model.showErrors.toggle()
                } label: {
                    Label("\(errors.count) 件のエラー", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $model.showErrors, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(errors, id: \.self) { Text($0).font(.system(.body, design: .monospaced)) }
                    }
                    .padding()
                }
            }
            Spacer()
            Button("デフォルトに戻す…") { model.confirmReset = true }
                .confirmationDialog("すべての設定をデフォルトに戻しますか?(保存するまでファイルは変更されません)",
                                    isPresented: $model.confirmReset) {
                    Button("デフォルトに戻す", role: .destructive) { model.resetToDefaults() }
                }
            Button("エディタで開く") { NSWorkspace.shared.open(model.store.url) }
            Button("元に戻す") { model.revert() }
                .disabled(!model.isDirty)
            Button("保存して適用") { model.save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.isDirty || !errors.isEmpty)
        }
    }
}

// MARK: - General

private let modChoices: [(value: String, label: String)] = [
    ("ALT", "⌥ Option(推奨)"),
    ("SUPER", "⌘ Command(動画と同じ)"),
    ("CTRL", "⌃ Control"),
    ("ALT CTRL", "⌥⌃ Option + Control"),
    ("CTRL SHIFT", "⌃⇧ Control + Shift"),
    ("SUPER CTRL", "⌘⌃ Command + Control"),
]

struct GeneralTab: View {
    @ObservedObject var model: SettingsModel

    private var modBinding: Binding<String> {
        Binding(get: { model.doc.variable("mod") ?? "ALT" },
                set: { model.doc.setVariable("mod", $0) })
    }

    var body: some View {
        Form {
            Section("修飾キー ($mod)") {
                Picker("$mod", selection: modBinding) {
                    ForEach(choices, id: \.value) { Text($0.label).tag($0.value) }
                }
                if model.modModifiers.contains(.command) {
                    Text("⌘S や ⌘1〜9 などが HyprMac に奪われ、アプリの保存やタブ切り替えが効かなくなります。")
                        .font(.callout).foregroundStyle(.orange)
                }
            }

            Section("隙間 (gaps)") {
                LabeledSlider(title: "ウィンドウ間 (gaps_in)", value: $model.doc.gapsIn, range: 0...40, step: 1, unit: "px")
                LabeledSlider(title: "画面の端 (gaps_out)", value: $model.doc.gapsOut, range: 0...80, step: 1, unit: "px")
            }

            Section("Special workspace") {
                LabeledSlider(title: "画面に対する大きさ (scale)", value: $model.doc.specialScale, range: 0.3...1.0, step: 0.05, unit: "", percent: true)
            }

            Section {
                ForEach($model.doc.variables) { $v in
                    if v.name != "mod" {
                        HStack {
                            Text("$").foregroundStyle(.secondary)
                            TextField("名前", text: $v.name).frame(width: 140)
                            Text("=").foregroundStyle(.secondary)
                            TextField("値", text: $v.value)
                                .multilineTextAlignment(.leading)
                            Button(role: .destructive) {
                                model.doc.variables.removeAll { $0.id == v.id }
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                        }
                        .labelsHidden()
                    }
                }
                Button {
                    model.doc.variables.append(.init(name: "var\(model.doc.variables.count)", value: ""))
                } label: { Label("変数を追加", systemImage: "plus") }
            } header: {
                Text("変数")
            } footer: {
                Text("キー割り当ての引数などで $terminal のように参照できます。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var choices: [(value: String, label: String)] {
        let current = model.doc.variable("mod") ?? "ALT"
        return modChoices.contains { $0.value == current } ? modChoices : modChoices + [(current, current)]
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var percent = false

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
            Text(percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value)) \(unit)")
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - Binds

private let dispatcherHelp: [String: String] = [
    "exec": "シェルコマンドを実行",
    "killactive": "ウィンドウを閉じる",
    "workspace": "ワークスペースへ (1〜99 / e+1 / e-1 / previous)",
    "movetoworkspace": "ウィンドウを移動して追従",
    "movetoworkspacesilent": "ウィンドウだけ移動",
    "togglespecialworkspace": "special workspace の表示切替",
    "movefocus": "フォーカス移動 (l r u d)",
    "swapwindow": "ウィンドウ入れ替え (l r u d)",
    "movewindow": "ウィンドウ入れ替え (l r u d)",
    "togglefloating": "フローティング切替",
    "fullscreen": "フルスクリーン切替",
    "togglesplit": "分割方向の切替",
    "splitratio": "分割比率 (+0.05 / -0.05)",
    "focusmonitor": "モニタ移動 (l r / +1 -1)",
    "reload": "設定の再読み込み",
    "exit": "HyprMac を終了",
]

private let argumentHint: [String: String] = [
    "exec": "コマンド(例: open -a Safari)",
    "workspace": "1〜99 / e+1 / e-1 / previous / special",
    "movetoworkspace": "1〜99 / special",
    "movetoworkspacesilent": "1〜99 / special",
    "movefocus": "l / r / u / d",
    "swapwindow": "l / r / u / d",
    "movewindow": "l / r / u / d",
    "splitratio": "+0.05 / -0.05",
    "focusmonitor": "l / r / +1 / -1",
]

/// Small on/off pill for a modifier key.
struct ModChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isOn ? .bold : .regular))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 22)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .foregroundStyle(isOn ? Color.white : Color.secondary)
                .background(RoundedRectangle(cornerRadius: 5).fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct BindsTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let conflicts = model.conflictingBinds
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("検索 (キー・動作・引数)", text: $model.bindFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Text("\(Image(systemName: "keyboard")) を押してからキーを入力すると記録できます(Esc で中止)")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    model.doc.binds.append(.init(mods: "$mod", key: "a", dispatcher: "exec", argument: ""))
                } label: { Label("追加", systemImage: "plus") }
            }
            HStack(spacing: 8) {
                Text("修飾キー").frame(width: 190, alignment: .leading)
                Text("キー").frame(width: 150, alignment: .leading)
                Text("動作").frame(width: 190, alignment: .leading)
                Text("引数")
            }
            .font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 8)

            List {
                ForEach($model.doc.binds) { $bind in
                    if matches(bind) {
                        BindRow(bind: $bind, model: model, conflict: conflicts.contains(bind.id))
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func matches(_ b: ConfigDocument.Bind) -> Bool {
        let f = model.bindFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !f.isEmpty else { return true }
        return [b.mods, b.key, b.dispatcher, b.argument].contains { $0.lowercased().contains(f) }
    }
}

struct BindRow: View {
    @Binding var bind: ConfigDocument.Bind
    @ObservedObject var model: SettingsModel
    let conflict: Bool

    private static let modTokens: [(token: String, label: String, help: String)] = [
        ("$mod", "mod", "$mod(一般タブで設定した修飾キー)"),
        ("SUPER", "⌘", "Command"),
        ("ALT", "⌥", "Option"),
        ("CTRL", "⌃", "Control"),
        ("SHIFT", "⇧", "Shift"),
    ]

    private func tokens() -> Set<String> {
        Set(bind.mods.split(whereSeparator: { " _+".contains($0) }).map { t -> String in
            let u = t.uppercased()
            switch u {
            case "$MOD": return "$mod"
            case "CMD", "COMMAND", "META", "WIN", "MOD4": return "SUPER"
            case "OPT", "OPTION", "MOD1": return "ALT"
            case "CONTROL": return "CTRL"
            default: return u
            }
        })
    }

    private func toggle(_ token: String) {
        var set = tokens()
        if set.contains(token) { set.remove(token) } else { set.insert(token) }
        bind.mods = Self.modTokens.map(\.token).filter { set.contains($0) }.joined(separator: " ")
    }

    private var keyBinding: Binding<String> {
        Binding(get: { KeyCodes.code(for: bind.key).flatMap { KeyCodes.name(for: $0) } ?? bind.key.lowercased() },
                set: { bind.key = $0 })
    }

    var body: some View {
        let recording = model.recordingBind == bind.id
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Self.modTokens, id: \.token) { m in
                    ModChip(label: m.label, isOn: tokens().contains(m.token)) { toggle(m.token) }
                        .help(m.help)
                }
            }
            .frame(width: 190, alignment: .leading)

            HStack(spacing: 4) {
                Picker("", selection: keyBinding) {
                    ForEach(keyChoices, id: \.self) { Text(displayName($0)).tag($0) }
                }
                .labelsHidden()
                .frame(width: 110)
                Button {
                    recording ? model.stopRecording() : model.startRecording(bind.id)
                } label: {
                    Image(systemName: recording ? "record.circle.fill" : "keyboard")
                        .foregroundStyle(recording ? Color.red : Color.primary)
                }
                .buttonStyle(.borderless)
                .help("キーの組み合わせを記録")
            }
            .frame(width: 150, alignment: .leading)

            Picker("", selection: $bind.dispatcher) {
                ForEach(dispatcherChoices, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 190)
            .help(dispatcherHelp[bind.dispatcher] ?? "")

            TextField(argumentHint[bind.dispatcher] ?? "", text: $bind.argument)
                .textFieldStyle(.roundedBorder)

            if conflict {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("同じキーの組み合わせが他にもあります(先に書かれたものが優先)")
            }
            Button(role: .destructive) {
                if recording { model.stopRecording() }
                model.doc.binds.removeAll { $0.id == bind.id }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 1)
        .background(recording ? Color.red.opacity(0.08) : Color.clear)
    }

    private var keyChoices: [String] {
        let current = keyBinding.wrappedValue
        return KeyCodes.canonicalNames.contains(current) ? KeyCodes.canonicalNames : [current] + KeyCodes.canonicalNames
    }

    private var dispatcherChoices: [String] {
        let all = HyprConfig.dispatchers.sorted()
        return all.contains(bind.dispatcher) ? all : [bind.dispatcher] + all
    }

    private func displayName(_ key: String) -> String {
        switch key {
        case "left": return "← left"
        case "right": return "→ right"
        case "up": return "↑ up"
        case "down": return "↓ down"
        case "return": return "↩ return"
        case "tab": return "⇥ tab"
        case "space": return "␣ space"
        case "grave": return "` grave"
        case "minus": return "- minus"
        case "equal": return "= equal"
        case "comma": return ", comma"
        case "period": return ". period"
        case "slash": return "/ slash"
        default: return key.count == 1 ? key.uppercased() : key
        }
    }
}

// MARK: - Rules

struct RulesTab: View {
    @ObservedObject var model: SettingsModel

    private static let actions: [String] = ["float", "tile", "workspace special"] + (1...10).map { "workspace \($0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("class はアプリ名またはバンドル ID、title はウィンドウタイトルに対する正規表現です(大文字小文字は区別しません)。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(runningApps(), id: \.self) { name in
                        Button(name) {
                            model.doc.rules.append(.init(action: "float", classPattern: "^(\(NSRegularExpression.escapedPattern(for: name)))$", titlePattern: ""))
                        }
                    }
                } label: { Label("実行中のアプリから追加", systemImage: "app.badge") }
                .fixedSize()
                Button {
                    model.doc.rules.append(.init(action: "float", classPattern: "", titlePattern: ""))
                } label: { Label("追加", systemImage: "plus") }
            }
            HStack(spacing: 8) {
                Text("動作").frame(width: 170, alignment: .leading)
                Text("class (アプリ)").frame(maxWidth: .infinity, alignment: .leading)
                Text("title (任意)").frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 20)
            }
            .font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 8)

            List {
                ForEach($model.doc.rules) { $rule in
                    HStack(spacing: 8) {
                        Picker("", selection: $rule.action) {
                            ForEach(actionChoices(rule.action), id: \.self) { Text(actionLabel($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        TextField("^(Slack|Messages)$", text: $rule.classPattern)
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(isValidRegex(rule.classPattern) ? Color.primary : Color.red)
                        TextField("", text: $rule.titlePattern)
                            .textFieldStyle(.roundedBorder)
                            .foregroundStyle(isValidRegex(rule.titlePattern) ? Color.primary : Color.red)
                        Button(role: .destructive) {
                            model.doc.rules.removeAll { $0.id == rule.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .frame(width: 20)
                    }
                }
                .onMove { model.doc.rules.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func actionChoices(_ current: String) -> [String] {
        Self.actions.contains(current) ? Self.actions : [current] + Self.actions
    }

    private func actionLabel(_ a: String) -> String {
        switch a {
        case "float": return "フローティング"
        case "tile": return "タイル"
        case "workspace special": return "special workspace へ"
        default:
            if a.hasPrefix("workspace ") { return "ワークスペース \(a.dropFirst(10)) へ" }
            return a
        }
    }

    private func isValidRegex(_ p: String) -> Bool {
        p.isEmpty || (try? NSRegularExpression(pattern: p)) != nil
    }

    private func runningApps() -> [String] {
        Array(Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName))).sorted()
    }
}

// MARK: - Startup

struct StartupTab: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(model.doc.execOnce.indices, id: \.self) { i in
                    HStack {
                        TextField("open -a Obsidian", text: Binding(
                            get: { i < model.doc.execOnce.count ? model.doc.execOnce[i] : "" },
                            set: { if i < model.doc.execOnce.count { model.doc.execOnce[i] = $0 } }))
                        Button(role: .destructive) {
                            model.doc.execOnce.remove(at: i)
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button { model.doc.execOnce.append("") } label: { Label("コマンドを追加", systemImage: "plus") }
            } header: {
                Text("exec-once")
            } footer: {
                Text("HyprMac の起動時に一度だけ /bin/sh -c で実行されます。").font(.caption).foregroundStyle(.secondary)
            }

            if !model.doc.extraLines.isEmpty {
                Section("設定画面で編集できない行(そのまま保存されます)") {
                    ForEach(model.doc.extraLines, id: \.self) {
                        Text($0).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }

            Section("設定ファイル") {
                Text(model.store.url.path).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text("保存すると設定ファイルは再生成され、コメントは保持されません。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Standalone settings app (`HyprMac --settings`)

@MainActor
final class SettingsOnlyDelegate: NSObject, NSApplicationDelegate {
    private let controller: SettingsWindowController

    init(configPath: String?, tab: String?) {
        let model = SettingsModel(store: ConfigStore(path: configPath))
        if let tab, ["general", "binds", "rules", "startup"].contains(tab) { model.selectedTab = tab }
        controller = SettingsWindowController(model: model)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "編集")
        edit.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
        controller.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
