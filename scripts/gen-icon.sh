#!/usr/bin/env bash
# Generates the original FSearch macOS app icon asset catalog
# (App/Resources/Assets.xcassets/AppIcon.appiconset) from vector CoreGraphics/SwiftUI code.
# Zero third-party assets; deterministic across runs.
#
# Usage: scripts/gen-icon.sh [assets-dir]
# Prerequisites: macOS with Xcode / Swift command-line tools.
# Exit codes: 0 generated; non-zero on error.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ASSETS_DIR="${1:-$ROOT/App/Resources/Assets.xcassets}"

exec swift - "$ASSETS_DIR" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// Exact Apple macOS continuous squircle (`RoundedRectangle(style: .continuous)`).
/// Vertically symmetric, so SwiftUI's y-down `Path` maps identically into y-up `CGContext`.
func appleSquirclePath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect).cgPath
}

func makeGradient(_ colors: [(CGFloat, CGFloat, CGFloat, CGFloat)], locations: [CGFloat], space: CGColorSpace) -> CGGradient {
    let cgColors = colors.map { CGColor(colorSpace: space, components: [$0.0, $0.1, $0.2, $0.3])! } as CFArray
    return CGGradient(colorsSpace: space, colors: cgColors, locations: locations)!
}

/// Draws a miniature document badge (rounded page with a crisp folded top-right corner).
func drawDocumentBadge(in ctx: CGContext, rect: CGRect, fill: CGColor, foldColor: CGColor) {
    let fold = rect.width * 0.30
    let r = rect.width * 0.16
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

    let body = CGMutablePath()
    body.move(to: CGPoint(x: minX + r, y: maxY))
    body.addLine(to: CGPoint(x: maxX - fold, y: maxY))
    body.addLine(to: CGPoint(x: maxX, y: maxY - fold))
    body.addLine(to: CGPoint(x: maxX, y: minY + r))
    body.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX - r, y: minY), radius: r)
    body.addLine(to: CGPoint(x: minX + r, y: minY))
    body.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX, y: minY + r), radius: r)
    body.addLine(to: CGPoint(x: minX, y: maxY - r))
    body.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX + r, y: maxY), radius: r)
    body.closeSubpath()

    ctx.addPath(body)
    ctx.setFillColor(fill)
    ctx.fillPath()

    let dogEar = CGMutablePath()
    dogEar.move(to: CGPoint(x: maxX - fold, y: maxY))
    dogEar.addLine(to: CGPoint(x: maxX - fold, y: maxY - fold))
    dogEar.addLine(to: CGPoint(x: maxX, y: maxY - fold))
    dogEar.closeSubpath()
    ctx.addPath(dogEar)
    ctx.setFillColor(foldColor)
    ctx.fillPath()
}

/// Draws a miniature file row (badge + title bar) in canonical 1024-space.
func drawIndexRow(
    in ctx: CGContext,
    origin: CGPoint,
    barWidth: CGFloat,
    height: CGFloat,
    badgeColor: CGColor,
    barGradient: CGGradient?,
    barColor: CGColor?,
    documentFoldColor: CGColor? = nil,
    glowColor: CGColor? = nil,
    scale: CGFloat = 1.0
) {
    let badgeW = documentFoldColor != nil ? height * 0.86 : height
    let badgeRect = CGRect(x: origin.x, y: origin.y, width: badgeW, height: height)

    let gap = height * 0.36
    let barH = height * 0.62
    let barRect = CGRect(
        x: origin.x + badgeW + gap,
        y: origin.y + (height - barH) / 2.0,
        width: barWidth,
        height: barH
    )
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barH / 2.0, cornerHeight: barH / 2.0, transform: nil)

    ctx.saveGState()
    if let glowColor {
        ctx.setShadow(offset: .zero, blur: 18 * scale, color: glowColor)
    }
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    if let foldColor = documentFoldColor {
        drawDocumentBadge(in: ctx, rect: badgeRect, fill: badgeColor, foldColor: foldColor)
    } else {
        ctx.addPath(appleSquirclePath(in: badgeRect, cornerRadius: height * 0.28))
        ctx.setFillColor(badgeColor)
        ctx.fillPath()
    }

    ctx.saveGState()
    ctx.addPath(barPath)
    if let barGradient {
        ctx.clip()
        ctx.drawLinearGradient(
            barGradient,
            start: CGPoint(x: barRect.minX, y: barRect.midY),
            end: CGPoint(x: barRect.maxX, y: barRect.midY),
            options: []
        )
    } else if let barColor {
        ctx.setFillColor(barColor)
        ctx.fillPath()
    }
    ctx.restoreGState()

    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

/// Renders the FSearch macOS app icon at `pixelSize x pixelSize` (canonical coordinate space 1024x1024, y-up).
func renderIcon(pixelSize: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let scale = CGFloat(pixelSize) / 1024.0
    ctx.scaleBy(x: scale, y: scale)

    let isTiny = pixelSize <= 32
    let isSmall = pixelSize <= 64

    // Exact macOS HIG icon grid: 824x824 continuous squircle centered in 1024x1024 canvas (100px margin, r = 185.4).
    let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tile = appleSquirclePath(in: tileRect, cornerRadius: 185.4)

    // 1. Soft macOS ambient drop shadow behind tile.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -14 * scale),
        blur: 28 * scale,
        color: CGColor(colorSpace: space, components: [0.02, 0.04, 0.12, 0.34])!
    )
    ctx.addPath(tile)
    ctx.setFillColor(CGColor(colorSpace: space, components: [0.05, 0.12, 0.32, 1.0])!)
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clipped interior of the squircle tile.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()

    // Deep cobalt to midnight-navy gradient.
    let bgGrad = makeGradient(
        [
            (0.14, 0.45, 0.99, 1.0),
            (0.08, 0.25, 0.74, 1.0),
            (0.04, 0.10, 0.30, 1.0),
        ],
        locations: [0.0, 0.50, 1.0],
        space: space
    )
    ctx.drawLinearGradient(
        bgGrad,
        start: CGPoint(x: 380, y: 940),
        end: CGPoint(x: 640, y: 80),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Luminous cyan-blue radial glow behind the lens.
    let lensCenter = CGPoint(x: 472, y: 552)
    let auraGrad = makeGradient(
        [
            (0.24, 0.78, 1.00, 0.40),
            (0.12, 0.52, 0.98, 0.16),
            (0.05, 0.18, 0.56, 0.0),
        ],
        locations: [0.0, 0.46, 1.0],
        space: space
    )
    ctx.drawRadialGradient(
        auraGrad,
        startCenter: lensCenter,
        startRadius: 20,
        endCenter: lensCenter,
        endRadius: 430,
        options: []
    )

    // Soft vignette at bottom corners for sculptural depth.
    let vignetteGrad = makeGradient(
        [
            (0.01, 0.04, 0.14, 0.0),
            (0.01, 0.03, 0.12, 0.36),
        ],
        locations: [0.58, 1.0],
        space: space
    )
    ctx.drawRadialGradient(
        vignetteGrad,
        startCenter: CGPoint(x: 490, y: 560),
        startRadius: 140,
        endCenter: CGPoint(x: 512, y: 512),
        endRadius: 560,
        options: [.drawsAfterEndLocation]
    )

    // 3. Recessed frosted file-results card behind the lens (omitted at <= 32px for tiny crispness).
    let cardRect = CGRect(x: 178, y: 244, width: 584, height: 540)
    if !isTiny {
        let cardPath = appleSquirclePath(in: cardRect, cornerRadius: 84)

        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10 * scale),
            blur: 24 * scale,
            color: CGColor(colorSpace: space, components: [0.01, 0.03, 0.12, 0.28])!
        )
        ctx.addPath(cardPath)
        ctx.setFillColor(CGColor(colorSpace: space, components: [0.07, 0.17, 0.48, 0.48])!)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.clip()
        let cardGrad = makeGradient(
            [
                (0.32, 0.62, 1.00, 0.22),
                (0.10, 0.26, 0.66, 0.24),
                (0.04, 0.11, 0.34, 0.36),
            ],
            locations: [0.0, 0.50, 1.0],
            space: space
        )
        ctx.drawLinearGradient(
            cardGrad,
            start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
            options: []
        )
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(cardPath)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.68, 0.86, 1.0, 0.22])!)
        ctx.setLineWidth(isSmall ? 6.0 : 3.0)
        ctx.strokePath()
        ctx.restoreGState()

        let subtleBadge = CGColor(colorSpace: space, components: [0.65, 0.84, 1.0, 0.24])!
        let subtleBar = CGColor(colorSpace: space, components: [0.76, 0.90, 1.0, 0.18])!
        let activeBadge = CGColor(colorSpace: space, components: [0.36, 0.90, 1.0, 0.46])!
        let activeBar = CGColor(colorSpace: space, components: [0.58, 0.92, 1.0, 0.28])!

        drawIndexRow(in: ctx, origin: CGPoint(x: 240, y: 664), barWidth: 278, height: 42, badgeColor: subtleBadge, barGradient: nil, barColor: subtleBar)
        drawIndexRow(in: ctx, origin: CGPoint(x: 240, y: 544), barWidth: 382, height: 44, badgeColor: activeBadge, barGradient: nil, barColor: activeBar)
        drawIndexRow(in: ctx, origin: CGPoint(x: 240, y: 424), barWidth: 320, height: 42, badgeColor: subtleBadge, barGradient: nil, barColor: subtleBar)
        drawIndexRow(in: ctx, origin: CGPoint(x: 240, y: 312), barWidth: 226, height: 40, badgeColor: subtleBadge, barGradient: nil, barColor: subtleBar)
    }

    // 4. Hero Precision Magnifying Glass.
    let outerRadius: CGFloat = isTiny ? 214 : 200
    let ringWidth: CGFloat = isTiny ? 60 : (isSmall ? 50 : 44)
    let innerRadius = outerRadius - ringWidth

    let angle: CGFloat = -.pi / 4.0
    let dir = CGPoint(x: cos(angle), y: sin(angle))
    let perp = CGPoint(x: -dir.y, y: dir.x)

    let neckStart = CGPoint(x: lensCenter.x + dir.x * (outerRadius - 10), y: lensCenter.y + dir.y * (outerRadius - 10))
    let neckEnd = CGPoint(x: lensCenter.x + dir.x * (outerRadius + 42), y: lensCenter.y + dir.y * (outerRadius + 42))
    let gripStart = CGPoint(x: lensCenter.x + dir.x * (outerRadius + 56), y: lensCenter.y + dir.y * (outerRadius + 56))
    let gripEnd = CGPoint(x: lensCenter.x + dir.x * (outerRadius + 206), y: lensCenter.y + dir.y * (outerRadius + 206))
    let neckWidth: CGFloat = isTiny ? 44 : 38
    let gripWidth: CGFloat = isTiny ? 72 : (isSmall ? 66 : 62)

    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -22 * scale),
        blur: 38 * scale,
        color: CGColor(colorSpace: space, components: [0.01, 0.03, 0.14, 0.56])!
    )
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    // Narrow metallic neck.
    ctx.saveGState()
    ctx.setLineCap(.butt)
    ctx.setLineWidth(neckWidth)
    ctx.move(to: neckStart)
    ctx.addLine(to: neckEnd)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let neckGrad = makeGradient(
        [
            (0.86, 0.92, 1.00, 1.0),
            (0.58, 0.72, 0.94, 1.0),
        ],
        locations: [0.0, 1.0],
        space: space
    )
    ctx.drawLinearGradient(
        neckGrad,
        start: CGPoint(x: neckStart.x + perp.x * 24, y: neckStart.y + perp.y * 24),
        end: CGPoint(x: neckStart.x - perp.x * 24, y: neckStart.y - perp.y * 24),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // Sculpted cylindrical handle grip.
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setLineWidth(gripWidth)
    ctx.move(to: gripStart)
    ctx.addLine(to: gripEnd)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let handleGrad = makeGradient(
        [
            (1.00, 1.00, 1.00, 1.0),
            (0.86, 0.92, 1.00, 1.0),
            (0.64, 0.78, 0.97, 1.0),
        ],
        locations: [0.0, 0.48, 1.0],
        space: space
    )
    ctx.drawLinearGradient(
        handleGrad,
        start: CGPoint(x: gripStart.x + perp.x * (gripWidth * 0.55), y: gripStart.y + perp.y * (gripWidth * 0.55)),
        end: CGPoint(x: gripStart.x - perp.x * (gripWidth * 0.55), y: gripStart.y - perp.y * (gripWidth * 0.55)),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    if !isTiny {
        let hiStart = CGPoint(x: gripStart.x + perp.x * (gripWidth * 0.24), y: gripStart.y + perp.y * (gripWidth * 0.24))
        let hiEnd = CGPoint(x: gripEnd.x + perp.x * (gripWidth * 0.24), y: gripEnd.y + perp.y * (gripWidth * 0.24))
        ctx.setLineCap(.round)
        ctx.setLineWidth(9)
        ctx.move(to: hiStart)
        ctx.addLine(to: hiEnd)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [1.0, 1.0, 1.0, 0.60])!)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Optical glass lens interior.
    let lensInnerRect = CGRect(
        x: lensCenter.x - innerRadius - 2,
        y: lensCenter.y - innerRadius - 2,
        width: (innerRadius + 2) * 2,
        height: (innerRadius + 2) * 2
    )
    ctx.saveGState()
    ctx.addEllipse(in: lensInnerRect)
    ctx.clip()

    let glassGrad = makeGradient(
        [
            (0.24, 0.78, 1.00, 0.46),
            (0.10, 0.36, 0.88, 0.64),
            (0.04, 0.14, 0.46, 0.80),
        ],
        locations: [0.0, 0.52, 1.0],
        space: space
    )
    ctx.drawLinearGradient(
        glassGrad,
        start: CGPoint(x: lensCenter.x - innerRadius, y: lensCenter.y + innerRadius),
        end: CGPoint(x: lensCenter.x + innerRadius, y: lensCenter.y - innerRadius),
        options: []
    )

    if isTiny {
        let dotGrad = makeGradient(
            [
                (0.65, 0.96, 1.00, 0.92),
                (0.28, 0.80, 1.00, 0.25),
                (0.16, 0.52, 1.00, 0.0),
            ],
            locations: [0.0, 0.55, 1.0],
            space: space
        )
        ctx.drawRadialGradient(
            dotGrad,
            startCenter: CGPoint(x: lensCenter.x - 36, y: lensCenter.y + 42),
            startRadius: 4,
            endCenter: CGPoint(x: lensCenter.x - 16, y: lensCenter.y + 20),
            endRadius: innerRadius * 0.95,
            options: []
        )
    } else {
        ctx.saveGState()
        let mag: CGFloat = 1.22
        ctx.translateBy(x: lensCenter.x, y: lensCenter.y)
        ctx.scaleBy(x: mag, y: mag)
        ctx.translateBy(x: -lensCenter.x, y: -lensCenter.y)

        let magGhostBadge = CGColor(colorSpace: space, components: [0.76, 0.92, 1.0, 0.30])!
        let magGhostBar = CGColor(colorSpace: space, components: [0.84, 0.94, 1.0, 0.22])!
        drawIndexRow(in: ctx, origin: CGPoint(x: 374, y: 612), barWidth: 146, height: 32, badgeColor: magGhostBadge, barGradient: nil, barColor: magGhostBar)
        drawIndexRow(in: ctx, origin: CGPoint(x: 374, y: 458), barWidth: 118, height: 32, badgeColor: magGhostBadge, barGradient: nil, barColor: magGhostBar)

        let heroBadge = CGColor(colorSpace: space, components: [0.24, 0.92, 1.00, 1.0])!
        let heroFold = CGColor(colorSpace: space, components: [0.80, 0.98, 1.00, 0.95])!
        let heroBarGrad = makeGradient(
            [
                (0.96, 0.99, 1.00, 1.0),
                (0.70, 0.94, 1.00, 0.96),
            ],
            locations: [0.0, 1.0],
            space: space
        )
        let heroGlow = CGColor(colorSpace: space, components: [0.24, 0.90, 1.0, 0.85])!
        drawIndexRow(
            in: ctx,
            origin: CGPoint(x: 370, y: 526),
            barWidth: 148,
            height: 52,
            badgeColor: heroBadge,
            barGradient: heroBarGrad,
            barColor: nil,
            documentFoldColor: isSmall ? nil : heroFold,
            glowColor: heroGlow,
            scale: scale
        )
        ctx.restoreGState()

        ctx.saveGState()
        let sheenRect = CGRect(
            x: lensCenter.x - innerRadius * 1.15,
            y: lensCenter.y + innerRadius * 0.14,
            width: innerRadius * 2.05,
            height: innerRadius * 1.25
        )
        ctx.addEllipse(in: sheenRect)
        ctx.clip()
        let sheenGrad = makeGradient(
            [
                (1.0, 1.0, 1.0, 0.34),
                (1.0, 1.0, 1.0, 0.0),
            ],
            locations: [0.0, 1.0],
            space: space
        )
        ctx.drawLinearGradient(
            sheenGrad,
            start: CGPoint(x: lensCenter.x - 55, y: lensCenter.y + innerRadius),
            end: CGPoint(x: lensCenter.x + 25, y: lensCenter.y + 18),
            options: []
        )
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addArc(
            center: lensCenter,
            radius: innerRadius - 8,
            startAngle: -.pi * 0.42,
            endAngle: .pi * 0.02,
            clockwise: false
        )
        ctx.setLineCap(.round)
        ctx.setLineWidth(7)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.45, 0.92, 1.0, 0.38])!)
        ctx.strokePath()
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Lens outer metallic ring.
    let ringPath = CGMutablePath()
    ringPath.addEllipse(
        in: CGRect(
            x: lensCenter.x - outerRadius,
            y: lensCenter.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
    ringPath.addEllipse(
        in: CGRect(
            x: lensCenter.x - innerRadius,
            y: lensCenter.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        ))
    ctx.saveGState()
    ctx.addPath(ringPath)
    ctx.clip(using: .evenOdd)
    let ringGrad = makeGradient(
        [
            (1.00, 1.00, 1.00, 1.0),
            (0.92, 0.96, 1.00, 1.0),
            (0.72, 0.84, 0.98, 1.0),
        ],
        locations: [0.0, 0.52, 1.0],
        space: space
    )
    ctx.drawLinearGradient(
        ringGrad,
        start: CGPoint(x: lensCenter.x - outerRadius, y: lensCenter.y + outerRadius),
        end: CGPoint(x: lensCenter.x + outerRadius, y: lensCenter.y - outerRadius),
        options: []
    )
    ctx.restoreGState()

    if !isTiny {
        ctx.saveGState()
        ctx.addEllipse(
            in: CGRect(
                x: lensCenter.x - innerRadius,
                y: lensCenter.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            ))
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.05, 0.14, 0.42, 0.38])!)
        ctx.setLineWidth(3.0)
        ctx.strokePath()
        ctx.restoreGState()
    }

    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 5. Crisp top-lit inner rim highlight around continuous squircle.
    if !isTiny {
        ctx.saveGState()
        ctx.addPath(tile)
        ctx.setLineWidth(isSmall ? 8.0 : 4.5)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let rimGrad = makeGradient(
            [
                (1.0, 1.0, 1.0, 0.36),
                (0.72, 0.88, 1.0, 0.12),
                (0.30, 0.60, 1.0, 0.04),
            ],
            locations: [0.0, 0.45, 1.0],
            space: space
        )
        ctx.drawLinearGradient(
            rimGrad,
            start: CGPoint(x: 512, y: 924),
            end: CGPoint(x: 512, y: 100),
            options: []
        )
        ctx.restoreGState()
    }

    ctx.restoreGState()

    return ctx.makeImage()!
}

func pngData(for image: CGImage) throws -> Data {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "gen-icon", code: 1)
    }
    return data
}

let assetsDir = URL(fileURLWithPath: CommandLine.arguments[1])
let appIconDir = assetsDir.appendingPathComponent("AppIcon.appiconset")
let fm = FileManager.default
try fm.createDirectory(at: appIconDir, withIntermediateDirectories: true)

let rootContents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try (rootContents + "\n").write(to: assetsDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let slots: [(size: String, scale: String, pixels: Int, filename: String)] = [
    ("16x16", "1x", 16, "icon_16x16.png"),
    ("16x16", "2x", 32, "icon_16x16@2x.png"),
    ("32x32", "1x", 32, "icon_32x32.png"),
    ("32x32", "2x", 64, "icon_32x32@2x.png"),
    ("128x128", "1x", 128, "icon_128x128.png"),
    ("128x128", "2x", 256, "icon_128x128@2x.png"),
    ("256x256", "1x", 256, "icon_256x256.png"),
    ("256x256", "2x", 512, "icon_256x256@2x.png"),
    ("512x512", "1x", 512, "icon_512x512.png"),
    ("512x512", "2x", 1024, "icon_512x512@2x.png"),
]

var cache: [Int: Data] = [:]
for slot in slots {
    let data: Data
    if let existing = cache[slot.pixels] {
        data = existing
    } else {
        data = try pngData(for: renderIcon(pixelSize: slot.pixels))
        cache[slot.pixels] = data
    }
    try data.write(to: appIconDir.appendingPathComponent(slot.filename))
}

let imageEntries = slots.map { slot in
    """
        {
          "filename" : "\(slot.filename)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)",
          "size" : "\(slot.size)"
        }
    """
}.joined(separator: ",\n")

let iconContents = """
{
  "images" : [
\(imageEntries)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try (iconContents + "\n").write(to: appIconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("generated \(slots.count) macOS AppIcon assets in \(appIconDir.path)")
SWIFT
