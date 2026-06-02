import AppKit

let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0], relativeTo: currentDirectoryURL).standardized
let rootURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resourcesURL = rootURL.appendingPathComponent("Resources")
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset")
let iconURL = resourcesURL.appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(name: String, points: CGFloat, scale: CGFloat)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 16, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 32, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 128, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 256, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 512, 2)
]

for size in sizes {
    let pixels = Int(size.points * size.scale)
    let image = makeIcon(size: CGFloat(pixels))
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIcon", code: 1)
    }

    try png.write(to: iconsetURL.appendingPathComponent(size.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", iconURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "AppIcon", code: Int(process.terminationStatus))
}

try FileManager.default.removeItem(at: iconsetURL)

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let body = rect.insetBy(dx: size * 0.12, dy: size * 0.12)
    let bodyPath = NSBezierPath(rect: body)
    NSColor(red: 0.02, green: 0.27, blue: 0.38, alpha: 0.94).setFill()
    bodyPath.fill()

    if let gradient = NSGradient(colors: [
        NSColor(red: 0.34, green: 0.82, blue: 0.98, alpha: 0.86),
        NSColor(red: 0.0, green: 0.43, blue: 0.72, alpha: 0.78),
        NSColor(red: 0.03, green: 0.10, blue: 0.16, alpha: 0.92)
    ]) {
        gradient.draw(in: body, angle: -35)
    }

    NSColor.white.withAlphaComponent(0.18).setStroke()
    bodyPath.lineWidth = max(1, size * 0.018)
    bodyPath.stroke()

    let header = NSRect(x: body.minX, y: body.maxY - size * 0.24, width: body.width, height: size * 0.18)
    NSColor.white.withAlphaComponent(0.18).setFill()
    header.fill()

    NSColor.white.withAlphaComponent(0.86).setStroke()
    for x in stride(from: body.minX + size * 0.20, through: body.maxX - size * 0.20, by: size * 0.20) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: body.minY + size * 0.22))
        path.line(to: NSPoint(x: x, y: body.maxY - size * 0.32))
        path.lineWidth = max(1, size * 0.01)
        path.stroke()
    }

    for y in stride(from: body.minY + size * 0.26, through: body.maxY - size * 0.36, by: size * 0.16) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: body.minX + size * 0.12, y: y))
        path.line(to: NSPoint(x: body.maxX - size * 0.12, y: y))
        path.lineWidth = max(1, size * 0.01)
        path.stroke()
    }

    NSColor(red: 0.0, green: 0.47, blue: 0.84, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: body.midX - size * 0.105, y: body.midY - size * 0.105, width: size * 0.21, height: size * 0.21)).fill()

    return image
}
