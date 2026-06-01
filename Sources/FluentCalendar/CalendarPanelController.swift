import AppKit

private final class CalendarFlyoutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CalendarPanelController: NSObject {
    private let onOpenSettings: () -> Void
    private let eventService = EventKitCalendarService()
    private var panel: NSPanel?
    private var contentView: CalendarPanelView?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var clockRefreshTimer: Timer?
    private weak var sourceButton: NSStatusBarButton?

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        super.init()
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel?.isVisible == true {
            close()
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        sourceButton = button

        if panel == nil {
            createPanel()
        }

        guard let panel, let contentView else { return }

        position(panel: panel, relativeTo: button)
        contentView.refreshClock()
        contentView.reloadEvents()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(contentView)

        installEventMonitors()
        startClockRefresh()
    }

    func close() {
        panel?.orderOut(nil)
        removeEventMonitors()
        stopClockRefresh()
    }

    private func createPanel() {
        let contentSize = NSSize(width: 460, height: 820)
        let panel = CalendarFlyoutPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isMovableByWindowBackground = false

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let acrylic = AcrylicBackgroundView(frame: container.bounds)
        acrylic.autoresizingMask = [.width, .height]
        container.addSubview(acrylic)

        let calendarView = CalendarPanelView(frame: container.bounds, eventService: eventService) { [weak self] in
            self?.onOpenSettings()
        }
        calendarView.autoresizingMask = [.width, .height]
        container.addSubview(calendarView)

        panel.contentView = container
        panel.animationBehavior = .utilityWindow

        self.panel = panel
        self.contentView = calendarView
    }

    private func position(panel: NSPanel, relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let screenFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let panelSize = panel.frame.size

        var origin = NSPoint(
            x: buttonRectOnScreen.midX - panelSize.width / 2,
            y: buttonRectOnScreen.minY - panelSize.height - 6
        )

        origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - panelSize.width - 8)

        if origin.y < screenFrame.minY + 8 {
            origin.y = buttonRectOnScreen.maxY + 6
        }

        panel.setFrameOrigin(origin)
    }

    private func installEventMonitors() {
        removeEventMonitors()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.close()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.close()
                return nil
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                let isPanelEvent = event.window === self.panel
                let isStatusButtonEvent = event.window === self.sourceButton?.window
                if !isPanelEvent && !isStatusButtonEvent {
                    self.close()
                }
            }

            return event
        }
    }

    private func removeEventMonitors() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }

        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func startClockRefresh() {
        stopClockRefresh()
        clockRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.contentView?.refreshClock()
        }
    }

    private func stopClockRefresh() {
        clockRefreshTimer?.invalidate()
        clockRefreshTimer = nil
    }
}
