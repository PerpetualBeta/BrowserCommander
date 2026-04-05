#!/usr/bin/env swift

import AppKit
import CoreGraphics

// Brand colour
let brandBlue = NSColor(red: 0x00/255.0, green: 0x40/255.0, blue: 0x80/255.0, alpha: 1.0)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let cx = s / 2
    let cy = s / 2

    // Background — rounded rect with brand colour
    let bgRect = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.18, yRadius: s * 0.18)
    brandBlue.setFill()
    bgPath.fill()

    // Subtle radial gradient for depth
    let gradSpace = CGColorSpaceCreateDeviceRGB()
    let gradColors = [
        NSColor(white: 1.0, alpha: 0.08).cgColor,
        NSColor(white: 0.0, alpha: 0.10).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: gradSpace, colors: gradColors, locations: [0.0, 1.0]) {
        ctx.saveGState()
        ctx.addPath(bgPath.cgPath)
        ctx.clip()
        ctx.drawRadialGradient(gradient,
            startCenter: CGPoint(x: cx, y: cy + s * 0.12),
            startRadius: 0,
            endCenter: CGPoint(x: cx, y: cy),
            endRadius: s * 0.55,
            options: [])
        ctx.restoreGState()
    }

    // ── Globe ──
    ctx.saveGState()
    ctx.addPath(bgPath.cgPath)
    ctx.clip()

    let globeR = s * 0.34
    let globeCY = cy

    // Outer glow
    let glowColors = [
        NSColor(white: 1.0, alpha: 0.06).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor,
    ] as CFArray
    if let glow = CGGradient(colorsSpace: gradSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glow,
            startCenter: CGPoint(x: cx, y: globeCY),
            startRadius: globeR * 0.9,
            endCenter: CGPoint(x: cx, y: globeCY),
            endRadius: globeR * 1.35,
            options: [])
    }

    let lineColor = NSColor(white: 1.0, alpha: 0.7)
    let thinColor = NSColor(white: 1.0, alpha: 0.35)
    let thickW = s * 0.01
    let thinW = s * 0.006

    // Outer circle — bold
    ctx.setStrokeColor(lineColor.cgColor)
    ctx.setLineWidth(thickW)
    ctx.strokeEllipse(in: CGRect(x: cx - globeR, y: globeCY - globeR,
                                  width: globeR * 2, height: globeR * 2))

    // Meridians (vertical ellipses)
    ctx.setStrokeColor(thinColor.cgColor)
    ctx.setLineWidth(thinW)
    for i in 1...3 {
        let frac = CGFloat(i) / 4.0
        let eW = globeR * frac
        ctx.strokeEllipse(in: CGRect(x: cx - eW, y: globeCY - globeR,
                                      width: eW * 2, height: globeR * 2))
    }

    // Parallels (horizontal curved lines)
    for i in 1...3 {
        let frac = CGFloat(i) / 4.0
        let y1 = globeCY + globeR * frac
        let y2 = globeCY - globeR * frac
        let halfW = sqrt(max(0, globeR * globeR - (globeR * frac) * (globeR * frac)))

        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx - halfW, y: y1))
        ctx.addQuadCurve(to: CGPoint(x: cx + halfW, y: y1),
                         control: CGPoint(x: cx, y: y1 + s * 0.006))
        ctx.strokePath()

        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx - halfW, y: y2))
        ctx.addQuadCurve(to: CGPoint(x: cx + halfW, y: y2),
                         control: CGPoint(x: cx, y: y2 - s * 0.006))
        ctx.strokePath()
    }

    // Equator — slightly bolder
    ctx.setStrokeColor(lineColor.withAlphaComponent(0.5).cgColor)
    ctx.setLineWidth(thinW * 1.2)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx - globeR, y: globeCY))
    ctx.addLine(to: CGPoint(x: cx + globeR, y: globeCY))
    ctx.strokePath()

    // Prime meridian (vertical centre) — slightly bolder
    ctx.beginPath()
    ctx.move(to: CGPoint(x: cx, y: globeCY - globeR))
    ctx.addLine(to: CGPoint(x: cx, y: globeCY + globeR))
    ctx.strokePath()

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// NSBezierPath -> CGPath
extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        let points = UnsafeMutablePointer<NSPoint>.allocate(capacity: 3)
        defer { points.deallocate() }
        for i in 0..<elementCount {
            let element = self.element(at: i, associatedPoints: points)
            switch element {
            case .moveTo:    path.move(to: points[0])
            case .lineTo:    path.addLine(to: points[0])
            case .curveTo:   path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

// Generate all icon sizes
let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

let scriptDir = CommandLine.arguments[0].components(separatedBy: "/").dropLast().joined(separator: "/")
let iconsetDir = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/BrowserMCP.iconset"

let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { continue }
    let path = iconsetDir + "/" + name
    try! png.write(to: URL(fileURLWithPath: path))
    print("  \(name) (\(size)x\(size))")
}

// Generate .icns
let icnsPath = (scriptDir.isEmpty ? "." : scriptDir) + "/Resources/AppIcon.icns"
let result = Process()
result.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
result.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try! result.run()
result.waitUntilExit()
print("  AppIcon.icns")
print("Done.")
