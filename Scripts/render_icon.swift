// Draws the Penumbra app icon: a partial solar eclipse against a mauve sky, with the soft
// half-shadow the app is named after along the moon's edge. Uses only CoreGraphics, so it runs
// with the Command Line Tools.
//
//   swift Scripts/render_icon.swift <output.icns>
//
// The artwork fills the whole square. macOS 26 cuts it to the system icon shape, adds the glass
// edge, and shrinks it to the standard icon size, so the eclipse is drawn larger to make up for it.
//
// The .icns has no 16 or 32 pixel images, because macOS puts any it finds on a grey tile instead of
// shaping them. It scales the 64 pixel image down instead, which is drawn with a bolder crescent so
// the eclipse still reads at 16 pixels.

import CoreGraphics
import Foundation
import ImageIO

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

enum Colors {
    static let skyTop = rgb(0.55, 0.37, 0.62)
    static let skyBottom = rgb(0.19, 0.14, 0.36)
    static let sunCore = rgb(1.00, 1.00, 1.00)
    static let sunEdge = rgb(1.00, 0.98, 0.94)
    static let halo = rgb(1.00, 0.95, 0.86)
    static let moon = rgb(0.04, 0.03, 0.09)
}

/// macOS shows a full-bleed icon at 824 of 1024 points.
let systemScale: CGFloat = 1024 / 824

func radialGradient(_ context: CGContext, center: CGPoint, colors: [CGColor], locations: [CGFloat], radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: locations)!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}

func drawIcon(in context: CGContext, pixels: Int) {
    // The 64 pixel image is also the source for 32 and 16 pixels, so it gets the bolder drawing.
    let simple = pixels <= 64
    context.saveGState()
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                         colors: [Colors.skyTop, Colors.skyBottom] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Lay the eclipse out on the visible 824-point icon, then scale it up around the centre.
    context.translateBy(x: 512, y: 512)
    context.scaleBy(x: systemScale, y: systemScale)
    context.translateBy(x: -512, y: -512)

    // The moon sits up and to the right, leaving a crescent of sun at the lower left.
    let sunCenter = CGPoint(x: 492, y: 492)
    let sunRadius: CGFloat = simple ? 250 : 222
    let moonOffset = simple ? CGSize(width: 70, height: 58) : CGSize(width: 52, height: 42)
    let moonCenter = CGPoint(x: sunCenter.x + moonOffset.width, y: sunCenter.y + moonOffset.height)
    let moonRadius = sunRadius * 0.97

    // A faint halo, fading out gradually.
    radialGradient(context, center: sunCenter,
                   colors: [Colors.halo.copy(alpha: simple ? 0.30 : 0.26)!, Colors.halo.copy(alpha: 0.08)!, Colors.halo.copy(alpha: 0)!],
                   locations: [0.58, 0.74, 1], radius: simple ? 360 : 390)

    // Sun.
    context.saveGState()
    context.addEllipse(in: circle(sunCenter, sunRadius))
    context.clip()
    radialGradient(context, center: sunCenter, colors: [Colors.sunCore, Colors.sunCore, Colors.sunEdge],
                   locations: [0, 0.7, 1], radius: sunRadius)
    context.restoreGState()

    // Moon. A light shadow softens its edge against the sun: the penumbra.
    context.saveGState()
    if !simple {
        context.setShadow(offset: .zero, blur: 20, color: rgb(0, 0, 0, 0.45))
    }
    context.addEllipse(in: circle(moonCenter, moonRadius))
    context.setFillColor(Colors.moon)
    context.fillPath()
    context.restoreGState()

    context.restoreGState()
}

func render(pixels: Int) -> CGImage {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawIcon(in: context, pixels: pixels)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift Scripts/render_icon.swift <output.icns>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

try writePNG(render(pixels: 64), to: iconset.appending(path: "icon_32x32@2x.png"))
for points in [128, 256, 512] {
    try writePNG(render(pixels: points), to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try writePNG(render(pixels: points * 2), to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(1) }
