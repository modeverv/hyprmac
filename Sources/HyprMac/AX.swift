import AppKit
import ApplicationServices

/// Private but stable API used by yabai / AeroSpace / Amethyst to map an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Thin helpers over the Accessibility C API. Coordinates are AX/Quartz global (top-left origin).
enum AX {
    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(el, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func raw(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        raw(el, name) as? String
    }

    static func bool(_ el: AXUIElement, _ name: String) -> Bool? {
        guard let v = raw(el, name), CFGetTypeID(v) == CFBooleanGetTypeID() else { return nil }
        return CFBooleanGetValue((v as! CFBoolean))
    }

    static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = raw(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let v = raw(el, name), CFGetTypeID(v) == CFArrayGetTypeID() else { return [] }
        return (v as? [AXUIElement]) ?? []
    }

    static func isSettable(_ el: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(el, name as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = raw(el, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = raw(el, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &point)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    @discardableResult
    static func setPosition(_ el: AXUIElement, _ point: CGPoint) -> Bool {
        var p = point
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) == .success
    }

    @discardableResult
    static func setSize(_ el: AXUIElement, _ size: CGSize) -> Bool {
        var s = size
        guard let v = AXValueCreate(.cgSize, &s) else { return false }
        return AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) == .success
    }

    /// size → position → size: the second resize fixes apps that clamp to the old monitor.
    static func setFrame(_ el: AXUIElement, _ rect: CGRect) {
        setSize(el, rect.size)
        setPosition(el, rect.origin)
        setSize(el, rect.size)
    }

    /// Some apps (Chrome, Electron...) animate AX frame changes when
    /// AXEnhancedUserInterface is on. Turn it off while we move windows.
    static func withoutEnhancedUI(pid: pid_t, _ body: () -> Void) {
        let app = AXUIElementCreateApplication(pid)
        let attr = "AXEnhancedUserInterface" as CFString
        let enabled = bool(app, "AXEnhancedUserInterface") ?? false
        if enabled { AXUIElementSetAttributeValue(app, attr, kCFBooleanFalse) }
        body()
        if enabled { AXUIElementSetAttributeValue(app, attr, kCFBooleanTrue) }
    }

    static func raise(_ el: AXUIElement) {
        AXUIElementPerformAction(el, kAXRaiseAction as CFString)
    }

    static func focus(_ el: AXUIElement, pid: pid_t) {
        AXUIElementSetAttributeValue(el, kAXMainAttribute as CFString, kCFBooleanTrue)
        raise(el)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let running = NSRunningApplication(processIdentifier: pid), !running.isActive {
            if #available(macOS 14.0, *) {
                running.activate(from: NSRunningApplication.current, options: [])
            } else {
                running.activate(options: [])
            }
        }
        raise(el)
    }

    static func close(_ el: AXUIElement) {
        if let button = element(el, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }
}
