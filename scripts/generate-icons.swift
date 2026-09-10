#!/usr/bin/env swift
//
//  Generates all macOS AppIcon sizes for Quetta.
//  Usage: swift scripts/generate-icons.swift <output-dir>
//  Default output: quetta/Assets.xcassets/AppIcon.appiconset
//

import AppKit

func makeIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus(); return image
    }

    // ── Rounded background ───────────────────────────────────────────────
    let corner = s * 0.225
    let bgPath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: corner, cornerHeight: corner,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let cs = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.08, green: 0.05, blue: 0.30, alpha: 1.0),   // deep navy
            CGColor(red: 0.42, green: 0.08, blue: 0.60, alpha: 1.0)    // deep violet
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0,  y: s),
        end:   CGPoint(x: s,  y: 0),
        options: []
    )
    ctx.restoreGState()

    // ── Waveform bars ────────────────────────────────────────────────────
    let nBars   = 7
    let hPad    = s * 0.20
    let gap     = s * 0.038
    let totalW  = s - hPad * 2
    let bw      = (totalW - gap * CGFloat(nBars - 1)) / CGFloat(nBars)
    let maxH    = s * 0.60
    let cy      = s / 2
    let ratios: [CGFloat] = [0.35, 0.60, 0.82, 1.00, 0.82, 0.60, 0.35]

    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.93))
    for i in 0 ..< nBars {
        let h  = ratios[i] * maxH
        let x  = hPad + CGFloat(i) * (bw + gap)
        let r  = min(bw / 2, s * 0.045)
        let p  = CGPath(
            roundedRect: CGRect(x: x, y: cy - h / 2, width: bw, height: h),
            cornerWidth: r, cornerHeight: r,
            transform: nil
        )
        ctx.addPath(p)
        ctx.fillPath()
    }

    image.unlockFocus()
    return image
}

// ── Output path ───────────────────────────────────────────────────────────
let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "quetta/Assets.xcassets/AppIcon.appiconset"

let specs: [(sz: Int, sc: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2)
]

for (sz, sc) in specs {
    let px   = sz * sc
    let img  = makeIcon(size: px)
    let name = sc == 1 ? "icon_\(sz)x\(sz).png" : "icon_\(sz)x\(sz)@\(sc)x.png"
    let url  = URL(fileURLWithPath: outDir).appendingPathComponent(name)

    guard let tiff = img.tiffRepresentation,
          let bmp  = NSBitmapImageRep(data: tiff),
          let png  = bmp.representation(using: .png, properties: [:])
    else { print("FAIL: \(name)"); continue }

    do {
        try png.write(to: url)
        print("✓  \(name)  (\(px)×\(px) px)")
    } catch {
        print("FAIL \(name): \(error)")
    }
}
print("Done.")
