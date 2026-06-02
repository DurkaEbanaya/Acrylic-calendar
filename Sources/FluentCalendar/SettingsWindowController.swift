import AppKit
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    init(onOpenAbout: @escaping () -> Void) {
        let contentView = SettingsContentView(frame: NSRect(x: 0, y: 0, width: 1060, height: 720), onOpenAbout: onOpenAbout)
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = L10n.text("settings.title")
        window.contentView = contentView
        window.minSize = NSSize(width: 820, height: 640)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class WindowsToggleButton: NSButton {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        setButtonType(.toggle)
        font = windowsUIFont(size: 15, weight: .regular)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let isOn = state == .on
        let enabledAlpha: CGFloat = isEnabled ? 1.0 : 0.45
        let toggleRect = NSRect(x: 0, y: floor((bounds.height - 28) / 2), width: 62, height: 28)
        let track = NSBezierPath(roundedRect: toggleRect, xRadius: 14, yRadius: 14)
        (isOn ? AppSettings.shared.accentColor : NSColor.clear).withAlphaComponent(enabledAlpha).setFill()
        track.fill()
        (isOn ? AppSettings.shared.accentColor : NSColor.white.withAlphaComponent(0.72)).withAlphaComponent(enabledAlpha).setStroke()
        track.lineWidth = 2
        track.stroke()

        let knobX = isOn ? toggleRect.maxX - 24 : toggleRect.minX + 6
        NSColor.white.withAlphaComponent(enabledAlpha).setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX, y: toggleRect.minY + 6, width: 16, height: 16)).fill()

        let color = isEnabled ? NSColor.white.withAlphaComponent(0.92) : NSColor.white.withAlphaComponent(0.42)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(
            in: NSRect(x: 82, y: floor((bounds.height - 22) / 2) + 1, width: bounds.width - 82, height: 22),
            withAttributes: [.font: font ?? windowsUIFont(size: 15), .foregroundColor: color, .paragraphStyle: paragraph]
        )
    }
}

final class SettingsContentView: NSView {
    override var isFlipped: Bool { true }

    private let onOpenAbout: () -> Void

    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let clockPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hourCyclePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let dayOfWeekCheckbox = WindowsToggleButton(frame: .zero)
    private let secondsCheckbox = WindowsToggleButton(frame: .zero)
    private let aboutButton = NSButton(title: "About Acrylic calendar", target: nil, action: nil)
    private let systemAccentCheckbox = WindowsToggleButton(frame: .zero)
    private let colorWell = NSColorWell(frame: .zero)
    private let launchAtLoginCheckbox = WindowsToggleButton(frame: .zero)

    init(frame frameRect: NSRect, onOpenAbout: @escaping () -> Void) {
        self.onOpenAbout = onOpenAbout
        super.init(frame: frameRect)
        wantsLayer = true
        configureControls()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .fluentCalendarSettingsChanged,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fill(bounds, color: NSColor.black)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        guard oldSize != newSize else { return }
        configureControls()
    }

    private func configureControls() {
        subviews.forEach { $0.removeFromSuperview() }

        guard bounds.width > 0 else { return }

        let margin: CGFloat = bounds.width < 900 ? 32 : 48
        let gap: CGFloat = bounds.width < 900 ? 32 : 48
        let availableWidth = max(320, bounds.width - margin * 2)
        let usesTwoColumns = availableWidth >= 660
        let fieldWidth = usesTwoColumns ? floor((availableWidth - gap) / 2) : availableWidth
        let contentX = margin
        let rightX = usesTwoColumns ? margin + fieldWidth + gap : margin
        let clockTop: CGFloat = usesTwoColumns ? 136 : 620

        addLabel(L10n.text("settings"), frame: NSRect(x: contentX, y: 62, width: availableWidth, height: 52), size: 40, weight: .light)
        addLabel(L10n.text("appearance"), frame: NSRect(x: contentX, y: 136, width: fieldWidth, height: 30), size: 24, weight: .semibold)

        addLabel(L10n.text("theme"), frame: NSRect(x: contentX, y: 184, width: fieldWidth, height: 22), size: 16)
        themePopup.frame = NSRect(x: contentX, y: 212, width: fieldWidth, height: 36)
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: ThemeMode.allCases.map(\.title))
        stylePopup(themePopup)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        addSubview(themePopup)

        addLabel(L10n.text("language"), frame: NSRect(x: contentX, y: 266, width: fieldWidth, height: 22), size: 16)
        languagePopup.frame = NSRect(x: contentX, y: 294, width: fieldWidth, height: 36)
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.title))
        stylePopup(languagePopup)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        addSubview(languagePopup)

        addLabel(L10n.text("accent"), frame: NSRect(x: contentX, y: 352, width: fieldWidth, height: 24), size: 22, weight: .semibold)
        colorWell.frame = NSRect(x: contentX, y: 392, width: 54, height: 32)
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        addSubview(colorWell)

        addPresetColorButtons(x: contentX, y: 440, maxWidth: fieldWidth)

        systemAccentCheckbox.title = L10n.text("useAccent")
        systemAccentCheckbox.frame = NSRect(x: contentX, y: 490, width: fieldWidth, height: 34)
        systemAccentCheckbox.target = self
        systemAccentCheckbox.action = #selector(systemAccentChanged)
        addSubview(systemAccentCheckbox)

        aboutButton.title = L10n.text("about")
        aboutButton.frame = NSRect(x: contentX, y: 552, width: fieldWidth, height: 38)
        styleButton(aboutButton, accent: false)
        aboutButton.target = self
        aboutButton.action = #selector(openAbout)
        addSubview(aboutButton)

        addLabel(L10n.text("macosClock"), frame: NSRect(x: rightX, y: clockTop, width: fieldWidth, height: 30), size: 24, weight: .semibold)

        addLabel(L10n.text("showDate"), frame: NSRect(x: rightX, y: clockTop + 48, width: fieldWidth, height: 22), size: 16)
        clockPopup.frame = NSRect(x: rightX, y: clockTop + 76, width: fieldWidth, height: 36)
        clockPopup.removeAllItems()
        clockPopup.addItems(withTitles: MenuBarDateDisplay.allCases.map(\.title))
        stylePopup(clockPopup)
        clockPopup.target = self
        clockPopup.action = #selector(clockFormatChanged)
        addSubview(clockPopup)

        dayOfWeekCheckbox.title = L10n.text("showDayOfWeek")
        dayOfWeekCheckbox.frame = NSRect(x: rightX, y: clockTop + 132, width: fieldWidth, height: 34)
        dayOfWeekCheckbox.target = self
        dayOfWeekCheckbox.action = #selector(dayOfWeekChanged)
        addSubview(dayOfWeekCheckbox)

        addLabel(L10n.text("hourCycle"), frame: NSRect(x: rightX, y: clockTop + 192, width: fieldWidth, height: 22), size: 16)
        hourCyclePopup.frame = NSRect(x: rightX, y: clockTop + 220, width: fieldWidth, height: 36)
        hourCyclePopup.removeAllItems()
        hourCyclePopup.addItems(withTitles: HourCycle.allCases.map(\.title))
        stylePopup(hourCyclePopup)
        hourCyclePopup.target = self
        hourCyclePopup.action = #selector(hourCycleChanged)
        addSubview(hourCyclePopup)

        secondsCheckbox.title = L10n.text("showSeconds")
        secondsCheckbox.frame = NSRect(x: rightX, y: clockTop + 276, width: fieldWidth, height: 34)
        secondsCheckbox.target = self
        secondsCheckbox.action = #selector(secondsChanged)
        addSubview(secondsCheckbox)

        addMultilineLabel(
            L10n.text("clockHelp"),
            frame: NSRect(x: rightX, y: clockTop + 338, width: fieldWidth, height: 88),
            size: 13
        )

        let clockSettingsButton = NSButton(title: L10n.text("openClockSettings"), target: self, action: #selector(openClockSettings))
        clockSettingsButton.frame = NSRect(x: rightX, y: clockTop + 448, width: fieldWidth, height: 38)
        styleButton(clockSettingsButton, accent: false)
        addSubview(clockSettingsButton)

        launchAtLoginCheckbox.title = L10n.text("launchAtLogin")
        launchAtLoginCheckbox.frame = NSRect(x: rightX, y: clockTop + 510, width: fieldWidth, height: 34)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
        addSubview(launchAtLoginCheckbox)

        reloadControlState()
    }

    private func addPresetColorButtons(x: CGFloat, y: CGFloat, maxWidth: CGFloat) {
        let colors = ["#0078D7", "#2B88D8", "#00BCF2", "#107C10", "#881798", "#E81123"]
        let buttonSize: CGFloat = maxWidth < 250 ? 26 : 30
        let step = max(32, min(42, floor((maxWidth - buttonSize) / CGFloat(max(colors.count - 1, 1)))))
        for (index, hex) in colors.enumerated() {
            let button = NSButton(frame: NSRect(x: x + CGFloat(index) * step, y: y, width: buttonSize, height: buttonSize))
            button.title = ""
            button.bezelStyle = .regularSquare
            button.wantsLayer = true
            button.layer?.backgroundColor = (NSColor(hexString: hex) ?? NSColor.windowsAccentBlue).cgColor
            button.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
            button.layer?.borderWidth = 1
            button.target = self
            button.action = #selector(presetColorSelected(_:))
            button.tag = index
            addSubview(button)
        }
    }

    private func stylePopup(_ popup: NSPopUpButton) {
        popup.bezelStyle = .regularSquare
        popup.isBordered = true
        popup.font = windowsUIFont(size: 15, weight: .regular)
        popup.contentTintColor = .white
        popup.wantsLayer = true
        popup.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1).cgColor
        popup.layer?.borderColor = NSColor.white.withAlphaComponent(0.48).cgColor
        popup.layer?.borderWidth = 1
        popup.layer?.cornerRadius = 0
    }

    private func styleButton(_ button: NSButton, accent: Bool) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.font = windowsUIFont(size: 15, weight: .semibold)
        button.contentTintColor = .white
        button.wantsLayer = true
        button.layer?.backgroundColor = (accent ? AppSettings.shared.accentColor : NSColor(red: 0.20, green: 0.20, blue: 0.20, alpha: 1)).cgColor
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        button.layer?.borderWidth = 1
        button.layer?.cornerRadius = 0
    }

    private func addLabel(_ text: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight = .regular) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = windowsUIFont(size: size, weight: weight)
        label.textColor = NSColor.white.withAlphaComponent(weight == .light ? 0.96 : 0.92)
        addSubview(label)
    }

    private func addMultilineLabel(_ text: String, frame: NSRect, size: CGFloat) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = frame
        label.font = windowsUIFont(size: size, weight: .regular)
        label.textColor = NSColor.white.withAlphaComponent(0.72)
        addSubview(label)
    }

    private func drawSidebarItem(icon: String, title: String, y: CGFloat, selected: Bool) {
        let rect = NSRect(x: 0, y: y, width: 360, height: 54)
        if selected {
            fill(NSRect(x: 0, y: y, width: 5, height: 54), color: AppSettings.shared.accentColor)
            fill(rect, color: NSColor.white.withAlphaComponent(0.10))
        }
        drawText(icon, in: NSRect(x: 22, y: y + 13, width: 28, height: 28), font: windowsUIFont(size: 22), color: .white, alignment: .center)
        drawText(title, in: NSRect(x: 70, y: y + 15, width: 260, height: 24), font: windowsUIFont(size: 19), color: .white, alignment: .left)
    }

    private func drawNoise(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let light = NSColor.white.withAlphaComponent(0.045).cgColor
        let dark = NSColor.black.withAlphaComponent(0.055).cgColor
        for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 5) {
            for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 7) {
                context.setFillColor(((x + y) % 3 == 0 ? light : dark))
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }

    private func reloadControlState() {
        let settings = AppSettings.shared
        themePopup.selectItem(at: ThemeMode.allCases.firstIndex(of: settings.themeMode) ?? 0)
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: settings.appLanguage) ?? 0)
        clockPopup.selectItem(at: MenuBarDateDisplay.allCases.firstIndex(of: settings.menuBarDateDisplay) ?? 0)
        hourCyclePopup.selectItem(at: HourCycle.allCases.firstIndex(of: settings.hourCycle) ?? 0)
        dayOfWeekCheckbox.state = settings.showsDayOfWeek ? .on : .off
        secondsCheckbox.state = settings.showsSeconds ? .on : .off
        systemAccentCheckbox.state = settings.usesSystemAccent ? .on : .off
        colorWell.color = settings.customAccentColor
        colorWell.isEnabled = !settings.usesSystemAccent

        if #available(macOS 13.0, *) {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            launchAtLoginCheckbox.isEnabled = Bundle.main.bundleURL.pathExtension == "app"
        } else {
            launchAtLoginCheckbox.isEnabled = false
        }
    }

    @objc private func settingsChanged() {
        configureControls()
        window?.title = L10n.text("settings.title")
        needsDisplay = true
    }

    @objc private func themeChanged() {
        AppSettings.shared.themeMode = ThemeMode.allCases[themePopup.indexOfSelectedItem]
    }

    @objc private func languageChanged() {
        AppSettings.shared.appLanguage = AppLanguage.allCases[languagePopup.indexOfSelectedItem]
    }

    @objc private func clockFormatChanged() {
        AppSettings.shared.menuBarDateDisplay = MenuBarDateDisplay.allCases[clockPopup.indexOfSelectedItem]
    }

    @objc private func dayOfWeekChanged() {
        AppSettings.shared.showsDayOfWeek = dayOfWeekCheckbox.state == .on
    }

    @objc private func hourCycleChanged() {
        AppSettings.shared.hourCycle = HourCycle.allCases[hourCyclePopup.indexOfSelectedItem]
    }

    @objc private func secondsChanged() {
        AppSettings.shared.showsSeconds = secondsCheckbox.state == .on
    }

    @objc private func openAbout() {
        onOpenAbout()
    }

    @objc private func systemAccentChanged() {
        AppSettings.shared.usesSystemAccent = systemAccentCheckbox.state == .on
        reloadControlState()
    }

    @objc private func colorChanged() {
        AppSettings.shared.customAccentColor = colorWell.color
    }

    @objc private func presetColorSelected(_ sender: NSButton) {
        let colors = ["#0078D7", "#2B88D8", "#00BCF2", "#107C10", "#881798", "#E81123"]
        guard colors.indices.contains(sender.tag), let color = NSColor(hexString: colors[sender.tag]) else { return }
        AppSettings.shared.usesSystemAccent = false
        AppSettings.shared.customAccentColor = color
        reloadControlState()
    }

    @objc private func openClockSettings() {
        SystemSettingsOpener.openClockSettings()
    }

    @objc private func launchAtLoginChanged() {
        guard #available(macOS 13.0, *) else { return }

        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            let alert = NSAlert(error: error)
            alert.messageText = L10n.text("launchAtLoginError")
            alert.runModal()
        }
    }
}
