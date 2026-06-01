import AppKit

final class FullCalendarWindowController: NSWindowController {
    init(onOpenSettings: @escaping () -> Void) {
        let eventService = EventKitCalendarService()
        let initialFrame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let containerView = NSView(frame: initialFrame)
        containerView.autoresizingMask = [.width, .height]

        let sidebarAcrylic = AcrylicBackgroundView(frame: NSRect(x: 0, y: 0, width: 340, height: initialFrame.height))
        sidebarAcrylic.autoresizingMask = [.height]
        containerView.addSubview(sidebarAcrylic)

        let contentView = FullCalendarView(frame: initialFrame, eventService: eventService, onOpenSettings: onOpenSettings)
        contentView.autoresizingMask = [.width, .height]
        containerView.addSubview(contentView)
        let window = NSWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = L10n.text("calendar")
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = containerView
        window.initialFirstResponder = contentView
        window.minSize = NSSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        contentView.reloadEvents()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class FullCalendarView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private enum CalendarViewMode {
        case day
        case week
        case month
        case year
    }

    private struct Layout {
        let sidebarRect: NSRect
        let commandRect: NSRect
        let hamburgerRect: NSRect
        let monthTitleRect: NSRect
        let todayRect: NSRect
        let dayModeRect: NSRect
        let weekModeRect: NSRect
        let monthModeRect: NSRect
        let yearModeRect: NSRect
        let settingsTextRect: NSRect
        let previousRect: NSRect
        let nextRect: NSRect
        let newEventRect: NSRect
        let mailRect: NSRect
        let calendarNavRect: NSRect
        let contactsRect: NSRect
        let notesRect: NSRect
        let settingsRect: NSRect
        let weekdayRect: NSRect
        let gridRect: NSRect
        let cellSize: NSSize
        let miniMonthRect: NSRect
    }

    private struct DayCell {
        let index: Int
        let date: Date
        let rect: NSRect
        let isDisplayedMonth: Bool
    }

    private struct EventHitRegion {
        let rect: NSRect
        let event: CalendarEventSummary
    }

    private struct DateHitRegion {
        let rect: NSRect
        let date: Date
    }

    private enum HitTarget: Equatable {
        case day(Int)
        case today
        case previous
        case next
        case dayMode
        case weekMode
        case monthMode
        case yearMode
        case newEvent
        case mail
        case calendarNav
        case contacts
        case notes
        case settings
        case hamburger
        case event(Int)
        case weekDay(Date)
        case yearDay(Date)
        case yearMonth(Date)
    }

    private let eventService: EventKitCalendarService
    private let onOpenSettings: () -> Void
    private var calendar = Calendar.autoupdatingCurrent
    private var displayedMonth: Date
    private var selectedDate: Date
    private var eventsByDay: [Date: [CalendarEventSummary]] = [:]
    private var eventStatusMessage: String?
    private var dayCells: [DayCell] = []
    private var eventHitRegions: [EventHitRegion] = []
    private var weekDayHitRegions: [DateHitRegion] = []
    private var yearDayHitRegions: [DateHitRegion] = []
    private var yearMonthHitRegions: [DateHitRegion] = []
    private var hoveredTarget: HitTarget?
    private var pressedTarget: HitTarget?
    private var mousePoint: NSPoint?
    private var scrollAccumulator: CGFloat = 0
    private var isSidebarExpanded = true
    private var viewMode: CalendarViewMode = .month
    private var dayPopover: NSPopover?

    init(frame frameRect: NSRect, eventService: EventKitCalendarService, onOpenSettings: @escaping () -> Void) {
        self.eventService = eventService
        self.onOpenSettings = onOpenSettings
        let today = Date()
        self.calendar.locale = AppSettings.shared.localizedLocale
        self.selectedDate = calendar.startOfDay(for: today)
        self.displayedMonth = Self.startOfMonth(for: today, calendar: calendar)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 0

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: .fluentCalendarSettingsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventsChanged),
            name: .fluentCalendarEventsChanged,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func reloadEvents() {
        eventStatusMessage = L10n.text("loadingEvents")
        needsDisplay = true

        eventService.fetchEvents(in: visibleDateInterval()) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let events):
                self.eventStatusMessage = nil
                self.eventsByDay = self.groupEventsByDay(events)
            case .failure(let error):
                self.eventsByDay = [:]
                self.eventStatusMessage = error.localizedDescription
            }

            self.needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let layout = makeLayout()
        eventHitRegions.removeAll()
        weekDayHitRegions.removeAll()
        yearDayHitRegions.removeAll()
        yearMonthHitRegions.removeAll()
        dayCells = makeDayCells(layout: layout)

        drawBackground(layout: layout)
        drawSidebar(layout: layout)
        drawCommandBar(layout: layout)

        switch viewMode {
        case .day:
            drawDayView(layout: layout)
        case .week:
            drawWeekView(layout: layout)
        case .month:
            drawWeekdays(layout: layout)
            drawMonthGrid(layout: layout)
        case .year:
            drawYearView(layout: layout)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mousePoint = point
        hoveredTarget = hitTarget(at: point)
        if hoveredTarget != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredTarget = nil
        mousePoint = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let target = hitTarget(at: point) else { return }
        pressedTarget = target
        needsDisplay = true

        switch target {
        case .event(let index):
            guard eventHitRegions.indices.contains(index) else { return }
            dayPopover?.close()
            EventKitCalendarService.openEventInCalendar(eventHitRegions[index].event)
        case .weekDay(let date):
            selectedDate = calendar.startOfDay(for: date)
            displayedMonth = Self.startOfMonth(for: date, calendar: calendar)
            needsDisplay = true
            if let region = weekDayHitRegions.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
                showDayDetailsPopover(for: selectedDate, sourceRect: region.rect)
            }
        case .yearDay(let date):
            selectedDate = calendar.startOfDay(for: date)
            displayedMonth = Self.startOfMonth(for: date, calendar: calendar)
            viewMode = .day
            reloadEvents()
        case .yearMonth(let date):
            displayedMonth = Self.startOfMonth(for: date, calendar: calendar)
            selectedDate = displayedMonth
            viewMode = .month
            reloadEvents()
        case .day(let index):
            guard let cell = dayCells.first(where: { $0.index == index }) else { return }
            selectedDate = calendar.startOfDay(for: cell.date)
            if !isSameMonth(cell.date, displayedMonth) {
                displayedMonth = Self.startOfMonth(for: cell.date, calendar: calendar)
                reloadEvents()
            } else {
                needsDisplay = true
            }
            showDayDetailsPopover(for: selectedDate, sourceRect: cell.rect)
        case .today:
            selectToday()
        case .previous:
            changeDisplayedMonth(by: -1)
        case .next:
            changeDisplayedMonth(by: 1)
        case .dayMode:
            showTodayDayView()
        case .weekMode:
            setViewMode(.week)
        case .monthMode:
            setViewMode(.month)
        case .yearMode:
            setViewMode(.year)
        case .newEvent:
            showQuickAddAlert()
        case .mail:
            openSystemApplication(named: "Mail")
        case .calendarNav:
            setViewMode(.month)
        case .contacts:
            openSystemApplication(named: "Contacts")
        case .notes:
            openSystemApplication(named: "Notes")
        case .settings:
            onOpenSettings()
        case .hamburger:
            isSidebarExpanded.toggle()
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        pressedTarget = nil
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 42 : 1
        guard abs(scrollAccumulator) >= threshold else { return }

        let direction = scrollAccumulator > 0 ? -1 : 1
        scrollAccumulator = 0
        changeDisplayedMonth(by: direction)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            moveSelectedDate(byDays: viewMode == .year ? -31 : -1)
        case 124:
            moveSelectedDate(byDays: viewMode == .year ? 31 : 1)
        case 125:
            moveSelectedDate(byDays: viewMode == .year ? 92 : 7)
        case 126:
            moveSelectedDate(byDays: viewMode == .year ? -92 : -7)
        case 115:
            selectToday()
        case 116:
            changeDisplayedMonth(by: viewMode == .year ? -12 : -1)
        case 121:
            changeDisplayedMonth(by: viewMode == .year ? 12 : 1)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "t": selectToday()
            case "d": showTodayDayView()
            case "w": setViewMode(.week)
            case "m": setViewMode(.month)
            case "y": setViewMode(.year)
            case "n": showQuickAddAlert()
            default: super.keyDown(with: event)
            }
        }
    }

    @objc private func settingsChanged() {
        calendar.locale = AppSettings.shared.localizedLocale
        window?.title = L10n.text("calendar")
        needsDisplay = true
    }

    @objc private func eventsChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.reloadEvents()
        }
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func changeDisplayedMonth(by delta: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        normalizeSelectedDateForDisplayedMonth()
        reloadEvents()
    }

    private func setViewMode(_ mode: CalendarViewMode) {
        guard viewMode != mode else {
            needsDisplay = true
            return
        }
        viewMode = mode
        reloadEvents()
    }

    private func showTodayDayView() {
        let today = Date()
        selectedDate = calendar.startOfDay(for: today)
        displayedMonth = Self.startOfMonth(for: today, calendar: calendar)
        viewMode = .day
        reloadEvents()
    }

    private func moveSelectedDate(byDays days: Int) {
        guard let nextDate = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = calendar.startOfDay(for: nextDate)
        displayedMonth = Self.startOfMonth(for: nextDate, calendar: calendar)
        reloadEvents()
    }

    private func selectToday() {
        let today = Date()
        selectedDate = calendar.startOfDay(for: today)
        displayedMonth = Self.startOfMonth(for: today, calendar: calendar)
        reloadEvents()
    }

    private func normalizeSelectedDateForDisplayedMonth() {
        guard !isSameMonth(selectedDate, displayedMonth) else { return }
        let desiredDay = min(calendar.component(.day, from: selectedDate), daysInDisplayedMonth())
        selectedDate = calendar.date(byAdding: .day, value: desiredDay - 1, to: displayedMonth) ?? displayedMonth
    }

    private func makeLayout() -> Layout {
        let sidebarWidth = isSidebarExpanded ? min(max(bounds.width * 0.26, 280), 340) : 60
        let sidebarRect = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        let commandRect = NSRect(x: sidebarWidth, y: 0, width: bounds.width - sidebarWidth, height: 106)
        let weekdayRect = NSRect(x: sidebarWidth, y: commandRect.maxY, width: commandRect.width, height: 34)
        let gridRect = NSRect(x: sidebarWidth, y: weekdayRect.maxY, width: commandRect.width, height: bounds.height - weekdayRect.maxY)
        let cellWidth = floor(gridRect.width / 7)
        let cellHeight = floor(gridRect.height / 6)
        let gridWidth = cellWidth * 7
        let gridHeight = cellHeight * 6
        let commandGap: CGFloat = 8
        let dayWidth: CGFloat = 82
        let weekWidth: CGFloat = 94
        let monthWidth: CGFloat = 108
        let yearWidth: CGFloat = 86
        let commandGroupWidth = dayWidth + weekWidth + monthWidth + yearWidth + commandGap * 3
        let trailingCommandStartX = commandRect.maxX - commandGroupWidth - 20
        let commandStartX = min(max(commandRect.minX + 330, trailingCommandStartX), trailingCommandStartX)
        let bottomIconSize: CGFloat = 36
        let expandedSlotWidth = sidebarRect.width / 5
        let expandedIconY = sidebarRect.maxY - 58
        let expandedCalendarSize = NSSize(width: 48, height: 44)
        let collapsedX = sidebarRect.minX + 12
        let collapsedStep: CGFloat = 56

        func expandedIconRect(_ slot: Int) -> NSRect {
            NSRect(
                x: sidebarRect.minX + CGFloat(slot) * expandedSlotWidth + floor((expandedSlotWidth - bottomIconSize) / 2),
                y: expandedIconY,
                width: bottomIconSize,
                height: bottomIconSize
            )
        }

        func expandedCalendarRect() -> NSRect {
            NSRect(
                x: sidebarRect.minX + expandedSlotWidth + floor((expandedSlotWidth - expandedCalendarSize.width) / 2),
                y: sidebarRect.maxY - 62,
                width: expandedCalendarSize.width,
                height: expandedCalendarSize.height
            )
        }

        return Layout(
            sidebarRect: sidebarRect,
            commandRect: commandRect,
            hamburgerRect: NSRect(x: sidebarRect.minX + 14, y: 56, width: 34, height: 34),
            monthTitleRect: NSRect(x: commandRect.minX + 112, y: 28, width: 260, height: 48),
            todayRect: .zero,
            dayModeRect: NSRect(x: commandStartX, y: 28, width: dayWidth, height: 42),
            weekModeRect: NSRect(x: commandStartX + dayWidth + commandGap, y: 28, width: weekWidth, height: 42),
            monthModeRect: NSRect(x: commandStartX + dayWidth + weekWidth + commandGap * 2, y: 28, width: monthWidth, height: 42),
            yearModeRect: NSRect(x: commandStartX + dayWidth + weekWidth + monthWidth + commandGap * 3, y: 28, width: yearWidth, height: 42),
            settingsTextRect: .zero,
            previousRect: NSRect(x: commandRect.minX + 24, y: 26, width: 42, height: 44),
            nextRect: NSRect(x: commandRect.minX + 68, y: 26, width: 42, height: 44),
            newEventRect: isSidebarExpanded ? NSRect(x: sidebarRect.minX + 24, y: 104, width: sidebarRect.width - 48, height: 48) : NSRect(x: sidebarRect.minX + 12, y: 112, width: 36, height: 36),
            mailRect: isSidebarExpanded ? expandedIconRect(0) : NSRect(x: collapsedX, y: sidebarRect.maxY - 52 - collapsedStep * 4, width: bottomIconSize, height: bottomIconSize),
            calendarNavRect: isSidebarExpanded ? expandedCalendarRect() : NSRect(x: sidebarRect.minX, y: sidebarRect.maxY - 60 - collapsedStep * 3, width: sidebarRect.width, height: 48),
            contactsRect: isSidebarExpanded ? expandedIconRect(2) : NSRect(x: collapsedX, y: sidebarRect.maxY - 52 - collapsedStep * 2, width: bottomIconSize, height: bottomIconSize),
            notesRect: isSidebarExpanded ? expandedIconRect(3) : NSRect(x: collapsedX, y: sidebarRect.maxY - 52 - collapsedStep, width: bottomIconSize, height: bottomIconSize),
            settingsRect: isSidebarExpanded ? expandedIconRect(4) : NSRect(x: collapsedX, y: sidebarRect.maxY - 52, width: bottomIconSize, height: bottomIconSize),
            weekdayRect: weekdayRect,
            gridRect: NSRect(x: gridRect.minX, y: gridRect.minY, width: gridWidth, height: gridHeight),
            cellSize: NSSize(width: cellWidth, height: cellHeight),
            miniMonthRect: NSRect(x: sidebarRect.minX + 24, y: 180, width: max(0, sidebarRect.width - 48), height: 238)
        )
    }

    private func makeDayCells(layout: Layout) -> [DayCell] {
        let firstDayOfMonth = Self.startOfMonth(for: displayedMonth, calendar: calendar)
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = daysInDisplayedMonth()

        return (0..<dayCount).compactMap { dayOffset in
            let index = leadingDays + dayOffset
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: firstDayOfMonth) else { return nil }
            let column = index % 7
            let row = index / 7
            let rect = NSRect(
                x: layout.gridRect.minX + CGFloat(column) * layout.cellSize.width,
                y: layout.gridRect.minY + CGFloat(row) * layout.cellSize.height,
                width: layout.cellSize.width,
                height: layout.cellSize.height
            )
            return DayCell(index: index, date: date, rect: rect, isDisplayedMonth: true)
        }
    }

    private func visibleDateInterval() -> DateInterval {
        let start: Date
        let end: Date

        switch viewMode {
        case .day:
            start = calendar.startOfDay(for: selectedDate)
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        case .week:
            start = startOfWeek(for: selectedDate)
            end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        case .month:
            start = calendar.startOfDay(for: displayedMonth)
            end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        case .year:
            let components = calendar.dateComponents([.year], from: displayedMonth)
            start = calendar.date(from: components) ?? displayedMonth
            end = calendar.date(byAdding: .year, value: 1, to: start) ?? start
        }

        return DateInterval(start: start, end: end)
    }

    private func daysInDisplayedMonth() -> Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    private func groupEventsByDay(_ events: [CalendarEventSummary]) -> [Date: [CalendarEventSummary]] {
        let interval = visibleDateInterval()
        let inclusiveEnd = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        var grouped: [Date: [CalendarEventSummary]] = [:]

        for event in events {
            let eventEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
            var day = calendar.startOfDay(for: max(event.startDate, interval.start))
            let finalDay = calendar.startOfDay(for: min(eventEnd, inclusiveEnd))

            while day <= finalDay {
                grouped[day, default: []].append(event)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }

        for key in grouped.keys {
            grouped[key]?.sort { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
        }

        return grouped
    }

    private func hitTarget(at point: NSPoint) -> HitTarget? {
        let layout = makeLayout()
        if let eventIndex = eventHitRegions.firstIndex(where: { $0.rect.contains(point) }) {
            return .event(eventIndex)
        }
        if layout.hamburgerRect.contains(point) { return .hamburger }
        if layout.todayRect.contains(point) { return .today }
        if layout.dayModeRect.contains(point) { return .dayMode }
        if layout.weekModeRect.contains(point) { return .weekMode }
        if layout.monthModeRect.contains(point) { return .monthMode }
        if layout.yearModeRect.contains(point) { return .yearMode }
        if layout.previousRect.contains(point) { return .previous }
        if layout.nextRect.contains(point) { return .next }
        if layout.newEventRect.contains(point) { return .newEvent }
        if layout.mailRect.contains(point) { return .mail }
        if layout.calendarNavRect.contains(point) { return .calendarNav }
        if layout.contactsRect.contains(point) { return .contacts }
        if layout.notesRect.contains(point) { return .notes }
        if layout.settingsRect.contains(point) { return .settings }

        if viewMode == .month {
            let cells = dayCells.isEmpty ? makeDayCells(layout: layout) : dayCells
            if let cell = cells.first(where: { $0.rect.contains(point) }) {
                return .day(cell.index)
            }
        } else if viewMode == .week {
            if let region = weekDayHitRegions.first(where: { $0.rect.contains(point) }) {
                return .weekDay(region.date)
            }
        } else if viewMode == .year {
            if let region = yearDayHitRegions.first(where: { $0.rect.contains(point) }) {
                return .yearDay(region.date)
            }
            if let region = yearMonthHitRegions.first(where: { $0.rect.contains(point) }) {
                return .yearMonth(region.date)
            }
        }

        return nil
    }

    private func showQuickAddAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.text("newEvent")
        alert.informativeText = L10n.text("createEventOnSelectedDay")
        alert.addButton(withTitle: L10n.text("save"))
        alert.addButton(withTitle: L10n.text("cancel"))

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 340, height: 164))
        stack.orientation = .vertical
        stack.spacing = 8

        let titleField = NSTextField(string: L10n.text("newEvent"))
        titleField.placeholderString = L10n.text("eventName")
        let locationField = NSTextField(string: "")
        locationField.placeholderString = L10n.text("location")

        let timeRow = NSStackView(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        timeRow.orientation = .horizontal
        timeRow.spacing = 8
        let startPicker = NSDatePicker()
        startPicker.datePickerStyle = .textFieldAndStepper
        startPicker.datePickerElements = [.hourMinute]
        let endPicker = NSDatePicker()
        endPicker.datePickerStyle = .textFieldAndStepper
        endPicker.datePickerElements = [.hourMinute]
        let defaultStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate.addingTimeInterval(9 * 3600)
        startPicker.dateValue = defaultStart
        endPicker.dateValue = defaultStart.addingTimeInterval(3600)
        timeRow.addArrangedSubview(startPicker)
        timeRow.addArrangedSubview(NSTextField(labelWithString: L10n.text("to")))
        timeRow.addArrangedSubview(endPicker)

        let reminderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        reminderPopup.addItems(withTitles: [L10n.text("noReminder"), L10n.text("minutes15"), L10n.text("minutes30"), L10n.text("hour1"), L10n.text("day1")])
        reminderPopup.selectItem(at: 1)

        stack.addArrangedSubview(titleField)
        stack.addArrangedSubview(locationField)
        stack.addArrangedSubview(timeRow)
        stack.addArrangedSubview(reminderPopup)
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let start = combinedDate(day: selectedDate, time: startPicker.dateValue)
        var end = combinedDate(day: selectedDate, time: endPicker.dateValue)
        if end <= start {
            end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        }
        eventService.createEvent(title: titleField.stringValue, location: locationField.stringValue, startDate: start, endDate: end, alarmOffsetMinutes: reminderMinutes(from: reminderPopup)) { [weak self] result in
            switch result {
            case .success(let event):
                self?.addOptimisticEvent(event)
                self?.reloadEvents()
            case .failure(let error):
                let errorAlert = NSAlert()
                errorAlert.messageText = L10n.text("eventSaveError")
                errorAlert.informativeText = error.localizedDescription
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }

    private func addOptimisticEvent(_ event: CalendarEventSummary) {
        for day in daysCoveredByEvent(event) {
            var events = eventsByDay[day] ?? []
            if !events.contains(where: { $0.identifier == event.identifier }) {
                events.append(event)
            }
            eventsByDay[day] = events.sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        needsDisplay = true
    }

    private func daysCoveredByEvent(_ event: CalendarEventSummary) -> [Date] {
        let interval = visibleDateInterval()
        let eventEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
        let inclusiveIntervalEnd = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        var day = calendar.startOfDay(for: Swift.max(event.startDate, interval.start))
        let finalDay = calendar.startOfDay(for: Swift.min(eventEnd, inclusiveIntervalEnd))
        var days: [Date] = []

        while day <= finalDay {
            days.append(day)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return days
    }

    private func showDayDetailsPopover(for date: Date, sourceRect: NSRect) {
        let key = calendar.startOfDay(for: date)
        let events = eventsByDay[key] ?? []

        dayPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = DayDetailsPopoverController(
            date: key,
            events: events,
            onAdd: { [weak self, weak popover] in
                guard let self else { return }
                self.selectedDate = key
                popover?.close()
                self.showQuickAddAlert()
            },
            onOpenEvent: { [weak popover] event in
                popover?.close()
                EventKitCalendarService.openEventInCalendar(event)
            }
        )
        dayPopover = popover
        popover.show(relativeTo: sourceRect, of: self, preferredEdge: .maxY)
    }

    private func combinedDate(day: Date, time: Date) -> Date {
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = .current
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return calendar.date(from: components) ?? day
    }

    private func reminderMinutes(from popup: NSPopUpButton) -> Int? {
        switch popup.indexOfSelectedItem {
        case 1: return 15
        case 2: return 30
        case 3: return 60
        case 4: return 24 * 60
        default: return nil
        }
    }

    private func openSystemApplication(named name: String) {
        let urls = [
            URL(fileURLWithPath: "/System/Applications/\(name).app"),
            URL(fileURLWithPath: "/Applications/\(name).app")
        ]

        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return
        }
    }

    private var isDarkMode: Bool {
        AppSettings.shared.isDarkMode(for: effectiveAppearance)
    }

    private var accentColor: NSColor {
        AppSettings.shared.accentColor
    }

    private var mainBackground: NSColor {
        isDarkMode ? NSColor(red: 0.095, green: 0.095, blue: 0.095, alpha: 1) : NSColor(red: 0.985, green: 0.985, blue: 0.985, alpha: 1)
    }

    private var panelBackground: NSColor {
        isDarkMode ? NSColor(red: 0.135, green: 0.135, blue: 0.135, alpha: 1) : NSColor.white
    }

    private var textColor: NSColor {
        isDarkMode ? NSColor.white.withAlpha(0.94) : NSColor.black.withAlpha(0.84)
    }

    private var secondaryTextColor: NSColor {
        isDarkMode ? NSColor.white.withAlpha(0.56) : NSColor.black.withAlpha(0.54)
    }

    private var gridLineColor: NSColor {
        isDarkMode ? NSColor.black.withAlpha(0.55) : NSColor.black.withAlpha(0.10)
    }

    private func drawBackground(layout: Layout) {
        fill(NSRect(x: layout.sidebarRect.maxX, y: 0, width: bounds.width - layout.sidebarRect.maxX, height: bounds.height), color: mainBackground)
        fill(layout.commandRect, color: panelBackground)
    }

    private func drawSidebar(layout: Layout) {
        let sidebar = layout.sidebarRect
        fill(sidebar, color: isDarkMode ? NSColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 0.20) : accentColor.withAlpha(0.20))

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.clip(to: sidebar)
            let top = isDarkMode ? NSColor.white.withAlpha(0.09).cgColor : NSColor.white.withAlpha(0.30).cgColor
            let bottom = NSColor.black.withAlpha(isDarkMode ? 0.30 : 0.14).cgColor
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: NSPoint(x: sidebar.midX, y: sidebar.minY), end: NSPoint(x: sidebar.midX, y: sidebar.maxY), options: [])
            }
            drawNoise(in: sidebar)
            context.restoreGState()
        }

        if isSidebarExpanded {
            drawText(L10n.text("calendar"), in: NSRect(x: 24, y: 14, width: sidebar.width - 48, height: 24), font: windowsUIFont(size: 14), color: .white, alignment: .left)
        }

        if hoveredTarget == .hamburger, let mousePoint {
            drawReveal(in: layout.hamburgerRect, at: mousePoint)
        }
        drawHamburger(in: layout.hamburgerRect, color: .white)

        if hoveredTarget == .newEvent, let mousePoint {
            drawReveal(in: layout.newEventRect, at: mousePoint)
        }
        if isSidebarExpanded {
            drawText("+  \(L10n.text("newEvent"))", in: layout.newEventRect.insetBy(dx: 0, dy: 10), font: windowsUIFont(size: 23, weight: .semibold), color: .white, alignment: .left)
            drawMiniMonth(layout: layout)
        } else {
            drawText("+", in: layout.newEventRect.insetBy(dx: 0, dy: 0), font: windowsUIFont(size: 30, weight: .light), color: .white, alignment: .center)
        }

        drawSidebarNavIcons(layout: layout)

        if hoveredTarget == .settings, let mousePoint {
            drawReveal(in: layout.settingsRect, at: mousePoint)
        }
        drawGear(in: layout.settingsRect.insetBy(dx: 7, dy: 7), color: .white)
    }

    private func drawSidebarNavIcons(layout: Layout) {
        if hoveredTarget == .mail, let mousePoint { drawReveal(in: layout.mailRect, at: mousePoint) }
        if hoveredTarget == .calendarNav, let mousePoint { drawReveal(in: layout.calendarNavRect, at: mousePoint) }
        if hoveredTarget == .contacts, let mousePoint { drawReveal(in: layout.contactsRect, at: mousePoint) }
        if hoveredTarget == .notes, let mousePoint { drawReveal(in: layout.notesRect, at: mousePoint) }
        if pressedTarget == .calendarNav {
            fill(layout.calendarNavRect, color: NSColor.white.withAlpha(0.18))
        }

        drawMailIcon(in: centeredIconRect(in: layout.mailRect, size: 23), color: .white)
        drawCalendarIcon(in: centeredIconRect(in: layout.calendarNavRect, size: 24), color: .white, grid: true, arrow: false)
        drawContactsIcon(in: centeredIconRect(in: layout.contactsRect, size: 23), color: .white)
        drawCheckIcon(in: centeredIconRect(in: layout.notesRect, size: 23), color: .white)
    }

    private func centeredIconRect(in rect: NSRect, size: CGFloat) -> NSRect {
        NSRect(x: floor(rect.midX - size / 2), y: floor(rect.midY - size / 2), width: size, height: size)
    }

    private func drawMailIcon(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let envelope = NSBezierPath(rect: rect.insetBy(dx: 1.5, dy: 4.0))
        envelope.lineWidth = 1.35
        envelope.stroke()

        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + 3, y: rect.minY + 7))
        path.line(to: NSPoint(x: rect.midX, y: rect.midY + 2))
        path.line(to: NSPoint(x: rect.maxX - 3, y: rect.minY + 7))
        path.move(to: NSPoint(x: rect.minX + 3, y: rect.maxY - 5))
        path.line(to: NSPoint(x: rect.midX - 1, y: rect.midY + 1))
        path.move(to: NSPoint(x: rect.maxX - 3, y: rect.maxY - 5))
        path.line(to: NSPoint(x: rect.midX + 1, y: rect.midY + 1))
        path.lineWidth = 1.25
        path.stroke()
    }

    private func drawContactsIcon(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let head = NSBezierPath(ovalIn: NSRect(x: rect.midX - 4.5, y: rect.minY + 3, width: 9, height: 9))
        head.lineWidth = 1.35
        head.stroke()

        let shoulders = NSBezierPath()
        shoulders.move(to: NSPoint(x: rect.minX + 5, y: rect.maxY - 5))
        shoulders.curve(
            to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 5),
            controlPoint1: NSPoint(x: rect.minX + 7, y: rect.midY + 1),
            controlPoint2: NSPoint(x: rect.maxX - 7, y: rect.midY + 1)
        )
        shoulders.lineWidth = 1.35
        shoulders.stroke()
    }

    private func drawCheckIcon(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + 4, y: rect.midY + 1))
        path.line(to: NSPoint(x: rect.midX - 1, y: rect.maxY - 5))
        path.line(to: NSPoint(x: rect.maxX - 4, y: rect.minY + 5))
        path.lineWidth = 2.4
        path.stroke()
    }

    private func drawMiniMonth(layout: Layout) {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")

        let rect = layout.miniMonthRect
        drawText(formatter.string(from: displayedMonth), in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 28), font: windowsUIFont(size: 18), color: .white, alignment: .left)

        let weekdayLabels = weekdaySymbols()
        let cellWidth = floor(rect.width / 7)
        let cellHeight: CGFloat = 28
        for index in 0..<7 {
            drawText(weekdayLabels[index], in: NSRect(x: rect.minX + CGFloat(index) * cellWidth, y: rect.minY + 42, width: cellWidth, height: 22), font: windowsUIFont(size: 13, weight: .semibold), color: .white, alignment: .center)
        }

        for cell in dayCells {
            let column = cell.index % 7
            let row = cell.index / 7
            let cellRect = NSRect(x: rect.minX + CGFloat(column) * cellWidth, y: rect.minY + 72 + CGFloat(row) * cellHeight, width: cellWidth, height: cellHeight)
            let selectionRect = NSRect(x: floor(cellRect.midX - 14), y: floor(cellRect.midY - 12), width: 28, height: 24)
            if calendar.isDate(cell.date, inSameDayAs: selectedDate) {
                fill(selectionRect, color: accentColor)
            }
            drawCenteredText(dayLabel(for: cell.date), in: selectionRect, font: windowsUIFont(size: 14, weight: .regular), color: .white, alignment: .center)
        }
    }

    private func drawCommandBar(layout: Layout) {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let title = viewMode == .year ? "\(calendar.component(.year, from: displayedMonth))" : formatter.string(from: displayedMonth)

        drawArrow(in: layout.previousRect, up: true, target: .previous)
        drawArrow(in: layout.nextRect, up: false, target: .next)
        drawText(title, in: layout.monthTitleRect, font: windowsUIFont(size: 31, weight: .light), color: accentColor, alignment: .left)

        drawCommand(title: L10n.text("day"), rect: layout.dayModeRect, target: .dayMode, icon: .day, selected: viewMode == .day)
        drawCommand(title: L10n.text("week"), rect: layout.weekModeRect, target: .weekMode, icon: .week, selected: viewMode == .week)
        drawCommand(title: L10n.text("month"), rect: layout.monthModeRect, target: .monthMode, icon: .month, selected: viewMode == .month)
        drawCommand(title: L10n.text("year"), rect: layout.yearModeRect, target: .yearMode, icon: .year, selected: viewMode == .year)
    }

    private func drawWeekdays(layout: Layout) {
        let labels = weekdaySymbols()
        for index in 0..<7 {
            let rect = NSRect(x: layout.gridRect.minX + CGFloat(index) * layout.cellSize.width, y: layout.weekdayRect.minY, width: layout.cellSize.width, height: layout.weekdayRect.height)
            drawText(labels[index], in: rect.insetBy(dx: 12, dy: 6), font: windowsUIFont(size: 16, weight: .semibold), color: textColor, alignment: .left)
        }
    }

    private func drawMonthGrid(layout: Layout) {
        for row in 0...6 {
            let y = layout.gridRect.minY + CGFloat(row) * layout.cellSize.height
            drawLine(from: NSPoint(x: layout.gridRect.minX, y: y), to: NSPoint(x: layout.gridRect.maxX, y: y), color: gridLineColor, lineWidth: 1)
        }

        for column in 0...7 {
            let x = layout.gridRect.minX + CGFloat(column) * layout.cellSize.width
            drawLine(from: NSPoint(x: x, y: layout.gridRect.minY), to: NSPoint(x: x, y: layout.gridRect.maxY), color: gridLineColor, lineWidth: 1)
        }

        for cell in dayCells {
            drawFullDayCell(cell)
        }

        if let eventStatusMessage {
            drawText(eventStatusMessage, in: NSRect(x: layout.gridRect.minX + 24, y: layout.gridRect.maxY - 42, width: layout.gridRect.width - 48, height: 24), font: windowsUIFont(size: 13), color: secondaryTextColor, alignment: .left)
        }
    }

    private func drawDayView(layout: Layout) {
        let dayTitle = dayHeaderTitle(for: selectedDate)
        drawText(dayTitle, in: layout.weekdayRect.insetBy(dx: 18, dy: 6), font: windowsUIFont(size: 18, weight: .semibold), color: textColor, alignment: .left)
        drawTimeGrid(in: layout.gridRect, days: [selectedDate])
    }

    private func drawWeekView(layout: Layout) {
        let start = startOfWeek(for: selectedDate)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let width = floor(layout.gridRect.width / 7)
        let labels = weekdaySymbols()

        drawLine(from: NSPoint(x: layout.gridRect.minX, y: layout.gridRect.minY), to: NSPoint(x: layout.gridRect.maxX, y: layout.gridRect.minY), color: gridLineColor, lineWidth: 1)
        drawLine(from: NSPoint(x: layout.gridRect.minX, y: layout.gridRect.maxY), to: NSPoint(x: layout.gridRect.maxX, y: layout.gridRect.maxY), color: gridLineColor, lineWidth: 1)

        for (index, date) in days.enumerated() {
            let dayStart = calendar.startOfDay(for: date)
            let rect = NSRect(x: layout.gridRect.minX + CGFloat(index) * width, y: layout.weekdayRect.minY, width: width, height: layout.weekdayRect.height)
            let label = "\(labels[index])  \(calendar.component(.day, from: date))"
            let columnRect = NSRect(x: layout.gridRect.minX + CGFloat(index) * width, y: layout.gridRect.minY, width: width, height: layout.gridRect.height)
            let isSelected = calendar.isDate(dayStart, inSameDayAs: selectedDate)

            weekDayHitRegions.append(DateHitRegion(rect: columnRect, date: dayStart))
            if hoveredTarget == .weekDay(dayStart), let mousePoint {
                drawReveal(in: columnRect, at: mousePoint)
            }
            if isSelected {
                fill(NSRect(x: columnRect.minX, y: columnRect.minY, width: columnRect.width, height: 3), color: accentColor)
            }

            drawText(label, in: rect.insetBy(dx: 12, dy: 6), font: windowsUIFont(size: 16, weight: .semibold), color: textColor, alignment: .left)
            drawLine(from: NSPoint(x: columnRect.minX, y: columnRect.minY), to: NSPoint(x: columnRect.minX, y: columnRect.maxY), color: gridLineColor, lineWidth: 1)

            drawWeekDayEvents(eventsByDay[dayStart] ?? [], in: columnRect, date: dayStart)
        }

        drawLine(from: NSPoint(x: layout.gridRect.maxX, y: layout.gridRect.minY), to: NSPoint(x: layout.gridRect.maxX, y: layout.gridRect.maxY), color: gridLineColor, lineWidth: 1)
    }

    private func drawWeekDayEvents(_ events: [CalendarEventSummary], in rect: NSRect, date: Date) {
        let timeFormatter = AppSettings.shared.makeTimeFormatter()
        let addRect = NSRect(x: rect.minX + 10, y: rect.minY + 12, width: rect.width - 20, height: 30)
        stroke(addRect, color: gridLineColor.withAlpha(0.90), lineWidth: 1)
        drawText("+  \(L10n.text("newEvent"))", in: addRect.insetBy(dx: 8, dy: 6), font: windowsUIFont(size: 13, weight: .semibold), color: secondaryTextColor, alignment: .left)

        if events.isEmpty {
            drawText(L10n.text("noEvents"), in: NSRect(x: rect.minX + 12, y: addRect.maxY + 16, width: rect.width - 24, height: 22), font: windowsUIFont(size: 13), color: secondaryTextColor, alignment: .left)
            return
        }

        var y = addRect.maxY + 12
        for event in events.prefix(8) {
            guard y + 48 < rect.maxY - 10 else { break }
            let eventRect = NSRect(x: rect.minX + 10, y: y, width: rect.width - 20, height: 46)
            let hitIndex = eventHitRegions.count
            eventHitRegions.append(EventHitRegion(rect: eventRect, event: event))
            if hoveredTarget == .event(hitIndex), let mousePoint {
                drawReveal(in: eventRect, at: mousePoint)
            }
            fill(NSRect(x: eventRect.minX, y: eventRect.minY + 5, width: 4, height: eventRect.height - 10), color: event.color)
            let timeText = event.isAllDay ? L10n.text("allDay") : timeFormatter.string(from: event.startDate)
            drawText(timeText, in: NSRect(x: eventRect.minX + 12, y: eventRect.minY + 3, width: eventRect.width - 18, height: 18), font: windowsUIFont(size: 11), color: secondaryTextColor, alignment: .left)
            drawText(event.title, in: NSRect(x: eventRect.minX + 12, y: eventRect.minY + 22, width: eventRect.width - 18, height: 20), font: windowsUIFont(size: 13, weight: .semibold), color: textColor, alignment: .left)
            y += 52
        }

        if events.count > 8 {
            drawText("+ \(events.count - 8) \(L10n.text("more"))", in: NSRect(x: rect.minX + 12, y: rect.maxY - 30, width: rect.width - 24, height: 20), font: windowsUIFont(size: 12, weight: .semibold), color: accentColor, alignment: .left)
        }
    }

    private func drawTimeGrid(in rect: NSRect, days: [Date]) {
        let labelWidth: CGFloat = AppSettings.shared.usesTwelveHourClock ? 76 : 58
        let gridRect = NSRect(x: rect.minX + labelWidth, y: rect.minY, width: rect.width - labelWidth, height: rect.height)
        let hourCount = 24
        let rowHeight = gridRect.height / CGFloat(hourCount)
        let columnWidth = floor(gridRect.width / CGFloat(days.count))

        for row in 0...hourCount {
            let y = gridRect.minY + CGFloat(row) * rowHeight
            drawLine(from: NSPoint(x: rect.minX, y: y), to: NSPoint(x: rect.maxX, y: y), color: gridLineColor, lineWidth: 1)
            if row < hourCount {
                drawText(hourLabel(for: row, on: selectedDate), in: NSRect(x: rect.minX + 8, y: y + 5, width: labelWidth - 14, height: 22), font: windowsUIFont(size: 13), color: textColor, alignment: .right)
            }
        }

        for column in 0...days.count {
            let x = gridRect.minX + CGFloat(column) * columnWidth
            drawLine(from: NSPoint(x: x, y: gridRect.minY), to: NSPoint(x: x, y: gridRect.maxY), color: gridLineColor, lineWidth: 1)
        }

        for (column, day) in days.enumerated() {
            let dayStart = calendar.startOfDay(for: day)
            let events = eventsByDay[dayStart] ?? []
            let columnRect = NSRect(x: gridRect.minX + CGFloat(column) * columnWidth, y: gridRect.minY, width: columnWidth, height: gridRect.height)
            drawTimedEvents(events, in: columnRect, day: day, rowHeight: rowHeight)
        }
    }

    private func hourLabel(for hour: Int, on date: Date) -> String {
        guard let labelDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) else {
            return String(format: "%02d", hour)
        }

        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        formatter.dateFormat = AppSettings.shared.usesTwelveHourClock ? "h a" : "HH"
        return formatter.string(from: labelDate)
    }

    private func drawTimedEvents(_ events: [CalendarEventSummary], in rect: NSRect, day: Date, rowHeight: CGFloat) {
        let limit = 18
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 3600)
        let timeFormatter = AppSettings.shared.makeTimeFormatter()
        let sortedEvents = events.sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay && !rhs.isAllDay }
            if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        for (visibleIndex, event) in sortedEvents.prefix(limit).enumerated() {
            let eventRect: NSRect

            if event.isAllDay {
                let allDayIndex = CGFloat(visibleIndex)
                let y = rect.minY + 4 + min(allDayIndex, 2) * 23
                eventRect = NSRect(x: rect.minX + 6, y: y, width: rect.width - 12, height: 20)
            } else {
                let visibleStart = Swift.max(event.startDate, dayStart)
                let visibleEnd = Swift.min(event.endDate, dayEnd)
                let startComponents = calendar.dateComponents([.hour, .minute], from: visibleStart)
                let startMinutes = CGFloat((startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0))
                let durationMinutes = max(30, visibleEnd.timeIntervalSince(visibleStart) / 60.0)
                let y = rect.minY + (startMinutes / 60.0) * rowHeight
                let height = max(22, CGFloat(durationMinutes / 60.0) * rowHeight)
                eventRect = NSRect(x: rect.minX + 6, y: y + 3, width: rect.width - 12, height: min(height, rect.maxY - y - 5))
            }

            guard eventRect.height > 12 else { continue }
            let hitIndex = eventHitRegions.count
            eventHitRegions.append(EventHitRegion(rect: eventRect, event: event))
            fill(eventRect, color: event.color.withAlpha(0.86))
            if hoveredTarget == .event(hitIndex) {
                stroke(eventRect.insetBy(dx: 0.5, dy: 0.5), color: NSColor.white.withAlpha(0.82), lineWidth: 1)
            }

            if eventRect.height >= 46, rect.width >= 132 {
                drawText(event.title, in: NSRect(x: eventRect.minX + 7, y: eventRect.minY + 4, width: eventRect.width - 14, height: 20), font: windowsUIFont(size: 13, weight: .semibold), color: .white, alignment: .left)
                let timeText = event.isAllDay ? L10n.text("allDay") : "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
                drawText(timeText, in: NSRect(x: eventRect.minX + 7, y: eventRect.minY + 24, width: eventRect.width - 14, height: 18), font: windowsUIFont(size: 11), color: NSColor.white.withAlpha(0.88), alignment: .left)
                if eventRect.height >= 66, let location = event.location {
                    drawText(location, in: NSRect(x: eventRect.minX + 7, y: eventRect.minY + 42, width: eventRect.width - 14, height: 18), font: windowsUIFont(size: 11), color: NSColor.white.withAlpha(0.78), alignment: .left)
                }
            } else {
                drawText(event.title, in: eventRect.insetBy(dx: 7, dy: 3), font: windowsUIFont(size: 12, weight: .semibold), color: .white, alignment: .left)
            }
        }

        if sortedEvents.count > limit {
            let moreRect = NSRect(x: rect.minX + 6, y: rect.maxY - 26, width: rect.width - 12, height: 20)
            fill(moreRect, color: accentColor.withAlpha(0.72))
            drawText("+ \(sortedEvents.count - limit) \(L10n.text("more"))", in: moreRect.insetBy(dx: 7, dy: 2), font: windowsUIFont(size: 12, weight: .semibold), color: .white, alignment: .left)
        }
    }

    private func drawYearView(layout: Layout) {
        let year = calendar.component(.year, from: displayedMonth)
        let isCompact = layout.commandRect.width < 880
        let horizontalInset: CGFloat = isCompact ? 34 : 80
        let verticalInset: CGFloat = isCompact ? 24 : 56
        let contentRect = NSRect(
            x: layout.commandRect.minX + horizontalInset,
            y: layout.commandRect.maxY + verticalInset,
            width: max(0, layout.commandRect.width - horizontalInset * 2),
            height: max(0, bounds.height - layout.commandRect.maxY - verticalInset - (isCompact ? 24 : 36))
        )
        let columnCount: Int
        if contentRect.width < 520 {
            columnCount = 3
        } else if contentRect.width < 980 {
            columnCount = 4
        } else {
            columnCount = 6
        }
        let rowCount = Int(ceil(12.0 / Double(columnCount)))
        let monthWidth = floor(contentRect.width / CGFloat(columnCount))
        let monthHeight = floor(contentRect.height / CGFloat(rowCount))
        let monthGap: CGFloat = isCompact ? 18 : 24

        for month in 1...12 {
            var components = DateComponents()
            components.calendar = calendar
            components.year = year
            components.month = month
            components.day = 1
            guard let monthDate = calendar.date(from: components) else { continue }
            let index = month - 1
            let rect = NSRect(
                x: contentRect.minX + CGFloat(index % columnCount) * monthWidth,
                y: contentRect.minY + CGFloat(index / columnCount) * monthHeight,
                width: max(70, monthWidth - monthGap),
                height: max(82, monthHeight - monthGap)
            )
            drawYearMonth(monthDate, in: rect)
        }
    }

    private func drawYearMonth(_ monthDate: Date, in rect: NSRect) {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        let titleHeight = min(30, max(21, rect.height * 0.14))
        let weekdayY = rect.minY + titleHeight + 7
        let weekdayHeight = min(20, max(14, rect.height * 0.09))
        let dayGridY = weekdayY + weekdayHeight + 5
        let titleRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: titleHeight)
        yearMonthHitRegions.append(DateHitRegion(rect: titleRect, date: monthDate))
        if hoveredTarget == .yearMonth(monthDate), let mousePoint {
            drawReveal(in: titleRect, at: mousePoint)
        }
        drawText(formatter.string(from: monthDate), in: titleRect, font: windowsUIFont(size: min(22, max(16, rect.width / 7.0)), weight: .semibold), color: textColor, alignment: .left)

        let labels = compactWeekdaySymbols()
        let cellWidth = floor(rect.width / 7)
        let cellHeight = max(8, min(28, floor((rect.maxY - dayGridY) / 6)))
        for index in 0..<7 {
            drawText(labels[index], in: NSRect(x: rect.minX + CGFloat(index) * cellWidth, y: weekdayY, width: cellWidth, height: weekdayHeight), font: windowsUIFont(size: min(13, max(9, cellWidth * 0.48)), weight: .semibold), color: textColor, alignment: .center)
        }

        let weekday = calendar.component(.weekday, from: monthDate)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        for day in 1...dayCount {
            let index = leadingDays + day - 1
            let cell = NSRect(x: rect.minX + CGFloat(index % 7) * cellWidth, y: dayGridY + CGFloat(index / 7) * cellHeight, width: cellWidth, height: cellHeight)
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthDate) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            yearDayHitRegions.append(DateHitRegion(rect: cell, date: dayStart))
            if hoveredTarget == .yearDay(dayStart), let mousePoint {
                drawReveal(in: cell, at: mousePoint)
            }
            if calendar.component(.year, from: selectedDate) == calendar.component(.year, from: monthDate), calendar.component(.month, from: selectedDate) == calendar.component(.month, from: monthDate), calendar.component(.day, from: selectedDate) == day {
                fill(cell.insetBy(dx: max(1, cellWidth * 0.18), dy: 1), color: accentColor)
            }
            let hasEvents = !(eventsByDay[dayStart] ?? []).isEmpty
            let dayColor: NSColor = hasEvents ? (isDarkMode ? NSColor.white : NSColor.black.withAlpha(0.95)) : textColor
            let fontSize = min(16, max(9, min(cellWidth * 0.58, cellHeight * 0.72)))
            drawText("\(day)", in: cell, font: windowsUIFont(size: fontSize, weight: hasEvents ? .semibold : .regular), color: dayColor, alignment: .center)
        }
    }

    private func drawFullDayCell(_ cell: DayCell) {
        let isSelected = calendar.isDate(cell.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(cell.date)
        let isHovered = hoveredTarget == .day(cell.index)

        if isSelected {
            fill(cell.rect.insetBy(dx: 0, dy: 0), color: accentColor.withAlpha(0.92))
        } else if isHovered, let mousePoint {
            drawReveal(in: cell.rect, at: mousePoint)
        }

        if isToday {
            stroke(cell.rect.insetBy(dx: 4, dy: 4), color: accentColor, lineWidth: 2)
        }

        let color: NSColor = isSelected ? .white : textColor
        drawText(dayLabel(for: cell.date), in: NSRect(x: cell.rect.minX + 12, y: cell.rect.minY + 12, width: cell.rect.width - 24, height: 28), font: windowsUIFont(size: 22, weight: .regular), color: color, alignment: .left)

        let key = calendar.startOfDay(for: cell.date)
        guard let events = eventsByDay[key], !events.isEmpty else { return }

        var y = cell.rect.minY + 48
        for event in events.prefix(3) {
            guard y + 20 < cell.rect.maxY - 8 else { break }
            let eventRect = NSRect(x: cell.rect.minX + 12, y: y, width: cell.rect.width - 24, height: 22)
            let hitIndex = eventHitRegions.count
            eventHitRegions.append(EventHitRegion(rect: eventRect, event: event))
            if hoveredTarget == .event(hitIndex), let mousePoint {
                drawReveal(in: eventRect, at: mousePoint)
            }
            fill(NSRect(x: cell.rect.minX + 12, y: y + 5, width: 4, height: 12), color: isSelected ? .white : event.color)
            drawText(event.title, in: NSRect(x: cell.rect.minX + 22, y: y, width: cell.rect.width - 34, height: 22), font: windowsUIFont(size: 13), color: isSelected ? .white : textColor, alignment: .left)
            y += 22
        }
    }

    private enum CommandIcon {
        case today
        case day
        case week
        case month
        case year
    }

    private func drawCommand(title: String, rect: NSRect, target: HitTarget?, icon: CommandIcon, selected: Bool = false) {
        if let target, hoveredTarget == target, let mousePoint {
            drawReveal(in: rect, at: mousePoint)
        }
        if selected {
            fill(NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 3), color: accentColor)
        }
        let iconRect = NSRect(x: rect.minX + 8, y: rect.midY - 11, width: 22, height: 22)
        drawCalendarIcon(in: iconRect, color: textColor, grid: icon != .day && icon != .today, arrow: icon == .today)
        drawText(title, in: NSRect(x: iconRect.maxX + 5, y: rect.minY + 10, width: rect.width - 34, height: 24), font: windowsUIFont(size: 16), color: textColor, alignment: .left)
    }

    private func drawCommandText(title: String, rect: NSRect, target: HitTarget) {
        if hoveredTarget == target, let mousePoint {
            drawReveal(in: rect, at: mousePoint)
        }
        drawText(title, in: rect.insetBy(dx: 8, dy: 10), font: windowsUIFont(size: 16), color: textColor, alignment: .center)
    }

    private func drawArrow(in rect: NSRect, up: Bool, target: HitTarget) {
        if hoveredTarget == target, let mousePoint {
            drawReveal(in: rect, at: mousePoint)
        }
        drawText(up ? "↑" : "↓", in: rect.insetBy(dx: 4, dy: 2), font: windowsUIFont(size: 35, weight: .light), color: secondaryTextColor, alignment: .center)
    }

    private func drawNoise(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let light = NSColor.white.withAlpha(isDarkMode ? 0.035 : 0.07).cgColor
        let dark = NSColor.black.withAlpha(isDarkMode ? 0.08 : 0.04).cgColor
        let minX = Int(rect.minX)
        let maxX = Int(rect.maxX)
        let minY = Int(rect.minY)
        let maxY = Int(rect.maxY)

        for y in stride(from: minY, through: maxY, by: 4) {
            for x in stride(from: minX, through: maxX, by: 4) {
                let hash = abs((x &* 73_856_093) ^ (y &* 19_349_663)) & 0xFF
                if hash < 16 {
                    context.setFillColor(hash.isMultiple(of: 2) ? light : dark)
                    context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 1, height: 1))
                }
            }
        }
    }

    private func drawHamburger(in rect: NSRect, color: NSColor) {
        color.setStroke()
        for offset in [-6.0, 0.0, 6.0] {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX - 8, y: rect.midY + CGFloat(offset)))
            path.line(to: NSPoint(x: rect.midX + 8, y: rect.midY + CGFloat(offset)))
            path.lineWidth = 2
            path.stroke()
        }
    }

    private func drawCalendarIcon(in rect: NSRect, color: NSColor, grid: Bool, arrow: Bool) {
        color.setStroke()
        let path = NSBezierPath(rect: rect.insetBy(dx: 1.5, dy: 2.5))
        path.lineWidth = 1.4
        path.stroke()

        drawLine(from: NSPoint(x: rect.minX + 2, y: rect.minY + 7), to: NSPoint(x: rect.maxX - 2, y: rect.minY + 7), color: color, lineWidth: 1.2)
        drawLine(from: NSPoint(x: rect.minX + 6, y: rect.minY), to: NSPoint(x: rect.minX + 6, y: rect.minY + 5), color: color, lineWidth: 1.6)
        drawLine(from: NSPoint(x: rect.maxX - 6, y: rect.minY), to: NSPoint(x: rect.maxX - 6, y: rect.minY + 5), color: color, lineWidth: 1.6)

        if grid {
            for x in stride(from: rect.minX + 6, through: rect.maxX - 6, by: 5) {
                drawLine(from: NSPoint(x: x, y: rect.minY + 10), to: NSPoint(x: x, y: rect.maxY - 4), color: color.withAlpha(0.65), lineWidth: 0.8)
            }
            for y in stride(from: rect.minY + 12, through: rect.maxY - 5, by: 4) {
                drawLine(from: NSPoint(x: rect.minX + 4, y: y), to: NSPoint(x: rect.maxX - 4, y: y), color: color.withAlpha(0.65), lineWidth: 0.8)
            }
        }

        if arrow {
            let arrowPath = NSBezierPath()
            arrowPath.move(to: NSPoint(x: rect.midX + 5, y: rect.midY - 3))
            arrowPath.line(to: NSPoint(x: rect.midX - 2, y: rect.midY - 3))
            arrowPath.line(to: NSPoint(x: rect.midX + 1, y: rect.midY - 6))
            arrowPath.move(to: NSPoint(x: rect.midX - 2, y: rect.midY - 3))
            arrowPath.line(to: NSPoint(x: rect.midX + 1, y: rect.midY))
            arrowPath.lineWidth = 1.2
            arrowPath.stroke()
        }
    }

    private func drawGear(in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4
            let point = NSPoint(x: center.x + cos(angle) * rect.width * 0.42, y: center.y + sin(angle) * rect.height * 0.42)
            NSBezierPath(rect: NSRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)).fill()
        }
        let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
        outer.lineWidth = 1.3
        outer.stroke()
        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 9, dy: 9))
        inner.lineWidth = 1.2
        inner.stroke()
    }

    private func weekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        let symbols = formatter.shortStandaloneWeekdaySymbols ?? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset..<symbols.count]) + Array(symbols[0..<offset])
    }

    private func compactWeekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.shortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset..<symbols.count]) + Array(symbols[0..<offset])
    }

    private func startOfWeek(for date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let leadingDays = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -leadingDays, to: date) ?? date
        return calendar.startOfDay(for: start)
    }

    private func dayHeaderTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        formatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return formatter.string(from: date)
    }

    private func dayLabel(for date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }

    private func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.component(.year, from: lhs) == calendar.component(.year, from: rhs)
            && calendar.component(.month, from: lhs) == calendar.component(.month, from: rhs)
    }

    private func drawReveal(in rect: NSRect, at point: NSPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: rect)

        let radius = max(rect.width, rect.height) * 1.45
        let colors = [
            (isDarkMode ? NSColor.white.withAlpha(0.16) : NSColor(red: 0.08, green: 0.55, blue: 1.0, alpha: 0.20)).cgColor,
            (isDarkMode ? accentColor.withAlpha(0.09) : NSColor(red: 0.0, green: 0.47, blue: 0.92, alpha: 0.14)).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0, 0.40, 1]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawRadialGradient(gradient, startCenter: point, startRadius: 0, endCenter: point, endRadius: radius, options: [.drawsAfterEndLocation])
        }

        drawRevealEdges(in: rect.insetBy(dx: 0.5, dy: 0.5), at: point, radius: radius)
        context.restoreGState()
    }

    private func drawRevealEdges(in rect: NSRect, at point: NSPoint, radius: CGFloat) {
        let segmentLength: CGFloat = 10
        let color = isDarkMode ? NSColor.white : NSColor(red: 0.0, green: 0.47, blue: 0.92, alpha: 1.0)

        func drawSegment(from start: NSPoint, to end: NSPoint) {
            let mid = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let distance = hypot(mid.x - point.x, mid.y - point.y)
            let intensity = max(0, 1 - distance / radius)
            guard intensity > 0.02 else { return }

            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = 1.4
            color.withAlpha((isDarkMode ? 0.78 : 0.70) * intensity * intensity).setStroke()
            path.stroke()
        }

        var x = rect.minX
        while x < rect.maxX {
            let nextX = min(x + segmentLength, rect.maxX)
            drawSegment(from: NSPoint(x: x, y: rect.minY), to: NSPoint(x: nextX, y: rect.minY))
            drawSegment(from: NSPoint(x: x, y: rect.maxY), to: NSPoint(x: nextX, y: rect.maxY))
            x = nextX
        }

        var y = rect.minY
        while y < rect.maxY {
            let nextY = min(y + segmentLength, rect.maxY)
            drawSegment(from: NSPoint(x: rect.minX, y: y), to: NSPoint(x: rect.minX, y: nextY))
            drawSegment(from: NSPoint(x: rect.maxX, y: y), to: NSPoint(x: rect.maxX, y: nextY))
            y = nextY
        }
    }

    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func drawCenteredText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let drawRect = NSRect(x: rect.minX, y: rect.minY + floor((rect.height - size.height) / 2), width: rect.width, height: ceil(size.height) + 2)
        (text as NSString).draw(in: drawRect, withAttributes: attributes)
    }

    private func drawLine(from start: NSPoint, to end: NSPoint, color: NSColor, lineWidth: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }
}

private final class DayDetailsPopoverController: NSViewController {
    private let date: Date
    private let events: [CalendarEventSummary]
    private let onAdd: () -> Void
    private let onOpenEvent: (CalendarEventSummary) -> Void

    init(date: Date, events: [CalendarEventSummary], onAdd: @escaping () -> Void, onOpenEvent: @escaping (CalendarEventSummary) -> Void) {
        self.date = date
        self.events = events
        self.onAdd = onAdd
        self.onOpenEvent = onOpenEvent
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let height = CGFloat(events.isEmpty ? 154 : min(330, 106 + events.count * 54))
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: height))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = root

        let titleFormatter = DateFormatter()
        titleFormatter.locale = AppSettings.shared.localizedLocale
        titleFormatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")

        let title = NSTextField(labelWithString: titleFormatter.string(from: date))
        title.frame = NSRect(x: 18, y: height - 40, width: 284, height: 24)
        title.font = windowsUIFont(size: 17, weight: .semibold)
        title.textColor = .labelColor
        root.addSubview(title)

        let addButton = NSButton(title: events.isEmpty ? L10n.text("newEvent") : L10n.text("addAnotherEvent"), target: self, action: #selector(addPressed))
        addButton.frame = NSRect(x: 18, y: 16, width: 190, height: 30)
        addButton.bezelStyle = .regularSquare
        addButton.font = windowsUIFont(size: 14, weight: .regular)
        root.addSubview(addButton)

        if events.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: L10n.text("noEventsForDay"))
            empty.frame = NSRect(x: 18, y: 64, width: 284, height: 40)
            empty.font = windowsUIFont(size: 14, weight: .regular)
            empty.textColor = .secondaryLabelColor
            root.addSubview(empty)
            return
        }

        let timeFormatter = AppSettings.shared.makeTimeFormatter()
        var y = height - 86
        for (index, event) in events.prefix(4).enumerated() {
            let colorView = NSView(frame: NSRect(x: 18, y: y + 6, width: 4, height: 36))
            colorView.wantsLayer = true
            colorView.layer?.backgroundColor = event.color.cgColor
            root.addSubview(colorView)

            let eventTitle = NSTextField(labelWithString: event.title)
            eventTitle.frame = NSRect(x: 32, y: y + 22, width: 270, height: 20)
            eventTitle.font = windowsUIFont(size: 14, weight: .semibold)
            eventTitle.textColor = .labelColor
            root.addSubview(eventTitle)

            let timeText = event.isAllDay ? L10n.text("allDay") : "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
            let time = NSTextField(labelWithString: timeText)
            time.frame = NSRect(x: 32, y: y + 4, width: 270, height: 18)
            time.font = windowsUIFont(size: 12, weight: .regular)
            time.textColor = .secondaryLabelColor
            root.addSubview(time)

            let button = NSButton(frame: NSRect(x: 12, y: y, width: 296, height: 48))
            button.title = ""
            button.isBordered = false
            button.target = self
            button.action = #selector(eventPressed(_:))
            button.tag = index
            root.addSubview(button)

            y -= 54
        }

        if events.count > 4 {
            let more = NSTextField(labelWithString: "+ \(events.count - 4) more")
            more.frame = NSRect(x: 32, y: max(54, y + 20), width: 270, height: 18)
            more.font = windowsUIFont(size: 12, weight: .regular)
            more.textColor = .secondaryLabelColor
            root.addSubview(more)
        }
    }

    @objc private func addPressed() {
        onAdd()
    }

    @objc private func eventPressed(_ sender: NSButton) {
        guard events.indices.contains(sender.tag) else { return }
        onOpenEvent(events[sender.tag])
    }
}
