import AppKit

final class AcrylicBackgroundView: NSVisualEffectView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.masksToBounds = true
        updateMaterial()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .fluentCalendarSettingsChanged,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func settingsChanged() {
        updateMaterial()
        needsDisplay = true
    }

    private func updateMaterial() {
        let isDark = AppSettings.shared.isDarkMode(for: effectiveAppearance)
        material = isDark ? .hudWindow : .popover
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterial()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isDark = AppSettings.shared.isDarkMode(for: effectiveAppearance)
        let tint = isDark
            ? NSColor(red: 0.09, green: 0.10, blue: 0.10, alpha: 0.76)
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 0.72)
        fill(dirtyRect, color: tint)

        drawNoise(in: dirtyRect, isDark: isDark)

        let border = isDark ? NSColor.white.withAlpha(0.16) : NSColor.black.withAlpha(0.16)
        stroke(bounds.insetBy(dx: 0.5, dy: 0.5), color: border, lineWidth: 1.0)
    }

    private func drawNoise(in dirtyRect: NSRect, isDark: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.clip(to: dirtyRect)

        let light = NSColor.white.withAlpha(isDark ? 0.035 : 0.08).cgColor
        let dark = NSColor.black.withAlpha(isDark ? 0.07 : 0.035).cgColor
        let minX = max(0, Int(floor(dirtyRect.minX)))
        let maxX = min(Int(ceil(bounds.maxX)), Int(ceil(dirtyRect.maxX)))
        let minY = max(0, Int(floor(dirtyRect.minY)))
        let maxY = min(Int(ceil(bounds.maxY)), Int(ceil(dirtyRect.maxY)))

        for y in stride(from: minY, through: maxY, by: 4) {
            for x in stride(from: minX, through: maxX, by: 4) {
                let hash = abs((x &* 73_856_093) ^ (y &* 19_349_663)) & 0xFF
                if hash < 18 {
                    context.setFillColor(hash.isMultiple(of: 2) ? light : dark)
                    context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1.0, height: 1.0))
                }
            }
        }

        context.restoreGState()
    }
}

func fill(_ rect: NSRect, color: NSColor) {
    color.setFill()
    NSBezierPath(rect: rect).fill()
}

func stroke(_ rect: NSRect, color: NSColor, lineWidth: CGFloat = 1.0) {
    color.setStroke()
    let path = NSBezierPath(rect: rect)
    path.lineWidth = lineWidth
    path.stroke()
}
