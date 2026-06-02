import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panelController: CalendarPanelController!
    private var clockTimer: Timer?
    private var settingsWindowController: SettingsWindowController?
    private var fullCalendarWindowController: FullCalendarWindowController?
    private var aboutWindowController: AboutWindowController?
    private var singleInstanceLockFileDescriptor: Int32 = -1
    private var hasAttemptedCalendarPanelOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            NSApp.terminate(nil)
            return
        }

        terminateDuplicateRunningApplications()
        scheduleDuplicateRunningApplicationCleanup()
        AppSettings.shared.applyAppearance()
        NSApp.applicationIconImage = AcrylicAppIcon.makeImage(size: 256)
        configureMainMenu()

        panelController = CalendarPanelController { [weak self] in
            self?.showSettings()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()
        updateStatusTitle()

        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStatusTitle()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .fluentCalendarSettingsChanged,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        clockTimer?.invalidate()
        releaseSingleInstanceLock()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let button = statusItem.button {
            panelController.show(relativeTo: button)
        }
        return true
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemPressed(_:))
        button.sendAction(on: [.leftMouseDown, .leftMouseUp, .rightMouseUp])
        button.toolTip = "Acrylic calendar"
    }

    private func updateStatusTitle() {
        guard let button = statusItem.button else { return }

        let title = Self.makeStatusTitle(for: Date())
        let attributes: [NSAttributedString.Key: Any] = [
            .font: windowsMonospacedDigitFont(size: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        button.attributedTitle = attributedTitle
        statusItem.length = max(132, ceil(attributedTitle.size().width) + 12)
    }

    private static func makeStatusTitle(for date: Date) -> String {
        let settings = AppSettings.shared
        var parts: [String] = []

        if settings.showsDayOfWeek {
            parts.append(settings.makeWeekdayFormatter().string(from: date))
        }

        switch settings.menuBarDateDisplay {
        case .whenSpaceAllows:
            parts.append(settings.makeMenuBarDateFormatter(always: false).string(from: date))
        case .always:
            parts.append(settings.makeMenuBarDateFormatter(always: true).string(from: date))
        case .never:
            break
        }

        parts.append(settings.makeTimeFormatter().string(from: date))
        return parts.joined(separator: "  ")
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "Fluent Calendar")
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(title: L10n.text("about"), action: #selector(showAboutFromMenu), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.text("settings.ellipsis"), action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.text("quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func statusItemPressed(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(relativeTo: button)
        } else {
            openCalendarPanel(relativeTo: button)
        }
    }

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.text("openCalendarPanel"), action: #selector(openCalendarFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.text("openFullCalendar"), action: #selector(openFullCalendarFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.text("settings"), action: #selector(showSettingsFromMenu), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L10n.text("about"), action: #selector(showAboutFromMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.text("quit"), action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 2), in: button)
    }

    @objc private func openCalendarFromMenu() {
        guard let button = statusItem.button else { return }
        openCalendarPanel(relativeTo: button)
    }

    private func openCalendarPanel(relativeTo button: NSStatusBarButton) {
        let shouldRetryFirstOpen = !hasAttemptedCalendarPanelOpen
        hasAttemptedCalendarPanelOpen = true

        showCalendarPanel(relativeTo: button, after: 0.01)
        if shouldRetryFirstOpen {
            showCalendarPanel(relativeTo: button, after: 0.18)
        }
    }

    private func showCalendarPanel(relativeTo button: NSStatusBarButton, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak button] in
            guard let self, let button else { return }
            self.panelController.show(relativeTo: button)
        }
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func openFullCalendarFromMenu() {
        showFullCalendar()
    }

    @objc private func showAboutFromMenu() {
        showAbout()
    }

    @objc private func settingsChanged() {
        configureMainMenu()
        updateStatusTitle()
    }

    @objc private func openClockSettings() {
        SystemSettingsOpener.openClockSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController { [weak self] in
                self?.showAbout()
            }
        }

        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController()
        }

        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showFullCalendar() {
        if fullCalendarWindowController == nil {
            fullCalendarWindowController = FullCalendarWindowController { [weak self] in
                self?.showSettings()
            }
        }

        fullCalendarWindowController?.showWindow(nil)
        fullCalendarWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func acquireSingleInstanceLock() -> Bool {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let lockDirectoryURL = baseURL.appendingPathComponent("Acrylic Calendar", isDirectory: true)

        do {
            try fileManager.createDirectory(at: lockDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return true
        }

        let lockURL = lockDirectoryURL.appendingPathComponent("single-instance.lock")
        let fileDescriptor = open(lockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else { return true }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 {
            singleInstanceLockFileDescriptor = fileDescriptor
            return true
        }

        close(fileDescriptor)
        return false
    }

    private func releaseSingleInstanceLock() {
        guard singleInstanceLockFileDescriptor >= 0 else { return }

        flock(singleInstanceLockFileDescriptor, LOCK_UN)
        close(singleInstanceLockFileDescriptor)
        singleInstanceLockFileDescriptor = -1
    }

    private func terminateDuplicateRunningApplications() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleIdentifier && app.processIdentifier != currentProcessIdentifier {
            app.terminate()
        }
    }

    private func scheduleDuplicateRunningApplicationCleanup() {
        for delay in [1.0, 3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.terminateDuplicateRunningApplications()
            }
        }
    }
}

enum SystemSettingsOpener {
    static func openClockSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Date-Time-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.datetime",
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension?Clock",
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
        ]

        for rawURL in urls {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
