import AppKit
import ApplicationServices
import HyprMacCore

final class ManagedWindow {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    var workspace: Int
    var isFloating: Bool
    /// Last on-screen frame of a floating window (restored when its workspace is shown).
    var floatingFrame: CGRect?

    init(id: CGWindowID, element: AXUIElement, pid: pid_t, appName: String, workspace: Int, isFloating: Bool) {
        self.id = id
        self.element = element
        self.pid = pid
        self.appName = appName
        self.workspace = workspace
        self.isFloating = isFloating
    }
}

final class Workspace {
    let id: Int
    let tree = DwindleTree()
    var floating: [CGWindowID] = []
    var fullscreen: CGWindowID?
    var lastFocused: CGWindowID?
    var lastDisplay: CGDirectDisplayID?
    init(id: Int) { self.id = id }

    var allWindows: [CGWindowID] { tree.windows + floating }
}

struct Monitor {
    let displayID: CGDirectDisplayID
    let frame: CGRect     // AX coordinates
    let visible: CGRect   // AX coordinates, without menu bar / Dock
    var workspace: Int
}

struct StatusSnapshot {
    var focusedWorkspace: Int
    var visibleWorkspaces: Set<Int>
    var occupiedWorkspaces: Set<Int>
    var specialShown: Bool
    var specialOccupied: Bool
}

/// Hyprland-style window manager on top of the macOS Accessibility API.
///
/// * Workspaces are virtual: windows of hidden workspaces are parked in a
///   monitor corner (like AeroSpace), so switching is instant — no Spaces animation.
/// * Each workspace tiles its windows with a dwindle tree.
/// * The special workspace is an overlay shown on top of the current workspace.
@MainActor
final class WindowManager {
    var config: HyprConfig
    var onStateChange: (() -> Void)?
    var onReloadRequest: (() -> Void)?
    private(set) var enabled = false

    private var windows: [CGWindowID: ManagedWindow] = [:]
    private var workspaces: [Int: Workspace] = [:]
    private var monitors: [Monitor] = []
    private var focusedMonitor = 0
    private var specialMonitor: Int?
    private var previousWorkspace: Int?
    private var rememberedWorkspace: [CGWindowID: Int] = [:]
    private var layoutFrames: [CGWindowID: CGRect] = [:]

    private var observers: [pid_t: AXObserver] = [:]
    private var observerFailures: [pid_t: Int] = [:]
    private var programmaticChange: [CGWindowID: Date] = [:]
    private var lastOwnFocus = Date.distantPast
    /// When a visible window closes, macOS may focus a sibling window parked on a
    /// hidden workspace. Don't follow that focus for a short while.
    private var lastVisibleRemoval = Date.distantPast
    private var refreshPending = false
    private var focusSyncWork: DispatchWorkItem?
    private var dragWork: DispatchWorkItem?
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []

    init(config: HyprConfig) {
        self.config = config
    }

    // MARK: - Lifecycle

    func start() {
        guard !enabled else { return }
        enabled = true
        rebuildMonitors()
        subscribeToWorkspaceNotifications()
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        for command in config.execOnce { exec(command) }
    }

    /// Stops managing windows and brings every parked window back on screen.
    func stop() {
        guard enabled else { return }
        restoreAllWindows()
        enabled = false
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        for token in notificationTokens {
            center.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        for obs in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observers.removeAll()
        observerFailures.removeAll()
        windows.removeAll()
        workspaces.removeAll()
        rememberedWorkspace.removeAll()
        layoutFrames.removeAll()
        specialMonitor = nil
        onStateChange?()
    }

    func restoreAllWindows() {
        guard let main = monitors.first else { return }
        let areas = monitors.map(\.frame)
        for w in windows.values {
            guard let frame = AX.frame(w.element) else { continue }
            if Geometry.visibleFraction(of: frame, in: areas) < 0.5 {
                var target = w.floatingFrame ?? Geometry.centered(
                    CGSize(width: min(frame.width, main.visible.width * 0.8),
                           height: min(frame.height, main.visible.height * 0.8)), in: main.visible)
                if Geometry.visibleFraction(of: target, in: areas) < 0.5 {
                    target = Geometry.centered(target.size, in: main.visible)
                }
                AX.setFrame(w.element, target)
            }
        }
    }

    func configDidChange() {
        guard enabled else { return }
        applyLayout()
    }

    // MARK: - Monitors

    func rebuildMonitors() {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let primaryHeight = primary.frame.height
        func toAX(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
        let old = monitors
        var result: [Monitor] = []
        let sorted = screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        for (i, screen) in sorted.enumerated() {
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? UInt32(i)
            var ws = old.first(where: { $0.displayID == id })?.workspace
            if ws == nil || result.contains(where: { $0.workspace == ws }) {
                ws = (1...99).first { n in !result.contains { $0.workspace == n } && !old.contains { $0.workspace == n } }
                    ?? (i + 1)
            }
            result.append(Monitor(displayID: id, frame: toAX(screen.frame), visible: toAX(screen.visibleFrame), workspace: ws!))
        }
        monitors = result
        focusedMonitor = min(focusedMonitor, max(0, monitors.count - 1))
        if let s = specialMonitor, s >= monitors.count { specialMonitor = nil }
    }

    private func monitorIndex(for rect: CGRect) -> Int {
        var best = (index: focusedMonitor, area: CGFloat(0))
        for (i, m) in monitors.enumerated() {
            let inter = m.frame.intersection(rect)
            let area = inter.isNull ? 0 : inter.width * inter.height
            if area > best.area { best = (i, area) }
        }
        return best.index
    }

    private func monitorShowing(_ ws: Int) -> Int? {
        if ws == specialWorkspaceID { return specialMonitor }
        return monitors.firstIndex { $0.workspace == ws }
    }

    private func isVisible(_ ws: Int) -> Bool { monitorShowing(ws) != nil }

    private func workspace(_ id: Int) -> Workspace {
        if let ws = workspaces[id] { return ws }
        let ws = Workspace(id: id)
        workspaces[id] = ws
        return ws
    }

    private func specialRect(on m: Monitor) -> CGRect {
        let s = config.specialScale
        let size = CGSize(width: (m.visible.width * s).rounded(), height: (m.visible.height * s).rounded())
        return Geometry.centered(size, in: m.visible)
    }

    /// Rectangle a workspace would be laid out in (its monitor, or the focused one).
    private func bounds(for ws: Int) -> CGRect {
        guard !monitors.isEmpty else { return .zero }
        if ws == specialWorkspaceID {
            return specialRect(on: monitors[specialMonitor ?? focusedMonitor])
        }
        if let i = monitorShowing(ws) { return monitors[i].visible }
        if let d = workspaces[ws]?.lastDisplay, let m = monitors.first(where: { $0.displayID == d }) { return m.visible }
        return monitors[focusedMonitor].visible
    }

    // MARK: - Window discovery

    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.refresh()
        }
    }

    func refresh(initial: Bool = false) {
        guard enabled, AXIsProcessTrusted(), !monitors.isEmpty else { return }
        var seen = Set<CGWindowID>()
        var changed = false
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let pid = app.processIdentifier
            ensureObserver(pid)
            if app.isHidden { continue }
            let appElement = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appElement, 0.5)
            for el in AX.elements(appElement, kAXWindowsAttribute) {
                guard AX.string(el, kAXRoleAttribute) == kAXWindowRole,
                      AX.string(el, kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      AX.bool(el, kAXMinimizedAttribute) != true,
                      let id = AX.windowID(el) else { continue }
                seen.insert(id)
                if windows[id] == nil {
                    addWindow(id: id, element: el, app: app, initial: initial)
                    changed = true
                }
            }
        }
        var removedVisible = false
        for id in Array(windows.keys) where !seen.contains(id) {
            if let w = windows[id], isVisible(w.workspace) { removedVisible = true }
            removeWindow(id)
            changed = true
        }
        if changed || initial {
            applyLayout()
            if removedVisible {
                // Like Hyprland: focus the next window of the current workspace.
                lastVisibleRemoval = Date()
                focusWorkspace(specialMonitor != nil ? specialWorkspaceID : monitors[focusedMonitor].workspace)
            }
            onStateChange?()
        }
    }

    private func addWindow(id: CGWindowID, element: AXUIElement, app: NSRunningApplication, initial: Bool) {
        let name = app.localizedName ?? ""
        let title = AX.string(element, kAXTitleAttribute) ?? ""
        let frame = AX.frame(element)
        var floating = !AX.isSettable(element, kAXSizeAttribute)
        var ws: Int
        if let remembered = rememberedWorkspace.removeValue(forKey: id) {
            ws = remembered
        } else if initial, let frame {
            ws = monitors[monitorIndex(for: frame)].workspace
        } else {
            ws = specialMonitor != nil ? specialWorkspaceID : monitors[focusedMonitor].workspace
        }
        for rule in config.rules where rule.matches(appName: name, bundleID: app.bundleIdentifier, title: title) {
            switch rule.action {
            case .float: floating = true
            case .tile: floating = false
            case .workspace(let n): ws = n
            }
        }

        let w = ManagedWindow(id: id, element: element, pid: app.processIdentifier, appName: name, workspace: ws, isFloating: floating)
        windows[id] = w
        if floating {
            if let frame, Geometry.visibleFraction(of: frame, in: monitors.map(\.frame)) > 0.3 {
                w.floatingFrame = frame
            } else if let frame {
                w.floatingFrame = Geometry.centered(frame.size, in: bounds(for: ws))
            }
            workspace(ws).floating.append(id)
        } else {
            insertTiled(w)
        }
        if let obs = observers[app.processIdentifier] {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for n in [kAXUIElementDestroyedNotification, kAXWindowMovedNotification,
                      kAXWindowResizedNotification, kAXWindowMiniaturizedNotification] {
                AXObserverAddNotification(obs, element, n as CFString, refcon)
            }
        }
    }

    private func insertTiled(_ w: ManagedWindow) {
        let ws = workspace(w.workspace)
        let target = ws.lastFocused.flatMap { ws.tree.contains($0) ? $0 : nil }
        ws.tree.insert(w.id, splitting: target, bounds: bounds(for: w.workspace))
    }

    private func detach(_ w: ManagedWindow) {
        guard let ws = workspaces[w.workspace] else { return }
        ws.tree.remove(w.id)
        ws.floating.removeAll { $0 == w.id }
        if ws.fullscreen == w.id { ws.fullscreen = nil }
        if ws.lastFocused == w.id { ws.lastFocused = nil }
    }

    private func removeWindow(_ id: CGWindowID) {
        guard let w = windows.removeValue(forKey: id) else { return }
        detach(w)
        layoutFrames[id] = nil
        programmaticChange[id] = nil
        // Hidden / minimised windows come back to the same workspace.
        if NSRunningApplication(processIdentifier: w.pid) != nil {
            rememberedWorkspace[id] = w.workspace
            if rememberedWorkspace.count > 500 { rememberedWorkspace.removeAll() }
        }
    }

    // MARK: - Layout

    func applyLayout() {
        guard enabled, !monitors.isEmpty else { return }
        var visible = Set<Int>()
        for m in monitors { visible.insert(m.workspace) }
        if specialMonitor != nil { visible.insert(specialWorkspaceID) }

        // 1. Park windows of hidden workspaces.
        for w in windows.values where !visible.contains(w.workspace) { park(w) }

        // 2. Lay out every visible workspace.
        layoutFrames.removeAll()
        for m in monitors {
            let ws = workspace(m.workspace)
            ws.lastDisplay = m.displayID
            layout(ws, in: m.visible, raise: false)
        }
        if let si = specialMonitor {
            let ws = workspace(specialWorkspaceID)
            ws.lastDisplay = monitors[si].displayID
            layout(ws, in: specialRect(on: monitors[si]), raise: true)
        }
    }

    private func layout(_ ws: Workspace, in rect: CGRect, raise: Bool) {
        var frames = ws.tree.layout(in: rect, gapsIn: config.gapsIn, gapsOut: config.gapsOut)
        if let fs = ws.fullscreen, frames[fs] != nil { frames[fs] = rect }
        for (id, frame) in frames {
            guard let w = windows[id] else { continue }
            layoutFrames[id] = frame
            setFrame(w, frame)
        }
        for id in ws.floating {
            guard let w = windows[id], let current = AX.frame(w.element) else { continue }
            if isParked(current) {
                var target = w.floatingFrame ?? Geometry.centered(current.size, in: rect)
                if !rect.intersects(target) { target = Geometry.centered(target.size, in: rect) }
                setFrame(w, target)
            }
        }
        if raise {
            for id in ws.allWindows { if let w = windows[id] { AX.raise(w.element) } }
        }
        if let fs = ws.fullscreen, let w = windows[fs] { AX.raise(w.element) }
    }

    private func setFrame(_ w: ManagedWindow, _ frame: CGRect) {
        if let current = AX.frame(w.element),
           abs(current.minX - frame.minX) < 1, abs(current.minY - frame.minY) < 1,
           abs(current.width - frame.width) < 1, abs(current.height - frame.height) < 1 { return }
        programmaticChange[w.id] = Date()
        AX.withoutEnhancedUI(pid: w.pid) { AX.setFrame(w.element, frame) }
    }

    /// Moves a window into the bottom-right corner of its monitor (1px visible),
    /// which is how AeroSpace emulates workspaces without macOS Spaces.
    private func park(_ w: ManagedWindow) {
        guard let current = AX.frame(w.element) else { return }
        if isParked(current) { return }
        if w.isFloating { w.floatingFrame = current }
        let ws = workspaces[w.workspace]
        let m = monitors.first { $0.displayID == ws?.lastDisplay } ?? monitors[monitorIndex(for: current)]
        var origin = CGPoint(x: m.frame.maxX - 1, y: m.frame.maxY - 1)
        let rightHasMonitor = monitors.contains { $0.frame.contains(CGPoint(x: m.frame.maxX + 2, y: m.frame.maxY - 2)) }
        if rightHasMonitor { origin.x = m.frame.minX - current.width + 1 }
        programmaticChange[w.id] = Date()
        AX.withoutEnhancedUI(pid: w.pid) { AX.setPosition(w.element, origin) }
    }

    private func isParked(_ frame: CGRect) -> Bool {
        Geometry.visibleFraction(of: frame, in: monitors.map(\.frame)) < 0.1
    }

    // MARK: - Focus

    private func focusedWindowID() -> CGWindowID? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        guard let win = AX.element(el, kAXFocusedWindowAttribute), let id = AX.windowID(win) else { return nil }
        return windows[id] != nil ? id : nil
    }

    /// The window dispatchers act on.
    private func activeWindow() -> ManagedWindow? {
        if let id = focusedWindowID(), let w = windows[id], isVisible(w.workspace) { return w }
        let wsID = specialMonitor != nil ? specialWorkspaceID : monitors[focusedMonitor].workspace
        if let id = workspaces[wsID]?.lastFocused { return windows[id] }
        return nil
    }

    private func focus(_ w: ManagedWindow) {
        lastOwnFocus = Date()
        workspace(w.workspace).lastFocused = w.id
        if let mi = monitorShowing(w.workspace) { focusedMonitor = mi }
        AX.focus(w.element, pid: w.pid)
        onStateChange?()
    }

    private func focusWorkspace(_ id: Int) {
        let ws = workspace(id)
        let candidate = ws.lastFocused.flatMap { windows[$0]?.workspace == id ? $0 : nil }
            ?? ws.tree.windows.first ?? ws.floating.first
        if let candidate, let w = windows[candidate] { focus(w) }
    }

    /// Called when macOS reports a focus change (click, Cmd-Tab, Dock ...).
    func scheduleFocusSync() {
        focusSyncWork?.cancel()
        let sinceOwn = Date().timeIntervalSince(lastOwnFocus)
        let delay = max(0.08, 0.35 - sinceOwn)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.syncFocus() }
        }
        focusSyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func syncFocus() {
        guard enabled, let id = focusedWindowID(), let w = windows[id] else { return }
        // After a visible window closes macOS may focus a parked sibling — not a user action.
        if !isVisible(w.workspace), w.workspace != specialWorkspaceID,
           Date().timeIntervalSince(lastVisibleRemoval) < 1.0 { return }
        workspace(w.workspace).lastFocused = id
        var changed = false
        if w.workspace == specialWorkspaceID {
            if specialMonitor == nil {
                specialMonitor = focusedMonitor
                changed = true
            }
        } else {
            if specialMonitor != nil {
                // Focus left the scratchpad: hide it, like a drop-down terminal.
                specialMonitor = nil
                changed = true
            }
            if let mi = monitors.firstIndex(where: { $0.workspace == w.workspace }) {
                focusedMonitor = mi
            } else {
                // The window lives on a hidden workspace (Cmd-Tab, Dock click): follow it.
                previousWorkspace = monitors[focusedMonitor].workspace
                monitors[focusedMonitor].workspace = w.workspace
                changed = true
            }
        }
        if changed {
            applyLayout()
            AX.raise(w.element)
        }
        onStateChange?()
    }

    // MARK: - Mouse drag (drop a tiled window onto another to swap)

    private func windowMovedOrResized(_ el: AXUIElement) {
        guard let id = AX.windowID(el), let w = windows[id], !w.isFloating else { return }
        if let t = programmaticChange[id], Date().timeIntervalSince(t) < 0.6 { return }
        scheduleDrop(id)
    }

    private func scheduleDrop(_ id: CGWindowID) {
        dragWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons & 1 != 0 {
                    self.scheduleDrop(id)
                } else {
                    self.handleDrop(id)
                }
            }
        }
        dragWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func handleDrop(_ id: CGWindowID) {
        guard enabled, let w = windows[id], !w.isFloating, let frame = AX.frame(w.element) else { return }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let ws = workspace(w.workspace)
        if let target = layoutFrames.first(where: { $0.key != id && ws.tree.contains($0.key) && $0.value.contains(center) })?.key {
            ws.tree.swap(id, target)
        } else if w.workspace != specialWorkspaceID,
                  let mi = monitors.firstIndex(where: { $0.frame.contains(center) }),
                  monitors[mi].workspace != w.workspace {
            detach(w)
            w.workspace = monitors[mi].workspace
            insertTiled(w)
            focusedMonitor = mi
        }
        applyLayout()
        onStateChange?()
    }

    // MARK: - Dispatchers

    func dispatch(_ dispatcher: String, _ arg: String) {
        guard enabled else { return }
        switch dispatcher {
        case "exec": exec(arg)
        case "killactive": if let w = activeWindow() { AX.close(w.element) }
        case "workspace": if let t = WorkspaceTarget(arg) { goTo(t) }
        case "movetoworkspace": if let t = WorkspaceTarget(arg) { moveActive(to: t, follow: true) }
        case "movetoworkspacesilent": if let t = WorkspaceTarget(arg) { moveActive(to: t, follow: false) }
        case "togglespecialworkspace": toggleSpecial()
        case "movefocus": if let d = Direction(arg) { moveFocus(d) }
        case "swapwindow", "movewindow": if let d = Direction(arg) { swapWindow(d) }
        case "togglefloating": toggleFloating()
        case "fullscreen": toggleFullscreen()
        case "togglesplit":
            if let w = activeWindow() { workspace(w.workspace).tree.toggleSplit(w.id); applyLayout() }
        case "splitratio":
            if let w = activeWindow(), let delta = Double(arg.replacingOccurrences(of: "+", with: "")) {
                workspace(w.workspace).tree.adjustRatio(w.id, by: CGFloat(delta))
                applyLayout()
            }
        case "focusmonitor": focusMonitor(arg)
        case "reload": onReloadRequest?()
        case "exit": NSApp.terminate(nil)
        default: break
        }
    }

    private func exec(_ command: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", command]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    private func resolve(_ target: WorkspaceTarget) -> Int? {
        let current = monitors[focusedMonitor].workspace
        switch target {
        case .number(let n): return n
        case .special: return specialWorkspaceID
        case .previous: return previousWorkspace
        case .relative(let delta):
            let occupied = Set(windows.values.map(\.workspace)).filter { $0 > 0 }
            let list = Array(occupied.union([current])).sorted()
            guard let i = list.firstIndex(of: current), !list.isEmpty else { return nil }
            return list[((i + delta) % list.count + list.count) % list.count]
        }
    }

    private func goTo(_ target: WorkspaceTarget) {
        guard let n = resolve(target) else { return }
        if n == specialWorkspaceID { toggleSpecial(); return }
        switchWorkspace(n)
    }

    func switchWorkspace(_ n: Int) {
        guard enabled, !monitors.isEmpty else { return }
        let current = monitors[focusedMonitor].workspace
        if let other = monitors.firstIndex(where: { $0.workspace == n }) {
            if other == focusedMonitor && specialMonitor == nil { return }
            focusedMonitor = other
        } else {
            previousWorkspace = current
            monitors[focusedMonitor].workspace = n
        }
        specialMonitor = nil
        applyLayout()
        focusWorkspace(n)
        onStateChange?()
    }

    func toggleSpecial() {
        guard enabled, !monitors.isEmpty else { return }
        if specialMonitor != nil {
            specialMonitor = nil
            applyLayout()
            focusWorkspace(monitors[focusedMonitor].workspace)
        } else {
            specialMonitor = focusedMonitor
            applyLayout()
            focusWorkspace(specialWorkspaceID)
        }
        onStateChange?()
    }

    private func moveActive(to target: WorkspaceTarget, follow: Bool) {
        guard let w = activeWindow(), let n = resolve(target), n != w.workspace else { return }
        detach(w)
        w.workspace = n
        if w.isFloating { workspace(n).floating.append(w.id) } else { insertTiled(w) }
        workspace(n).lastFocused = w.id

        if follow {
            if n == specialWorkspaceID {
                specialMonitor = focusedMonitor
            } else if let other = monitors.firstIndex(where: { $0.workspace == n }) {
                focusedMonitor = other
                specialMonitor = nil
            } else {
                previousWorkspace = monitors[focusedMonitor].workspace
                monitors[focusedMonitor].workspace = n
                specialMonitor = nil
            }
            applyLayout()
            focus(w)
        } else {
            applyLayout()
            if !isVisible(n) {
                // The window left the screen: focus what remains on the current layer.
                focusWorkspace(specialMonitor != nil ? specialWorkspaceID : monitors[focusedMonitor].workspace)
            }
        }
        onStateChange?()
    }

    private func visibleCandidates(sameLayerAs w: ManagedWindow?) -> [(CGWindowID, CGRect)] {
        let inSpecial = w?.workspace == specialWorkspaceID
        return windows.values.compactMap { other in
            guard isVisible(other.workspace) else { return nil }
            if specialMonitor != nil && (other.workspace == specialWorkspaceID) != inSpecial { return nil }
            guard let f = layoutFrames[other.id] ?? AX.frame(other.element) else { return nil }
            return (other.id, f)
        }
    }

    private func moveFocus(_ d: Direction) {
        guard let w = activeWindow(), let frame = layoutFrames[w.id] ?? AX.frame(w.element) else {
            focusMonitor(in: d)
            return
        }
        let candidates = visibleCandidates(sameLayerAs: w).filter { $0.0 != w.id }
        if let id = Geometry.neighbor(of: frame, in: candidates, direction: d), let target = windows[id] {
            focus(target)
        } else {
            focusMonitor(in: d)
        }
    }

    private func swapWindow(_ d: Direction) {
        guard let w = activeWindow(), !w.isFloating, let frame = layoutFrames[w.id] else { return }
        let ws = workspace(w.workspace)
        let candidates = ws.tree.windows.filter { $0 != w.id }.compactMap { id in layoutFrames[id].map { (id, $0) } }
        if let other = Geometry.neighbor(of: frame, in: candidates, direction: d) {
            ws.tree.swap(w.id, other)
            applyLayout()
            focus(w)
            return
        }
        // Nothing in that direction: push the window to the neighbouring monitor.
        guard w.workspace != specialWorkspaceID,
              let mi = monitorIndex(in: d), monitors[mi].workspace != w.workspace else { return }
        detach(w)
        w.workspace = monitors[mi].workspace
        insertTiled(w)
        focusedMonitor = mi
        applyLayout()
        focus(w)
    }

    private func monitorIndex(in d: Direction) -> Int? {
        guard monitors.indices.contains(focusedMonitor) else { return nil }
        let candidates = monitors.enumerated().filter { $0.offset != focusedMonitor }.map { ($0.offset, $0.element.frame) }
        return Geometry.neighbor(of: monitors[focusedMonitor].frame, in: candidates, direction: d)
    }

    private func focusMonitor(in d: Direction) {
        guard let mi = monitorIndex(in: d) else { return }
        focusedMonitor = mi
        specialMonitor = nil
        applyLayout()
        focusWorkspace(monitors[mi].workspace)
        onStateChange?()
    }

    private func focusMonitor(_ arg: String) {
        if let d = Direction(arg) { focusMonitor(in: d); return }
        guard let delta = Int(arg.replacingOccurrences(of: "+", with: "")), !monitors.isEmpty else { return }
        focusedMonitor = ((focusedMonitor + delta) % monitors.count + monitors.count) % monitors.count
        focusWorkspace(monitors[focusedMonitor].workspace)
        onStateChange?()
    }

    private func toggleFloating() {
        guard let w = activeWindow() else { return }
        let ws = workspace(w.workspace)
        if w.isFloating {
            ws.floating.removeAll { $0 == w.id }
            w.isFloating = false
            insertTiled(w)
        } else {
            ws.tree.remove(w.id)
            if ws.fullscreen == w.id { ws.fullscreen = nil }
            w.isFloating = true
            ws.floating.append(w.id)
            let b = bounds(for: w.workspace)
            let frame = Geometry.centered(CGSize(width: (b.width * 0.6).rounded(), height: (b.height * 0.6).rounded()), in: b)
            w.floatingFrame = frame
            setFrame(w, frame)
        }
        applyLayout()
        focus(w)
    }

    private func toggleFullscreen() {
        guard let w = activeWindow(), !w.isFloating else { return }
        let ws = workspace(w.workspace)
        ws.fullscreen = ws.fullscreen == w.id ? nil : w.id
        applyLayout()
        focus(w)
    }

    // MARK: - Status

    func snapshot() -> StatusSnapshot {
        StatusSnapshot(
            focusedWorkspace: monitors.indices.contains(focusedMonitor) ? monitors[focusedMonitor].workspace : 1,
            visibleWorkspaces: Set(monitors.map(\.workspace)),
            occupiedWorkspaces: Set(windows.values.map(\.workspace)).filter { $0 > 0 },
            specialShown: specialMonitor != nil,
            specialOccupied: windows.values.contains { $0.workspace == specialWorkspaceID }
        )
    }

    // MARK: - Notifications

    private func subscribeToWorkspaceNotifications() {
        let nc = NSWorkspace.shared.notificationCenter
        let refreshNames: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in refreshNames {
            notificationTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scheduleRefresh()
                    // Freshly launched apps often expose their windows a bit later.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.scheduleRefresh() }
                }
            })
        }
        notificationTokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                if let pid { self.dropObserver(pid) }
                self.scheduleRefresh()
            }
        })
        notificationTokens.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleFocusSync() }
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.enabled else { return }
                self.rebuildMonitors()
                self.applyLayout()
                self.onStateChange?()
            }
        })
    }

    private func ensureObserver(_ pid: pid_t) {
        guard observers[pid] == nil, observerFailures[pid, default: 0] < 10 else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let obs = created else {
            observerFailures[pid, default: 0] += 1
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var ok = false
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification,
                  kAXApplicationHiddenNotification, kAXApplicationShownNotification, kAXWindowDeminiaturizedNotification] {
            if AXObserverAddNotification(obs, app, n as CFString, refcon) == .success { ok = true }
        }
        guard ok else {
            observerFailures[pid, default: 0] += 1
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    private func dropObserver(_ pid: pid_t) {
        if let obs = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observerFailures[pid] = nil
    }

    fileprivate func handleAXNotification(_ name: String, _ element: AXUIElement) {
        guard enabled else { return }
        switch name {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            windowMovedOrResized(element)
        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            scheduleRefresh()
            scheduleFocusSync()
        default:
            scheduleRefresh()
        }
    }
}

private func axObserverCallback(observer: AXObserver, element: AXUIElement, notification: CFString,
                                refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let wm = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated { wm.handleAXNotification(name, element) }
}
