import AppKit

enum AcrylicAppIcon {
    static func makeImage(size: CGFloat = 128) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
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

        image.unlockFocus()
        return image
    }
}

enum ProjectLinks {
    static let releases = "https://github.com/DurkaEbanaya/Acrylic-calendar/releases"
}

final class AboutWindowController: NSWindowController {
    init() {
        let contentSize = NSSize(width: 560, height: 360)
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        let acrylic = AcrylicBackgroundView(frame: container.bounds)
        acrylic.autoresizingMask = [.width, .height]
        container.addSubview(acrylic)

        let content = AboutContentView(frame: container.bounds)
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Acrylic calendar"
        window.contentView = container
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class AboutContentView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isDark = AppSettings.shared.isDarkMode(for: effectiveAppearance)
        let text = isDark ? NSColor.white.withAlpha(0.94) : NSColor.black.withAlpha(0.84)
        let secondary = isDark ? NSColor.white.withAlpha(0.68) : NSColor.black.withAlpha(0.58)

        AcrylicAppIcon.makeImage(size: 104).draw(in: NSRect(x: 40, y: 54, width: 104, height: 104))
        drawText("Acrylic calendar", in: NSRect(x: 168, y: 62, width: 330, height: 38), font: windowsUIFont(size: 30, weight: .light), color: text)
        drawText("DurkaEbanaya", in: NSRect(x: 170, y: 106, width: 300, height: 24), font: windowsUIFont(size: 17, weight: .regular), color: secondary)
        drawText("Version 1.1", in: NSRect(x: 170, y: 148, width: 200, height: 24), font: windowsUIFont(size: 15), color: text)
        drawText("2026", in: NSRect(x: 170, y: 176, width: 200, height: 24), font: windowsUIFont(size: 15), color: secondary)
        drawText(ProjectLinks.releases, in: NSRect(x: 40, y: 244, width: 480, height: 24), font: windowsUIFont(size: 15), color: NSColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1))
        drawText("Все права зачищены.", in: NSRect(x: 40, y: 286, width: 480, height: 24), font: windowsUIFont(size: 14), color: secondary)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if NSRect(x: 40, y: 244, width: 480, height: 24).contains(point), let url = URL(string: ProjectLinks.releases) {
            NSWorkspace.shared.open(url)
        }
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
}
