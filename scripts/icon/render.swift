// Renders the PullView app icon. Usage: swift render.swift <outdir>
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Continuous-curvature squircle: superellipse corners (n = 5) blended into straight edges.
func squircle(_ r: CGRect, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let steps = 96
    // Curve spans 1.528r per side like Apple's continuous corner; n is solved so the 45 deg inset equals a radius-r arc (0.293r).
    let k = min(radius * 1.528, r.width / 2)
    let n = -log(2) / log(1 - 0.2929 * radius / k)
    let corners: [(CGPoint, CGFloat)] = [  // center of corner box, start angle
        (CGPoint(x: r.maxX - k, y: r.maxY - k), 0),
        (CGPoint(x: r.minX + k, y: r.maxY - k), .pi / 2),
        (CGPoint(x: r.minX + k, y: r.minY + k), .pi),
        (CGPoint(x: r.maxX - k, y: r.minY + k), 3 * .pi / 2),
    ]
    for (i, (c, a0)) in corners.enumerated() {
        for s in 0...steps {
            let t = a0 + CGFloat(s) / CGFloat(steps) * .pi / 2
            let ct = cos(t), st = sin(t)
            let x = c.x + k * copysign(pow(abs(ct), 2 / n), ct)
            let y = c.y + k * copysign(pow(abs(st), 2 / n), st)
            if i == 0 && s == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
    }
    p.closeSubpath()
    return p
}

func render() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = g.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))
    // Work in top-left coordinates.
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body, radius: 185)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Drop shadow inside the 100 px margin.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x0A0830, 0.45))
    ctx.addPath(shape); ctx.setFillColor(rgb(0x3A3BD0)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    // Base gradient: bright blue top-left to deep indigo bottom-right.
    let base = CGGradient(colorsSpace: space, colors: [rgb(0x3D8BFF), rgb(0x3355F0), rgb(0x3B2BB8), rgb(0x2A1680)] as CFArray,
                          locations: [0, 0.38, 0.75, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 330, y: 100), end: CGPoint(x: 694, y: 924), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Soft top glow for depth.
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 60), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 60), endRadius: 620, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // Bottom darkening to ground the body.
    let floor = CGGradient(colorsSpace: space, colors: [rgb(0x100840, 0), rgb(0x100840, 0.30)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(floor, start: CGPoint(x: 0, y: 600), end: CGPoint(x: 0, y: 924), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Glass rim: thin light edge strongest at the top.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.addPath(shape); ctx.setLineWidth(6); ctx.replacePathWithStrokedPath(); ctx.clip()
    let rim = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.55), rgb(0xFFFFFF, 0.08), rgb(0xFFFFFF, 0.18)] as CFArray,
                         locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(rim, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()

    // Pull-request motif. Left: base branch (two nodes, one line). Right: PR branch curving into a left arrow.
    let lw: CGFloat = 68, nr: CGFloat = 64  // stroke width, node ring radius (centerline)
    let lx: CGFloat = 352, rx: CGFloat = 672, top: CGFloat = 318, bot: CGFloat = 706
    let strokes = CGMutablePath()
    for c in [CGPoint(x: lx, y: top), CGPoint(x: lx, y: bot)] {
        strokes.addEllipse(in: CGRect(x: c.x - nr, y: c.y - nr, width: 2 * nr, height: 2 * nr))
    }
    strokes.move(to: CGPoint(x: lx, y: top + nr)); strokes.addLine(to: CGPoint(x: lx, y: bot - nr))
    let cr: CGFloat = 80
    strokes.move(to: CGPoint(x: rx, y: bot - nr))
    strokes.addLine(to: CGPoint(x: rx, y: top + cr))
    strokes.addArc(tangent1End: CGPoint(x: rx, y: top), tangent2End: CGPoint(x: rx - cr, y: top), radius: cr)
    strokes.addLine(to: CGPoint(x: 560, y: top))
    // Arrowhead pointing left, a triangle with rounded corners.
    let tipX: CGFloat = 476, baseX: CGFloat = 594, half: CGFloat = 90, rr: CGFloat = 14
    let v = [CGPoint(x: tipX, y: top), CGPoint(x: baseX, y: top - half), CGPoint(x: baseX, y: top + half)]
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: (v[0].x + v[2].x) / 2, y: (v[0].y + v[2].y) / 2))
    for i in 0..<3 { tri.addArc(tangent1End: v[i], tangent2End: v[(i + 1) % 3], radius: rr) }
    tri.closeSubpath()

    func paintMotif() {
        ctx.setStrokeColor(rgb(0xFFFFFF)); ctx.setFillColor(rgb(0xFFFFFF))
        ctx.setLineWidth(lw); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(strokes); ctx.strokePath()
        ctx.addPath(tri); ctx.fillPath()
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x120A50, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    paintMotif()
    // Faint cool shading, painted only where the white already is, so it reads as a solid object.
    ctx.setBlendMode(.sourceAtop)
    let ink = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF), rgb(0xE8EDFF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ink, start: CGPoint(x: 0, y: top - nr), end: CGPoint(x: 0, y: bot + nr),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Head-branch node in CI green: the passing-checks status PullView shows, and a color cue at 16 px.
    let head = CGPath(ellipseIn: CGRect(x: rx - nr, y: bot - nr, width: 2 * nr, height: 2 * nr), transform: nil)
        .copy(strokingWithWidth: lw, lineCap: .round, lineJoin: .round, miterLimit: 10)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 26, color: rgb(0x0F6B45, 0.55))
    ctx.addPath(head); ctx.setFillColor(rgb(0x3EE48F)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(head); ctx.clip()
    let green = CGGradient(colorsSpace: space, colors: [rgb(0x9CFFC4), rgb(0x3EE48F), rgb(0x1EBE6E)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(green, start: CGPoint(x: 0, y: bot - nr - lw / 2), end: CGPoint(x: 0, y: bot + nr + lw / 2), options: [])
    ctx.restoreGState()

    g.flushGraphics()
    return rep
}

// Halve repeatedly so each step averages 2x2 pixels; one big jump with .high still aliases thin strokes.
func downscale(_ src: NSBitmapImageRep, _ px: Int) -> NSBitmapImageRep {
    var cur = src
    while cur.pixelsWide / 2 > px { cur = resample(cur, cur.pixelsWide / 2) }
    return resample(cur, px)
}

func resample(_ src: NSBitmapImageRep, _ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    g.cgContext.interpolationQuality = .high
    g.cgContext.draw(src.cgImage!, in: CGRect(x: 0, y: 0, width: px, height: px))
    g.flushGraphics()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print(url.path)
}

let big = render()
write(big, "icon_1024.png")
write(downscale(big, 32), "icon_32.png")
write(downscale(big, 16), "icon_16.png")

// Self-check: canvas corner stays transparent, body center is opaque, sizes are right.
precondition(big.pixelsWide == 1024 && big.colorAt(x: 2, y: 2)!.alphaComponent == 0)
precondition(big.colorAt(x: 512, y: 512)!.alphaComponent == 1)
