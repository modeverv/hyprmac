import AppKit
import HyprMacCore

/// Global hotkeys via a CGEventTap. Matching key-downs are swallowed so the
/// focused app never sees them (like Hyprland binds).
/// (Carbon RegisterEventHotKey is not used: Option-only hotkeys are blocked on recent macOS.)
@MainActor
final class KeyboardTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var binds: [UInt16: [KeyBind]] = [:]
    var onBind: ((KeyBind) -> Void)?

    func setBinds(_ list: [KeyBind]) {
        binds = Dictionary(grouping: list, by: \.keyCode)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyboardTapCallback,
            userInfo: refcon
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reenable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Returns true when the event matched a bind (and must be swallowed).
    func handle(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard let candidates = binds[keyCode] else { return false }
        var mods: Modifiers = []
        if flags.contains(.maskCommand) { mods.insert(.command) }
        if flags.contains(.maskAlternate) { mods.insert(.option) }
        if flags.contains(.maskControl) { mods.insert(.control) }
        if flags.contains(.maskShift) { mods.insert(.shift) }
        guard let bind = candidates.first(where: { $0.modifiers == mods }) else { return false }
        // Run outside of the tap callback so a slow AX call can't time the tap out.
        DispatchQueue.main.async { [weak self] in self?.onBind?(bind) }
        return true
    }
}

private func keyboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyboardTap>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    let swallow = MainActor.assumeIsolated { tap.handle(keyCode: keyCode, flags: flags) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
