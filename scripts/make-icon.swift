// Renders the HyprMac app icon (1024×1024 PNG).
// usage: swift scripts/make-icon.swift OUTPUT.png
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Flip so y grows downward (easier to reason about window layouts).
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// macOS icon grid: 824pt body centred in a 1024 canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow + background gradient.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(color(0x0F172A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [color(0x1E1B4B), color(0x0F172A), color(0x082F49)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])
// Soft glow behind the active window.
let glow = CGGradient(colorsSpace: space, colors: [color(0x22D3EE, 0.35), color(0x22D3EE, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 360, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 360, y: 470), endRadius: 420, options: [])
ctx.restoreGState()

// Dwindle layout: big left window, top right, and the bottom right split again.
let area = body.insetBy(dx: 92, dy: 92)
let gap: CGFloat = 26
let leftW = (area.width - gap) * 0.55
let left = CGRect(x: area.minX, y: area.minY, width: leftW, height: area.height)
let rightX = left.maxX + gap
let rightW = area.maxX - rightX
let topH = (area.height - gap) * 0.5
let topRight = CGRect(x: rightX, y: area.minY, width: rightW, height: topH)
let bottomY = topRight.maxY + gap
let bottomH = area.maxY - bottomY
let halfW = (rightW - gap) / 2
let bottomLeft = CGRect(x: rightX, y: bottomY, width: halfW, height: bottomH)
let bottomRight = CGRect(x: rightX + halfW + gap, y: bottomY, width: halfW, height: bottomH)

func window(_ r: CGRect, fill: CGColor, titleBar: CGColor) {
    let radius: CGFloat = 34
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
    ctx.addPath(path)
    ctx.clip()
    ctx.setFillColor(titleBar)
    ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: min(56, r.height * 0.22)))
    ctx.restoreGState()
}

// Inactive windows.
window(topRight, fill: color(0xFFFFFF, 0.13), titleBar: color(0xFFFFFF, 0.10))
window(bottomLeft, fill: color(0xFFFFFF, 0.10), titleBar: color(0xFFFFFF, 0.08))
window(bottomRight, fill: color(0xFFFFFF, 0.10), titleBar: color(0xFFFFFF, 0.08))

// Active window with a Hyprland-style gradient border.
window(left, fill: color(0xFFFFFF, 0.20), titleBar: color(0xFFFFFF, 0.14))
let border: CGFloat = 16
let outer = left.insetBy(dx: -border / 2, dy: -border / 2)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: outer, cornerWidth: 34 + border / 2, cornerHeight: 34 + border / 2, transform: nil))
ctx.setLineWidth(border)
ctx.replacePathWithStrokedPath()
ctx.clip()
let accent = CGGradient(colorsSpace: space, colors: [color(0x22D3EE), color(0x818CF8), color(0xE879F9)] as CFArray,
                        locations: [0, 0.5, 1])!
ctx.drawLinearGradient(accent, start: CGPoint(x: outer.minX, y: outer.minY), end: CGPoint(x: outer.maxX, y: outer.maxY), options: [])
ctx.restoreGState()

// Traffic lights on the active window.
for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
    let d: CGFloat = 24
    ctx.setFillColor(color(hex))
    ctx.fillEllipse(in: CGRect(x: left.minX + 30 + CGFloat(i) * 38, y: left.minY + 16, width: d, height: d))
}

// Subtle inner highlight on the icon body.
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
ctx.setStrokeColor(color(0xFFFFFF, 0.12))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
