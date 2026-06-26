import AppKit
import Foundation

// Renders the 1024px master app icon: an orange squircle with a crisp vector "spark"
// burst in white (drawn, not upscaled, so it stays sharp at every icon size).
// Usage: swiftc tools/genicon.swift -o genicon && ./genicon out.png

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    NSColor(srgbRed: 0.851, green: 0.467, blue: 0.341, alpha: 1).setFill() // #d97757
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 230, yRadius: 230).fill()

    let c = CGPoint(x: size / 2, y: size / 2)
    let rays = 12
    let lens: [CGFloat] = [1.0, 0.64, 0.94, 0.70, 1.0, 0.60, 0.96, 0.68, 1.0, 0.64, 0.92, 0.70] // uneven, spark-like
    let r0 = size * 0.02
    let outer = size * 0.34
    let baseWidth = size * 0.055
    NSColor.white.setStroke()
    for i in 0..<rays {
        let a = (CGFloat(i) / CGFloat(rays)) * 2 * .pi + .pi / 12
        let lf = lens[i % lens.count]
        let r1 = outer * lf
        let p = NSBezierPath()
        p.lineWidth = baseWidth * (0.7 + 0.3 * lf) // shorter rays a touch thinner
        p.lineCapStyle = .round
        p.move(to: CGPoint(x: c.x + cos(a) * r0, y: c.y + sin(a) * r0))
        p.line(to: CGPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
        p.stroke()
    }
    return true
}

guard CommandLine.arguments.count > 1,
      let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("genicon: render failed\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
