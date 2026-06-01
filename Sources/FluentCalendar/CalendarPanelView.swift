import AppKit

private final class CalendarHeaderDateView: NSView {
    override var isFlipped: Bool { true }

    var date = Date() {
        didSet { needsDisplay = true }
    }

    var isHovered = false {
        didSet { needsDisplay = true }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let formatter = AppSettings.shared.makeHeaderDateFormatter()
        let color = isHovered ? NSColor.white.withAlpha(0.98) : NSColor(red: 0.74, green: 0.89, blue: 1.0, alpha: 1.0)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlpha(0.36)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: windowsUIFont(size: 20, weight: .light),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]

        (formatter.string(from: date) as NSString).draw(in: bounds, withAttributes: attributes)
    }
}

final class CalendarPanelView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private struct Layout {
        let sideInset: CGFloat
        let dividerY: CGFloat
        let clockDateRect: NSRect
        let monthHeaderRect: NSRect
        let weekdayRect: NSRect
        let gridRect: NSRect
        let cellSize: NSSize
        let agendaRect: NSRect
        let todayButtonRect: NSRect
        let previousButtonRect: NSRect
        let nextButtonRect: NSRect
        let settingsButtonRect: NSRect
        let addEventRect: NSRect
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

    private enum HitTarget: Equatable {
        case day(Int)
        case today
        case previousMonth
        case nextMonth
        case settings
        case clockDate
        case addEvent
        case event(Int)
    }

    private let eventService: EventKitCalendarService
    private let onOpenSettings: () -> Void
    private var calendar = CalendarPanelView.makeWindowsCalendar()
    private var displayedMonth: Date
    private var selectedDate: Date
    private var now = Date()
    private var dayCells: [DayCell] = []
    private var eventsByDay: [Date: [CalendarEventSummary]] = [:]
    private var selectedDayEvents: [CalendarEventSummary] = []
    private var eventHitRegions: [EventHitRegion] = []
    private var eventStatusMessage: String?
    private var hoveredTarget: HitTarget?
    private var mousePoint: NSPoint?
    private var scrollAccumulator: CGFloat = 0
    private let headerDateView = CalendarHeaderDateView(frame: .zero)
    private lazy var quickEventEditor: QuickEventEditorView = makeQuickEventEditor()

    init(frame frameRect: NSRect, eventService: EventKitCalendarService, onOpenSettings: @escaping () -> Void) {
        self.eventService = eventService
        self.onOpenSettings = onOpenSettings
        let today = Date()
        self.selectedDate = calendar.startOfDay(for: today)
        self.displayedMonth = CalendarPanelView.startOfMonth(for: today, calendar: calendar)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 0
        addSubview(quickEventEditor)
        addSubview(headerDateView)

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

    func refreshClock() {
        now = Date()
        headerDateView.date = now
        needsDisplay = true
    }

    func reloadEvents() {
        eventStatusMessage = "Loading events..."
        updateSelectedEvents()
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

            self.updateSelectedEvents()
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

    override func layout() {
        super.layout()
        let layout = makeLayout()
        headerDateView.frame = layout.clockDateRect
        headerDateView.date = now
        let editorY = layout.agendaRect.minY + 64
        quickEventEditor.frame = NSRect(
            x: 0,
            y: editorY,
            width: bounds.width,
            height: min(248, max(0, bounds.height - editorY))
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let layout = makeLayout()
        headerDateView.frame = layout.clockDateRect
        headerDateView.date = now
        eventHitRegions.removeAll()
        dayCells = makeDayCells(layout: layout)

        drawClock(layout: layout)
        drawDivider(y: layout.dividerY)
        drawMonthHeader(layout: layout)
        drawWeekdayHeader(layout: layout)
        drawCalendarGrid(layout: layout)
        drawAgenda(layout: layout)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mousePoint = point
        hoveredTarget = hitTarget(at: point)
        headerDateView.isHovered = hoveredTarget == .clockDate
        if hoveredTarget == .clockDate || hoveredTarget == .addEvent || isEventTarget(hoveredTarget) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mousePoint = nil
        hoveredTarget = nil
        headerDateView.isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let target = hitTarget(at: point) else { return }

        switch target {
        case .day(let index):
            guard let cell = dayCells.first(where: { $0.index == index }) else { return }
            selectedDate = calendar.startOfDay(for: cell.date)
            if !quickEventEditor.isHidden {
                quickEventEditor.configure(for: selectedDate)
            }

            if !isSameMonth(cell.date, displayedMonth) {
                displayedMonth = Self.startOfMonth(for: cell.date, calendar: calendar)
                reloadEvents()
            } else {
                updateSelectedEvents()
                needsDisplay = true
            }
        case .today:
            selectToday()
        case .previousMonth:
            changeDisplayedMonth(by: -1)
        case .nextMonth:
            changeDisplayedMonth(by: 1)
        case .settings:
            onOpenSettings()
        case .clockDate:
            SystemSettingsOpener.openClockSettings()
        case .addEvent:
            showQuickEventEditor()
        case .event(let index):
            guard eventHitRegions.indices.contains(index) else { return }
            EventKitCalendarService.openEventInCalendar(eventHitRegions[index].event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccumulator += event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 36 : 1

        guard abs(scrollAccumulator) >= threshold else { return }

        let direction = scrollAccumulator > 0 ? -1 : 1
        scrollAccumulator = 0
        changeDisplayedMonth(by: direction)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            moveSelectedDate(byDays: -1)
        case 124:
            moveSelectedDate(byDays: 1)
        case 125:
            moveSelectedDate(byDays: 7)
        case 126:
            moveSelectedDate(byDays: -7)
        case 115:
            selectToday()
        case 116:
            changeDisplayedMonth(by: -1)
        case 121:
            changeDisplayedMonth(by: 1)
        default:
            if event.charactersIgnoringModifiers?.lowercased() == "t" {
                selectToday()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc private func settingsChanged() {
        calendar.locale = AppSettings.shared.localizedLocale
        headerDateView.needsDisplay = true
        needsDisplay = true
    }

    @objc private func eventsChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.reloadEvents()
        }
    }

    private func makeQuickEventEditor() -> QuickEventEditorView {
        let editor = QuickEventEditorView(frame: .zero)
        editor.isHidden = true
        editor.onSave = { [weak self] title, location, startDate, endDate, alarmOffsetMinutes in
            self?.createQuickEvent(title: title, location: location, startDate: startDate, endDate: endDate, alarmOffsetMinutes: alarmOffsetMinutes)
        }
        editor.onCancel = { [weak self] in
            self?.quickEventEditor.isHidden = true
            self?.needsDisplay = true
        }
        editor.onMoreDetails = {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        }
        return editor
    }

    private func showQuickEventEditor() {
        quickEventEditor.configure(for: selectedDate)
        quickEventEditor.isHidden = false
        needsLayout = true
        needsDisplay = true
    }

    private func createQuickEvent(title: String, location: String?, startDate: Date, endDate: Date, alarmOffsetMinutes: Int?) {
        eventService.createEvent(title: title, location: location, startDate: startDate, endDate: endDate, alarmOffsetMinutes: alarmOffsetMinutes) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let event):
                self.quickEventEditor.isHidden = true
                self.addOptimisticEvent(event)
                self.reloadEvents()
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Event could not be saved"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func addOptimisticEvent(_ event: CalendarEventSummary) {
        for day in daysCoveredByEvent(event) {
            var events = eventsByDay[day] ?? []
            if !events.contains(where: { $0.identifier == event.identifier }) {
                events.append(event)
            }
            eventsByDay[day] = events.sorted(by: sortEvents)
        }
        updateSelectedEvents()
        needsDisplay = true
    }

    private func daysCoveredByEvent(_ event: CalendarEventSummary) -> [Date] {
        let interval = visibleDateInterval()
        let eventEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
        let inclusiveIntervalEnd = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        var day = calendar.startOfDay(for: max(event.startDate, interval.start))
        let finalDay = calendar.startOfDay(for: min(eventEnd, inclusiveIntervalEnd))
        var days: [Date] = []

        while day <= finalDay {
            days.append(day)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        return days
    }

    private func changeDisplayedMonth(by delta: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) ?? displayedMonth
        normalizeSelectedDateForDisplayedMonth()
        reloadEvents()
    }

    private func moveSelectedDate(byDays days: Int) {
        guard let nextDate = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = calendar.startOfDay(for: nextDate)
        let nextMonth = Self.startOfMonth(for: nextDate, calendar: calendar)

        if !isSameMonth(nextMonth, displayedMonth) {
            displayedMonth = nextMonth
            reloadEvents()
        } else {
            updateSelectedEvents()
            needsDisplay = true
        }
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

    private static func makeWindowsCalendar() -> Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = AppSettings.shared.localizedLocale
        calendar.timeZone = .current
        return calendar
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private func makeLayout() -> Layout {
        let sideInset: CGFloat = 32
        let dividerY: CGFloat = 128
        let monthHeaderY: CGFloat = dividerY + 18
        let monthHeaderRect = NSRect(x: sideInset, y: monthHeaderY, width: bounds.width - sideInset * 2, height: 44)
        let weekdayRect = NSRect(x: sideInset, y: monthHeaderRect.maxY + 16, width: bounds.width - sideInset * 2, height: 26)
        let gridY = weekdayRect.maxY + 6
        let agendaHeight = min(318, max(278, bounds.height * 0.38))
        let cellWidth = floor((bounds.width - sideInset * 2) / 7.0)
        let availableGridHeight = bounds.height - gridY - agendaHeight - 16
        let cellHeight = floor(min(52, max(42, availableGridHeight / 6.0)))
        let gridWidth = cellWidth * 7.0
        let gridRect = NSRect(x: floor((bounds.width - gridWidth) / 2.0), y: gridY, width: gridWidth, height: cellHeight * 6.0)
        let agendaRect = NSRect(x: 0, y: gridRect.maxY + 18, width: bounds.width, height: bounds.height - gridRect.maxY - 18)

        return Layout(
            sideInset: sideInset,
            dividerY: dividerY,
            clockDateRect: NSRect(x: sideInset + 2, y: 92, width: bounds.width - sideInset * 2 - 4, height: 32),
            monthHeaderRect: monthHeaderRect,
            weekdayRect: weekdayRect,
            gridRect: gridRect,
            cellSize: NSSize(width: cellWidth, height: cellHeight),
            agendaRect: agendaRect,
            todayButtonRect: NSRect(x: monthHeaderRect.maxX - 172, y: monthHeaderRect.minY + 5, width: 76, height: 32),
            previousButtonRect: NSRect(x: monthHeaderRect.maxX - 88, y: monthHeaderRect.minY + 4, width: 36, height: 34),
            nextButtonRect: NSRect(x: monthHeaderRect.maxX - 40, y: monthHeaderRect.minY + 4, width: 36, height: 34),
            settingsButtonRect: NSRect(x: bounds.width - 54, y: bounds.height - 54, width: 36, height: 36),
            addEventRect: NSRect(x: sideInset, y: agendaRect.minY + 66, width: bounds.width - sideInset * 2, height: 38)
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
        let start = calendar.startOfDay(for: displayedMonth)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private func daysInDisplayedMonth() -> Int {
        calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30
    }

    private func groupEventsByDay(_ events: [CalendarEventSummary]) -> [Date: [CalendarEventSummary]] {
        var grouped: [Date: [CalendarEventSummary]] = [:]
        let interval = visibleDateInterval()

        for event in events {
            let eventEnd = calendar.date(byAdding: .second, value: -1, to: event.endDate) ?? event.endDate
            let inclusiveIntervalEnd = calendar.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            var day = calendar.startOfDay(for: max(event.startDate, interval.start))
            let finalDay = calendar.startOfDay(for: min(eventEnd, inclusiveIntervalEnd))

            while day <= finalDay {
                grouped[day, default: []].append(event)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = nextDay
            }
        }

        for key in grouped.keys {
            grouped[key]?.sort(by: sortEvents)
        }

        return grouped
    }

    private func sortEvents(_ lhs: CalendarEventSummary, _ rhs: CalendarEventSummary) -> Bool {
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay && !rhs.isAllDay
        }
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func updateSelectedEvents() {
        let key = calendar.startOfDay(for: selectedDate)
        selectedDayEvents = eventsByDay[key]?.sorted(by: sortEvents) ?? []
    }

    private func isSameMonth(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.component(.year, from: lhs) == calendar.component(.year, from: rhs)
            && calendar.component(.month, from: lhs) == calendar.component(.month, from: rhs)
    }

    private func hitTarget(at point: NSPoint) -> HitTarget? {
        let layout = makeLayout()

        if layout.clockDateRect.contains(point) { return .clockDate }
        if layout.todayButtonRect.contains(point) { return .today }
        if layout.previousButtonRect.contains(point) { return .previousMonth }
        if layout.nextButtonRect.contains(point) { return .nextMonth }
        if layout.settingsButtonRect.contains(point) { return .settings }
        if quickEventEditor.isHidden, layout.addEventRect.contains(point) { return .addEvent }
        if let eventIndex = eventHitRegions.firstIndex(where: { $0.rect.contains(point) }) {
            return .event(eventIndex)
        }

        let cells = dayCells.isEmpty ? makeDayCells(layout: layout) : dayCells
        if let cell = cells.first(where: { $0.rect.contains(point) }) {
            return .day(cell.index)
        }

        return nil
    }

    private func isEventTarget(_ target: HitTarget?) -> Bool {
        guard let target else { return false }
        if case .event = target { return true }
        return false
    }

    private var isDarkMode: Bool {
        AppSettings.shared.isDarkMode(for: effectiveAppearance)
    }

    private var textColor: NSColor {
        isDarkMode ? NSColor.white.withAlpha(0.94) : NSColor.black.withAlpha(0.84)
    }

    private var secondaryTextColor: NSColor {
        isDarkMode ? NSColor.white.withAlpha(0.62) : NSColor.black.withAlpha(0.55)
    }

    private var dividerColor: NSColor {
        isDarkMode ? NSColor.white.withAlpha(0.16) : NSColor.black.withAlpha(0.14)
    }

    private var subtleFillColor: NSColor {
        isDarkMode ? NSColor.white.withAlpha(0.06) : NSColor.black.withAlpha(0.045)
    }

    private var accentColor: NSColor {
        AppSettings.shared.accentColor
    }

    private func drawClock(layout: Layout) {
        let settings = AppSettings.shared
        let timeFormatter = settings.makeTimeFormatter()

        drawText(
            timeFormatter.string(from: now),
            in: NSRect(x: layout.sideInset, y: 20, width: bounds.width - layout.sideInset * 2, height: 66),
            font: windowsUIFont(size: 54, weight: .ultraLight),
            color: textColor,
            alignment: .left
        )
    }

    private func drawDivider(y: CGFloat) {
        drawLine(from: NSPoint(x: 0, y: y), to: NSPoint(x: bounds.width, y: y), color: dividerColor, lineWidth: 1)
    }

    private func drawMonthHeader(layout: Layout) {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")

        drawText(
            formatter.string(from: displayedMonth),
            in: NSRect(x: layout.monthHeaderRect.minX, y: layout.monthHeaderRect.minY + 5, width: 220, height: 34),
            font: windowsUIFont(size: 20, weight: .regular),
            color: textColor,
            alignment: .left
        )

        drawCommandButton(title: L10n.text("today"), rect: layout.todayButtonRect, target: .today)
        drawChevron(rect: layout.previousButtonRect, direction: .up, target: .previousMonth)
        drawChevron(rect: layout.nextButtonRect, direction: .down, target: .nextMonth)
    }

    private func drawWeekdayHeader(layout: Layout) {
        let labels = weekdaySymbols()
        for index in 0..<7 {
            let rect = NSRect(
                x: layout.gridRect.minX + CGFloat(index) * layout.cellSize.width,
                y: layout.weekdayRect.minY,
                width: layout.cellSize.width,
                height: layout.weekdayRect.height
            )

            drawText(labels[index], in: rect, font: windowsUIFont(size: 14, weight: .semibold), color: textColor, alignment: .center)
        }
    }

    private func weekdaySymbols() -> [String] {
        let formatter = DateFormatter()
        formatter.locale = AppSettings.shared.localizedLocale
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? formatter.shortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let offset = max(0, calendar.firstWeekday - 1)
        return Array(symbols[offset..<symbols.count]) + Array(symbols[0..<offset])
    }

    private func drawCalendarGrid(layout: Layout) {
        let lineColor = isDarkMode ? NSColor.white.withAlpha(0.055) : NSColor.black.withAlpha(0.045)

        for row in 0...6 {
            let y = layout.gridRect.minY + CGFloat(row) * layout.cellSize.height
            drawLine(from: NSPoint(x: layout.gridRect.minX, y: y), to: NSPoint(x: layout.gridRect.maxX, y: y), color: lineColor, lineWidth: 1)
        }

        for column in 0...7 {
            let x = layout.gridRect.minX + CGFloat(column) * layout.cellSize.width
            drawLine(from: NSPoint(x: x, y: layout.gridRect.minY), to: NSPoint(x: x, y: layout.gridRect.maxY), color: lineColor, lineWidth: 1)
        }

        for cell in dayCells {
            drawDayCell(cell)
        }
    }

    private func drawDayCell(_ cell: DayCell) {
        let isSelected = calendar.isDate(cell.date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(cell.date)
        let isHovered = hoveredTarget == .day(cell.index)
        let cellRect = cell.rect.insetBy(dx: 2, dy: 2)
        let selectionRect = NSRect(
            x: floor(cell.rect.midX - 21),
            y: floor(cell.rect.midY - 19),
            width: 42,
            height: 38
        )

        if isSelected {
            fill(selectionRect, color: accentColor)
        } else if isHovered, let mousePoint {
            drawReveal(in: cellRect, at: mousePoint)
        }

        if isToday {
            stroke(selectionRect.insetBy(dx: 0.5, dy: 0.5), color: accentColor, lineWidth: isSelected ? 2 : 2)
            if isSelected {
                stroke(selectionRect.insetBy(dx: 4.0, dy: 4.0), color: isDarkMode ? NSColor.black.withAlpha(0.84) : NSColor.white.withAlpha(0.84), lineWidth: 2)
            }
        }

        let label = dayLabel(for: cell.date)
        let color: NSColor = isSelected ? .white : textColor

        drawCenteredText(
            label,
            in: selectionRect,
            font: windowsUIFont(size: 17, weight: .regular),
            color: color,
            alignment: .center
        )

        drawEventIndicators(for: cell, selected: isSelected)
    }

    private func dayLabel(for date: Date) -> String {
        "\(calendar.component(.day, from: date))"
    }

    private func drawEventIndicators(for cell: DayCell, selected: Bool) {
        let key = calendar.startOfDay(for: cell.date)
        guard let events = eventsByDay[key], !events.isEmpty else { return }

        let count = min(events.count, 3)
        let totalWidth = CGFloat(count) * 5 + CGFloat(max(0, count - 1)) * 4
        let startX = cell.rect.midX - totalWidth / 2
        let y = cell.rect.maxY - 10

        for index in 0..<count {
            let eventColor = selected ? NSColor.white.withAlpha(0.95) : events[index].color.withAlpha(0.95)
            fill(NSRect(x: startX + CGFloat(index) * 9, y: y, width: 5, height: 5), color: eventColor)
        }
    }

    private func drawAgenda(layout: Layout) {
        drawDivider(y: layout.agendaRect.minY)

        let selectedFormatter = DateFormatter()
        selectedFormatter.locale = AppSettings.shared.localizedLocale

        let selectedTitle: String
        if calendar.isDateInToday(selectedDate) {
            selectedTitle = L10n.text("today")
        } else {
            selectedFormatter.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
            selectedTitle = selectedFormatter.string(from: selectedDate)
        }

        drawText(
            selectedTitle,
            in: NSRect(x: layout.sideInset, y: layout.agendaRect.minY + 22, width: bounds.width - layout.sideInset * 2 - 48, height: 32),
            font: windowsUIFont(size: 23, weight: .semibold),
            color: textColor,
            alignment: .left
        )

        drawSettingsButton(rect: layout.settingsButtonRect)

        if !quickEventEditor.isHidden {
            return
        }

        let inputRect = layout.addEventRect
        if hoveredTarget == .addEvent, let mousePoint {
            drawReveal(in: inputRect, at: mousePoint)
        }
        stroke(inputRect, color: dividerColor.withAlpha(0.85), lineWidth: 1)
        drawText(
            L10n.text("addEventReminder"),
            in: inputRect.insetBy(dx: 12, dy: 8),
            font: windowsUIFont(size: 16, weight: .regular),
            color: secondaryTextColor,
            alignment: .left
        )

        let eventsTop = inputRect.maxY + 18

        if let eventStatusMessage {
            drawMultilineText(
                eventStatusMessage,
                in: NSRect(x: layout.sideInset, y: eventsTop, width: bounds.width - layout.sideInset * 2, height: 70),
                font: windowsUIFont(size: 14, weight: .regular),
                color: secondaryTextColor,
                alignment: .left
            )
            return
        }

        if selectedDayEvents.isEmpty {
            drawText(
                L10n.text("noEvents"),
                in: NSRect(x: layout.sideInset, y: eventsTop, width: bounds.width - layout.sideInset * 2, height: 28),
                font: windowsUIFont(size: 18, weight: .regular),
                color: textColor,
                alignment: .left
            )
        } else {
            drawEvents(selectedDayEvents, startY: eventsTop, maxY: bounds.height - 22, sideInset: layout.sideInset)
        }
    }

    private func drawEvents(_ events: [CalendarEventSummary], startY: CGFloat, maxY: CGFloat, sideInset: CGFloat) {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = AppSettings.shared.localizedLocale
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        var y = startY
        for event in events.prefix(5) {
            guard y + 48 < maxY else { break }

            let eventRect = NSRect(x: sideInset, y: y, width: bounds.width - sideInset * 2, height: 48)
            let hitIndex = eventHitRegions.count
            eventHitRegions.append(EventHitRegion(rect: eventRect, event: event))
            if hoveredTarget == .event(hitIndex), let mousePoint {
                drawReveal(in: eventRect, at: mousePoint)
            }
            fill(NSRect(x: eventRect.minX, y: eventRect.minY + 5, width: 4, height: 38), color: event.color)

            let time = event.isAllDay ? L10n.text("allDay") : timeFormatter.string(from: event.startDate)
            drawText(
                time,
                in: NSRect(x: eventRect.minX + 12, y: eventRect.minY + 2, width: 76, height: 22),
                font: windowsMonospacedDigitFont(size: 13, weight: .regular),
                color: secondaryTextColor,
                alignment: .left
            )

            drawText(
                event.title,
                in: NSRect(x: eventRect.minX + 98, y: eventRect.minY, width: eventRect.width - 100, height: 24),
                font: windowsUIFont(size: 16, weight: .semibold),
                color: textColor,
                alignment: .left
            )

            if let location = event.location {
                drawText(
                    location,
                    in: NSRect(x: eventRect.minX + 98, y: eventRect.minY + 22, width: eventRect.width - 100, height: 20),
                    font: windowsUIFont(size: 13, weight: .regular),
                    color: secondaryTextColor,
                    alignment: .left
                )
            }

            y += 52
        }
    }

    private func drawCommandButton(title: String, rect: NSRect, target: HitTarget) {
        if hoveredTarget == target, let mousePoint {
            drawReveal(in: rect, at: mousePoint)
        }

        drawText(title, in: rect.insetBy(dx: 8, dy: 7), font: windowsUIFont(size: 14, weight: .regular), color: textColor, alignment: .center)
    }

    private enum ChevronDirection {
        case up
        case down
    }

    private func drawChevron(rect: NSRect, direction: ChevronDirection, target: HitTarget) {
        if hoveredTarget == target, let mousePoint {
            drawReveal(in: rect, at: mousePoint)
        }

        let path = NSBezierPath()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let width: CGFloat = 16
        let height: CGFloat = 9

        switch direction {
        case .up:
            path.move(to: NSPoint(x: center.x - width / 2, y: center.y + height / 2))
            path.line(to: NSPoint(x: center.x, y: center.y - height / 2))
            path.line(to: NSPoint(x: center.x + width / 2, y: center.y + height / 2))
        case .down:
            path.move(to: NSPoint(x: center.x - width / 2, y: center.y - height / 2))
            path.line(to: NSPoint(x: center.x, y: center.y + height / 2))
            path.line(to: NSPoint(x: center.x + width / 2, y: center.y - height / 2))
        }

        path.lineWidth = 1.6
        textColor.setStroke()
        path.stroke()
    }

    private func drawSettingsButton(rect: NSRect) {
        if hoveredTarget == .settings, let mousePoint {
            drawReveal(in: rect, at: mousePoint)
        }

        let center = NSPoint(x: rect.midX, y: rect.midY)
        let outerRadius: CGFloat = 9
        let innerRadius: CGFloat = 3.5
        let path = NSBezierPath()

        textColor.setFill()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4
            let point = NSPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius)
            let tooth = NSRect(x: point.x - 1.3, y: point.y - 1.3, width: 2.6, height: 2.6)
            NSBezierPath(rect: tooth).fill()
        }

        path.appendOval(in: NSRect(x: center.x - outerRadius + 2, y: center.y - outerRadius + 2, width: (outerRadius - 2) * 2, height: (outerRadius - 2) * 2))
        path.appendOval(in: NSRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))
        textColor.setStroke()
        path.lineWidth = 1.4
        path.stroke()
    }

    private func drawReveal(in rect: NSRect, at point: NSPoint) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.clip(to: rect)

        let radius = max(rect.width, rect.height) * 1.85
        let colors = [
            NSColor.white.withAlpha(isDarkMode ? 0.18 : 0.14).cgColor,
            accentColor.withAlpha(isDarkMode ? 0.10 : 0.07).cgColor,
            NSColor.clear.cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.42, 1.0]

        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
            context.drawRadialGradient(
                gradient,
                startCenter: point,
                startRadius: 0,
                endCenter: point,
                endRadius: radius,
                options: [.drawsAfterEndLocation]
            )
        }

        drawRevealEdges(in: rect.insetBy(dx: 0.5, dy: 0.5), at: point, radius: radius)
        context.restoreGState()
    }

    private func drawRevealEdges(in rect: NSRect, at point: NSPoint, radius: CGFloat) {
        let segmentLength: CGFloat = 8
        let color = isDarkMode ? NSColor.white : accentColor

        func drawSegment(from start: NSPoint, to end: NSPoint) {
            let mid = NSPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let distance = hypot(mid.x - point.x, mid.y - point.y)
            let intensity = max(0, 1 - distance / radius)
            guard intensity > 0.02 else { return }

            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = 1.35
            color.withAlpha((isDarkMode ? 0.82 : 0.58) * intensity * intensity).setStroke()
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

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawTextAtPointWithShadow(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlpha(0.36)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .shadow: shadow
        ]

        (text as NSString).draw(at: point, withAttributes: attributes)
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
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.minY + floor((rect.height - size.height) / 2.0) - 0.5,
            width: rect.width,
            height: ceil(size.height) + 2
        )
        (text as NSString).draw(in: drawRect, withAttributes: attributes)
    }

    private func drawMultilineText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        (text as NSString).draw(in: rect, withAttributes: attributes)
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

private func max(_ lhs: Date, _ rhs: Date) -> Date {
    lhs > rhs ? lhs : rhs
}

private func min(_ lhs: Date, _ rhs: Date) -> Date {
    lhs < rhs ? lhs : rhs
}
