import AppKit
import ServiceManagement

final class SettingsWindowController: NSWindowController {
    init(onOpenAbout: @escaping () -> Void) {
        let contentView = SettingsContentView(frame: NSRect(x: 0, y: 0, width: 620, height: 620), onOpenAbout: onOpenAbout)
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = L10n.text("settings.title")
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SettingsContentView: NSView {
    override var isFlipped: Bool { true }

    private let onOpenAbout: () -> Void

    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let clockPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let hourCyclePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let dayOfWeekCheckbox = NSButton(checkboxWithTitle: "Show day of week", target: nil, action: nil)
    private let secondsCheckbox = NSButton(checkboxWithTitle: "Show seconds", target: nil, action: nil)
    private let aboutButton = NSButton(title: "About Acrylic calendar", target: nil, action: nil)
    private let systemAccentCheckbox = NSButton(checkboxWithTitle: "Use macOS accent color", target: nil, action: nil)
    private let colorWell = NSColorWell(frame: .zero)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)

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
        let isDark = AppSettings.shared.isDarkMode(for: effectiveAppearance)
        fill(bounds, color: isDark ? NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1) : NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1))
    }

    private func configureControls() {
        subviews.forEach { $0.removeFromSuperview() }

        addLabel(L10n.text("appearance"), frame: NSRect(x: 28, y: 28, width: 220, height: 24), size: 20, weight: .semibold)

        addLabel(L10n.text("theme"), frame: NSRect(x: 28, y: 72, width: 160, height: 22), size: 14)
        themePopup.frame = NSRect(x: 200, y: 68, width: 360, height: 28)
        themePopup.removeAllItems()
        themePopup.addItems(withTitles: ThemeMode.allCases.map(\.title))
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        addSubview(themePopup)

        addLabel(L10n.text("language"), frame: NSRect(x: 28, y: 116, width: 160, height: 22), size: 14)
        languagePopup.frame = NSRect(x: 200, y: 112, width: 360, height: 28)
        languagePopup.removeAllItems()
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.title))
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        addSubview(languagePopup)

        addLabel(L10n.text("showDate"), frame: NSRect(x: 28, y: 160, width: 160, height: 22), size: 14)
        clockPopup.frame = NSRect(x: 200, y: 156, width: 360, height: 28)
        clockPopup.removeAllItems()
        clockPopup.addItems(withTitles: MenuBarDateDisplay.allCases.map(\.title))
        clockPopup.target = self
        clockPopup.action = #selector(clockFormatChanged)
        addSubview(clockPopup)

        dayOfWeekCheckbox.title = L10n.text("showDayOfWeek")
        dayOfWeekCheckbox.frame = NSRect(x: 200, y: 194, width: 360, height: 24)
        dayOfWeekCheckbox.target = self
        dayOfWeekCheckbox.action = #selector(dayOfWeekChanged)
        addSubview(dayOfWeekCheckbox)

        addLabel(L10n.text("hourCycle"), frame: NSRect(x: 28, y: 234, width: 160, height: 22), size: 14)
        hourCyclePopup.frame = NSRect(x: 200, y: 230, width: 360, height: 28)
        hourCyclePopup.removeAllItems()
        hourCyclePopup.addItems(withTitles: HourCycle.allCases.map(\.title))
        hourCyclePopup.target = self
        hourCyclePopup.action = #selector(hourCycleChanged)
        addSubview(hourCyclePopup)

        secondsCheckbox.title = L10n.text("showSeconds")
        secondsCheckbox.frame = NSRect(x: 200, y: 270, width: 140, height: 24)
        secondsCheckbox.target = self
        secondsCheckbox.action = #selector(secondsChanged)
        addSubview(secondsCheckbox)

        aboutButton.title = L10n.text("about")
        aboutButton.frame = NSRect(x: 350, y: 266, width: 210, height: 30)
        aboutButton.bezelStyle = .regularSquare
        aboutButton.target = self
        aboutButton.action = #selector(openAbout)
        addSubview(aboutButton)

        systemAccentCheckbox.title = L10n.text("useAccent")
        systemAccentCheckbox.frame = NSRect(x: 200, y: 320, width: 360, height: 24)
        systemAccentCheckbox.target = self
        systemAccentCheckbox.action = #selector(systemAccentChanged)
        addSubview(systemAccentCheckbox)

        addLabel(L10n.text("accent"), frame: NSRect(x: 28, y: 356, width: 160, height: 22), size: 14)
        colorWell.frame = NSRect(x: 200, y: 350, width: 54, height: 32)
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        addSubview(colorWell)

        addPresetColorButtons(y: 394)

        addLabel(L10n.text("macosClock"), frame: NSRect(x: 28, y: 444, width: 260, height: 24), size: 20, weight: .semibold)
        addMultilineLabel(
            L10n.text("clockHelp"),
            frame: NSRect(x: 28, y: 480, width: 532, height: 54),
            size: 13
        )

        let clockSettingsButton = NSButton(title: L10n.text("openClockSettings"), target: self, action: #selector(openClockSettings))
        clockSettingsButton.frame = NSRect(x: 28, y: 552, width: 210, height: 30)
        clockSettingsButton.bezelStyle = .regularSquare
        addSubview(clockSettingsButton)

        launchAtLoginCheckbox.title = L10n.text("launchAtLogin")
        launchAtLoginCheckbox.frame = NSRect(x: 246, y: 556, width: 300, height: 24)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
        addSubview(launchAtLoginCheckbox)

        reloadControlState()
    }

    private func addPresetColorButtons(y: CGFloat) {
        let colors = ["#0078D7", "#2B88D8", "#00BCF2", "#107C10", "#881798", "#E81123"]
        for (index, hex) in colors.enumerated() {
            let button = NSButton(frame: NSRect(x: 200 + CGFloat(index) * 38, y: y, width: 28, height: 28))
            button.title = ""
            button.bezelStyle = .regularSquare
            button.wantsLayer = true
            button.layer?.backgroundColor = (NSColor(hexString: hex) ?? NSColor.windowsAccentBlue).cgColor
            button.target = self
            button.action = #selector(presetColorSelected(_:))
            button.tag = index
            addSubview(button)
        }
    }

    private func addLabel(_ text: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight = .regular) {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = windowsUIFont(size: size, weight: weight)
        label.textColor = NSColor.labelColor
        addSubview(label)
    }

    private func addMultilineLabel(_ text: String, frame: NSRect, size: CGFloat) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.frame = frame
        label.font = windowsUIFont(size: size, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor
        addSubview(label)
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
                AppSettings.shared.launchAtLoginManuallyDisabled = false
            } else {
                try SMAppService.mainApp.unregister()
                AppSettings.shared.launchAtLoginManuallyDisabled = true
            }
        } catch {
            launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
            let alert = NSAlert(error: error)
            alert.messageText = L10n.text("launchAtLoginError")
            alert.runModal()
        }
    }
}
