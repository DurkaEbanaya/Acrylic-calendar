import AppKit

final class QuickEventEditorView: NSView {
    override var isFlipped: Bool { true }

    var onSave: ((String, String?, Date, Date, Int?) -> Void)?
    var onCancel: (() -> Void)?
    var onMoreDetails: (() -> Void)?

    private let titleField = NSTextField(string: L10n.text("newEvent"))
    private let locationField = NSTextField(string: "")
    private let startDatePicker = NSDatePicker()
    private let endDatePicker = NSDatePicker()
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let reminderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let saveButton = NSButton(title: L10n.text("save"), target: nil, action: nil)
    private let moreButton = NSButton(title: L10n.text("moreDetails"), target: nil, action: nil)
    private let closeButton = NSButton(title: "×", target: nil, action: nil)
    private var calendar = Calendar.autoupdatingCurrent
    private var selectedDate = Date()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        calendar.locale = AppSettings.shared.localizedLocale
        wantsLayer = true
        layer?.cornerRadius = 0
        configureControls()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(for date: Date) {
        selectedDate = calendar.startOfDay(for: date)

        let start: Date
        if calendar.isDateInToday(date) {
            let now = Date()
            let hour = calendar.component(.hour, from: now) + 1
            start = calendar.date(bySettingHour: min(hour, 23), minute: 0, second: 0, of: selectedDate) ?? selectedDate.addingTimeInterval(9 * 3600)
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate.addingTimeInterval(9 * 3600)
        }

        titleField.stringValue = L10n.text("newEvent")
        locationField.stringValue = ""
        startDatePicker.dateValue = selectedDate
        endDatePicker.dateValue = selectedDate
        startPicker.dateValue = start
        endPicker.dateValue = start.addingTimeInterval(3600)
        reminderPopup.selectItem(at: 1)
        window?.makeFirstResponder(titleField)
        needsDisplay = true
    }

    override func layout() {
        super.layout()

        let inset: CGFloat = 32
        let contentWidth = bounds.width - inset * 2
        closeButton.frame = NSRect(x: bounds.width - 52, y: 12, width: 32, height: 32)
        titleField.frame = NSRect(x: inset, y: 22, width: contentWidth - 46, height: 32)

        startDatePicker.frame = NSRect(x: inset + 48, y: 68, width: 142, height: 26)
        endDatePicker.frame = NSRect(x: inset + 232, y: 68, width: 142, height: 26)
        startPicker.frame = NSRect(x: inset + 48, y: 104, width: 128, height: 26)
        endPicker.frame = NSRect(x: inset + 232, y: 104, width: 128, height: 26)
        locationField.frame = NSRect(x: inset + 48, y: 140, width: contentWidth - 48, height: 26)
        reminderPopup.frame = NSRect(x: inset + 48, y: 176, width: 150, height: 26)

        saveButton.frame = NSRect(x: bounds.width - inset - 218, y: 208, width: 92, height: 32)
        moreButton.frame = NSRect(x: bounds.width - inset - 116, y: 208, width: 116, height: 32)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let isDark = AppSettings.shared.isDarkMode(for: effectiveAppearance)
        fill(bounds, color: isDark ? NSColor.black.withAlpha(0.52) : NSColor.white.withAlpha(0.62))
        stroke(bounds.insetBy(dx: 0.5, dy: 0.5), color: isDark ? NSColor.white.withAlpha(0.16) : NSColor.black.withAlpha(0.14), lineWidth: 1)

        drawIconCalendar(frame: NSRect(x: 32, y: 72, width: 18, height: 18))
        drawLabel(L10n.text("to"), frame: NSRect(x: 214, y: 70, width: 24, height: 22), size: 15, weight: .regular)
        drawIconClock(frame: NSRect(x: 32, y: 108, width: 18, height: 18))
        drawLabel(L10n.text("to"), frame: NSRect(x: 214, y: 106, width: 24, height: 22), size: 15, weight: .regular)
        drawIconLocation(frame: NSRect(x: 32, y: 144, width: 18, height: 18))
        drawIconBell(frame: NSRect(x: 32, y: 180, width: 18, height: 18))
    }

    private func configureControls() {
        titleField.font = windowsUIFont(size: 18, weight: .regular)
        titleField.placeholderString = L10n.text("eventName")
        titleField.isBordered = true
        titleField.bezelStyle = .squareBezel
        titleField.isEditable = true
        titleField.isSelectable = true
        addSubview(titleField)

        locationField.font = windowsUIFont(size: 16, weight: .regular)
        locationField.placeholderString = L10n.text("addLocation")
        locationField.isBordered = false
        locationField.drawsBackground = false
        locationField.isEditable = true
        locationField.isSelectable = true
        addSubview(locationField)

        for picker in [startDatePicker, endDatePicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.yearMonthDay]
            picker.isBordered = true
            picker.font = windowsMonospacedDigitFont(size: 13, weight: .regular)
            addSubview(picker)
        }

        for picker in [startPicker, endPicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.hourMinute]
            picker.isBordered = true
            picker.font = windowsMonospacedDigitFont(size: 15, weight: .regular)
            addSubview(picker)
        }

        reminderPopup.addItems(withTitles: [L10n.text("noReminder"), L10n.text("minutes15"), L10n.text("minutes30"), L10n.text("hour1"), L10n.text("day1")])
        reminderPopup.font = windowsUIFont(size: 14, weight: .regular)
        addSubview(reminderPopup)

        saveButton.target = self
        saveButton.action = #selector(savePressed)
        saveButton.bezelStyle = .regularSquare
        saveButton.font = windowsUIFont(size: 16, weight: .regular)
        saveButton.contentTintColor = .white
        saveButton.wantsLayer = true
        saveButton.layer?.backgroundColor = AppSettings.shared.accentColor.cgColor
        addSubview(saveButton)

        moreButton.target = self
        moreButton.action = #selector(moreDetailsPressed)
        moreButton.bezelStyle = .regularSquare
        moreButton.font = windowsUIFont(size: 16, weight: .regular)
        addSubview(moreButton)

        closeButton.target = self
        closeButton.action = #selector(cancelPressed)
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.font = windowsUIFont(size: 26, weight: .light)
        addSubview(closeButton)

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
        calendar.locale = AppSettings.shared.localizedLocale
        titleField.placeholderString = L10n.text("eventName")
        locationField.placeholderString = L10n.text("addLocation")
        saveButton.title = L10n.text("save")
        moreButton.title = L10n.text("moreDetails")
        let selectedReminder = reminderPopup.indexOfSelectedItem
        reminderPopup.removeAllItems()
        reminderPopup.addItems(withTitles: [L10n.text("noReminder"), L10n.text("minutes15"), L10n.text("minutes30"), L10n.text("hour1"), L10n.text("day1")])
        reminderPopup.selectItem(at: max(0, min(selectedReminder, reminderPopup.numberOfItems - 1)))
        saveButton.layer?.backgroundColor = AppSettings.shared.accentColor.cgColor
        needsDisplay = true
    }

    @objc private func savePressed() {
        let start = combinedDate(day: startDatePicker.dateValue, time: startPicker.dateValue)
        var end = combinedDate(day: endDatePicker.dateValue, time: endPicker.dateValue)

        if end <= start {
            end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        }

        onSave?(titleField.stringValue, locationField.stringValue, start, end, selectedReminderMinutes())
    }

    @objc private func cancelPressed() {
        onCancel?()
    }

    @objc private func moreDetailsPressed() {
        onMoreDetails?()
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

    private func selectedReminderMinutes() -> Int? {
        switch reminderPopup.indexOfSelectedItem {
        case 1: return 15
        case 2: return 30
        case 3: return 60
        case 4: return 24 * 60
        default: return nil
        }
    }

    private func drawLabel(_ text: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let color = AppSettings.shared.isDarkMode(for: effectiveAppearance) ? NSColor.white.withAlpha(0.92) : NSColor.black.withAlpha(0.82)
        (text as NSString).draw(in: frame, withAttributes: [
            .font: windowsUIFont(size: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func drawIconClock(frame: NSRect) {
        let color = AppSettings.shared.isDarkMode(for: effectiveAppearance) ? NSColor.white.withAlpha(0.70) : NSColor.black.withAlpha(0.54)
        color.setStroke()
        let path = NSBezierPath(ovalIn: frame)
        path.lineWidth = 1.4
        path.stroke()

        let center = NSPoint(x: frame.midX, y: frame.midY)
        let hands = NSBezierPath()
        hands.move(to: center)
        hands.line(to: NSPoint(x: center.x, y: center.y - 5))
        hands.move(to: center)
        hands.line(to: NSPoint(x: center.x + 4, y: center.y + 2))
        hands.lineWidth = 1.4
        hands.stroke()
    }

    private func drawIconCalendar(frame: NSRect) {
        let color = AppSettings.shared.isDarkMode(for: effectiveAppearance) ? NSColor.white.withAlpha(0.70) : NSColor.black.withAlpha(0.54)
        color.setStroke()
        let path = NSBezierPath(rect: frame.insetBy(dx: 1.5, dy: 2.5))
        path.lineWidth = 1.3
        path.stroke()
        drawLine(from: NSPoint(x: frame.minX + 2, y: frame.minY + 7), to: NSPoint(x: frame.maxX - 2, y: frame.minY + 7), color: color, lineWidth: 1.1)
        drawLine(from: NSPoint(x: frame.minX + 6, y: frame.minY + 1), to: NSPoint(x: frame.minX + 6, y: frame.minY + 5), color: color, lineWidth: 1.4)
        drawLine(from: NSPoint(x: frame.maxX - 6, y: frame.minY + 1), to: NSPoint(x: frame.maxX - 6, y: frame.minY + 5), color: color, lineWidth: 1.4)
    }

    private func drawIconLocation(frame: NSRect) {
        let color = AppSettings.shared.isDarkMode(for: effectiveAppearance) ? NSColor.white.withAlpha(0.70) : NSColor.black.withAlpha(0.54)
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: frame.midX, y: frame.minY))
        path.line(to: NSPoint(x: frame.maxX - 3, y: frame.maxY))
        path.line(to: NSPoint(x: frame.minX + 3, y: frame.maxY))
        path.close()
        path.lineWidth = 1.3
        path.stroke()
    }

    private func drawIconBell(frame: NSRect) {
        let color = AppSettings.shared.isDarkMode(for: effectiveAppearance) ? NSColor.white.withAlpha(0.70) : NSColor.black.withAlpha(0.54)
        color.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: frame.minX + 4, y: frame.maxY - 5))
        path.curve(to: NSPoint(x: frame.maxX - 4, y: frame.maxY - 5), controlPoint1: NSPoint(x: frame.minX + 4, y: frame.minY + 2), controlPoint2: NSPoint(x: frame.maxX - 4, y: frame.minY + 2))
        path.line(to: NSPoint(x: frame.maxX - 2, y: frame.maxY - 2))
        path.line(to: NSPoint(x: frame.minX + 2, y: frame.maxY - 2))
        path.close()
        path.lineWidth = 1.3
        path.stroke()

        let clapper = NSBezierPath(ovalIn: NSRect(x: frame.midX - 2, y: frame.maxY - 1, width: 4, height: 4))
        clapper.stroke()
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
