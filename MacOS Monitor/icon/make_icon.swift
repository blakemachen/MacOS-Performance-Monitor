import AppKit

// Renders a 1024×1024 PNG app icon: a rounded-rect with the app's dark gradient,
// a green→red performance gauge ring, and a live "pulse" line through the center.
// Usage: swift make_icon.swift <output.png>

let size = 1024
let S = CGFloat(size)

func heat(_ t: CGFloat) -> NSColor {
    let hue = 0.33 * (1 - max(0, min(1, t)))   // green (0.33) → red (0.0)
    return NSColor(hue: hue, saturation: 0.9, brightness: 0.97, alpha: 1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("rep") }

NSGraphicsContext.saveGraphicsState()
let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = nsctx
let cg = nsctx.cgContext

cg.clear(CGRect(x: 0, y: 0, width: S, height: S))

// Rounded-rect body.
let inset: CGFloat = 84
let body = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius = body.width * 0.2237
let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Drop shadow + base.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -16), blur: 36,
             color: NSColor.black.withAlphaComponent(0.45).cgColor)
cg.addPath(bodyPath)
cg.setFillColor(NSColor(srgbRed: 0.09, green: 0.11, blue: 0.17, alpha: 1).cgColor)
cg.fillPath()
cg.restoreGState()

// Gradient fill, clipped to the body.
cg.saveGState()
cg.addPath(bodyPath)
cg.clip()
let grad = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [NSColor(srgbRed: 0.10, green: 0.12, blue: 0.19, alpha: 1).cgColor,
             NSColor(srgbRed: 0.15, green: 0.18, blue: 0.30, alpha: 1).cgColor] as CFArray,
    locations: [0, 1])!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
// Subtle top highlight, faded smoothly to avoid a hard seam.
let hi = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [NSColor.white.withAlphaComponent(0.07).cgColor,
             NSColor.white.withAlphaComponent(0).cgColor] as CFArray,
    locations: [0, 1])!
cg.drawLinearGradient(hi, start: CGPoint(x: 0, y: body.maxY),
                      end: CGPoint(x: 0, y: body.midY - body.height * 0.1), options: [])
cg.restoreGState()

// Gauge ring.
let center = CGPoint(x: S / 2, y: S / 2)
let ringRadius: CGFloat = 252
let lineWidth: CGFloat = 66
let a0 = CGFloat(235 * Double.pi / 180)   // lower-left
let a1 = CGFloat(-55 * Double.pi / 180)   // lower-right (clockwise through top)

// Faint track.
cg.setLineCap(.round)
cg.setLineWidth(lineWidth)
cg.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
cg.beginPath()
cg.addArc(center: center, radius: ringRadius, startAngle: a0, endAngle: a1, clockwise: true)
cg.strokePath()

// Heat-gradient arc, drawn as overlapping segments.
let segments = 120
for i in 0..<segments {
    let t0 = CGFloat(i) / CGFloat(segments)
    let t1 = CGFloat(i + 1) / CGFloat(segments)
    let ang0 = a0 + (a1 - a0) * t0
    let ang1 = a0 + (a1 - a0) * t1
    cg.setStrokeColor(heat(t0).cgColor)
    cg.setLineWidth(lineWidth)
    cg.setLineCap(.round)
    cg.beginPath()
    cg.addArc(center: center, radius: ringRadius, startAngle: ang0, endAngle: ang1, clockwise: true)
    cg.strokePath()
}

// Live pulse line through the center (ECG-style).
let baseX = center.x - 185
let span: CGFloat = 370
let amp: CGFloat = 130
let pts: [(CGFloat, CGFloat)] = [
    (0.00, 0.00), (0.26, 0.00), (0.37, 0.22), (0.46, 0.95),
    (0.55, -0.85), (0.64, 0.30), (0.74, 0.00), (1.00, 0.00),
]
let path = CGMutablePath()
for (idx, p) in pts.enumerated() {
    let pt = CGPoint(x: baseX + p.0 * span, y: center.y + p.1 * amp)
    if idx == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
}

// Soft glow, then crisp stroke.
cg.setLineJoin(.round)
cg.setLineCap(.round)
cg.addPath(path)
cg.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
cg.setLineWidth(44)
cg.strokePath()
cg.addPath(path)
cg.setStrokeColor(NSColor.white.cgColor)
cg.setLineWidth(22)
cg.strokePath()

nsctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
try! data.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
