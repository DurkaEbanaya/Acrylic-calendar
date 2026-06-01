import AppKit

extension Notification.Name {
    static let fluentCalendarSettingsChanged = Notification.Name("fluentCalendarSettingsChanged")
    static let fluentCalendarEventsChanged = Notification.Name("fluentCalendarEventsChanged")
}

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return L10n.text("theme.system")
        case .light: return L10n.text("theme.light")
        case .dark: return L10n.text("theme.dark")
        }
    }
}

enum MenuBarDateDisplay: String, CaseIterable {
    case whenSpaceAllows
    case always
    case never

    var title: String {
        switch self {
        case .whenSpaceAllows: return L10n.text("date.whenSpaceAllows")
        case .always: return L10n.text("date.always")
        case .never: return L10n.text("date.never")
        }
    }
}

enum HourCycle: String, CaseIterable {
    case system
    case twelve
    case twentyFour

    var title: String {
        switch self {
        case .system: return L10n.text("hour.system")
        case .twelve: return L10n.text("hour.twelve")
        case .twentyFour: return L10n.text("hour.twentyFour")
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case system
    case english
    case russian
    case ukrainian
    case german
    case french
    case japanese
    case tatar

    var title: String {
        switch self {
        case .system: return L10n.text("language.system")
        case .english: return "English"
        case .russian: return "Русский"
        case .ukrainian: return "Українська"
        case .german: return "Deutsch"
        case .french: return "Français"
        case .japanese: return "日本語"
        case .tatar: return "Татарча"
        }
    }
}

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let themeMode = "themeMode"
        static let menuBarDateDisplay = "menuBarDateDisplay"
        static let hourCycle = "hourCycle"
        static let showsDayOfWeek = "showsDayOfWeek"
        static let showsSeconds = "showsSeconds"
        static let appLanguage = "appLanguage"
        static let accentColorHex = "accentColorHex"
        static let usesSystemAccent = "usesSystemAccent"
        static let launchAtLoginManuallyDisabled = "launchAtLoginManuallyDisabled"
    }

    private init() {
        if defaults.string(forKey: Key.accentColorHex) == nil {
            defaults.set("#0078D7", forKey: Key.accentColorHex)
        }
    }

    var themeMode: ThemeMode {
        get { ThemeMode(rawValue: defaults.string(forKey: Key.themeMode) ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: Key.themeMode)
            applyAppearance()
            notifyChanged()
        }
    }

    var menuBarDateDisplay: MenuBarDateDisplay {
        get {
            if let value = defaults.string(forKey: Key.menuBarDateDisplay), let display = MenuBarDateDisplay(rawValue: value) {
                return display
            }
            if let legacy = defaults.string(forKey: "clockFormat"), legacy == "compact" {
                return .never
            }
            return .whenSpaceAllows
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.menuBarDateDisplay)
            notifyChanged()
        }
    }

    var hourCycle: HourCycle {
        get { HourCycle(rawValue: defaults.string(forKey: Key.hourCycle) ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: Key.hourCycle)
            notifyChanged()
        }
    }

    var showsDayOfWeek: Bool {
        get { defaults.object(forKey: Key.showsDayOfWeek) == nil ? true : defaults.bool(forKey: Key.showsDayOfWeek) }
        set {
            defaults.set(newValue, forKey: Key.showsDayOfWeek)
            notifyChanged()
        }
    }

    var showsSeconds: Bool {
        get { defaults.object(forKey: Key.showsSeconds) == nil ? true : defaults.bool(forKey: Key.showsSeconds) }
        set {
            defaults.set(newValue, forKey: Key.showsSeconds)
            notifyChanged()
        }
    }

    var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: Key.appLanguage) ?? "") ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: Key.appLanguage)
            notifyChanged()
        }
    }

    var resolvedLanguage: AppLanguage {
        if appLanguage != .system { return appLanguage }
        let code = Locale.autoupdatingCurrent.language.languageCode?.identifier.lowercased() ?? "en"
        switch code {
        case "ru": return .russian
        case "uk": return .ukrainian
        case "de": return .german
        case "fr": return .french
        case "ja": return .japanese
        case "tt": return .tatar
        default: return .english
        }
    }

    var localizedLocale: Locale {
        switch resolvedLanguage {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .russian:
            return Locale(identifier: "ru")
        case .ukrainian:
            return Locale(identifier: "uk")
        case .german:
            return Locale(identifier: "de")
        case .french:
            return Locale(identifier: "fr")
        case .japanese:
            return Locale(identifier: "ja")
        case .tatar:
            return Locale(identifier: "tt")
        }
    }

    var usesSystemAccent: Bool {
        get {
            if defaults.object(forKey: Key.usesSystemAccent) == nil {
                return false
            }
            return defaults.bool(forKey: Key.usesSystemAccent)
        }
        set {
            defaults.set(newValue, forKey: Key.usesSystemAccent)
            notifyChanged()
        }
    }

    var launchAtLoginManuallyDisabled: Bool {
        get { defaults.bool(forKey: Key.launchAtLoginManuallyDisabled) }
        set { defaults.set(newValue, forKey: Key.launchAtLoginManuallyDisabled) }
    }

    var customAccentColor: NSColor {
        get { NSColor(hexString: defaults.string(forKey: Key.accentColorHex) ?? "#0078D7") ?? NSColor.windowsAccentBlue }
        set {
            defaults.set(newValue.hexString, forKey: Key.accentColorHex)
            notifyChanged()
        }
    }

    var accentColor: NSColor {
        usesSystemAccent ? NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.windowsAccentBlue : customAccentColor
    }

    func applyAppearance() {
        switch themeMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func isDarkMode(for appearance: NSAppearance?) -> Bool {
        switch themeMode {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            let resolved = appearance ?? NSApp.effectiveAppearance
            return resolved.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    func makeTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = localizedLocale
        formatter.dateStyle = .none

        switch hourCycle {
        case .system:
            formatter.timeStyle = showsSeconds ? .medium : .short
        case .twelve:
            let template = showsSeconds ? "hms a" : "hm a"
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: localizedLocale)
        case .twentyFour:
            formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: showsSeconds ? "Hms" : "Hm", options: 0, locale: localizedLocale)
        }

        return formatter
    }

    var usesTwelveHourClock: Bool {
        switch hourCycle {
        case .system:
            let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
            return format.contains("a")
        case .twelve:
            return true
        case .twentyFour:
            return false
        }
    }

    func makeHeaderDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = localizedLocale
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }

    func makeMenuBarDateFormatter(always: Bool) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = localizedLocale
        formatter.dateStyle = always ? .medium : .short
        formatter.timeStyle = .none
        return formatter
    }

    func makeWeekdayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = localizedLocale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .fluentCalendarSettingsChanged, object: self)
    }
}

extension NSColor {
    static let windowsAccentBlue = NSColor(red: 0.0, green: 0.4706, blue: 0.8431, alpha: 1.0)

    convenience init?(hexString: String) {
        var value = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") {
            value.removeFirst()
        }

        guard value.count == 6, let raw = UInt32(value, radix: 16) else {
            return nil
        }

        let red = CGFloat((raw & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((raw & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(raw & 0x0000FF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int(round(color.redComponent * 255.0))
        let green = Int(round(color.greenComponent * 255.0))
        let blue = Int(round(color.blueComponent * 255.0))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    func withAlpha(_ alpha: CGFloat) -> NSColor {
        withAlphaComponent(alpha)
    }
}

func windowsUIFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let candidates: [String]

    switch weight {
    case .thin, .ultraLight, .light:
        candidates = ["Segoe UI Light", "Segoe UI"]
    case .semibold, .bold, .heavy, .black:
        candidates = ["Segoe UI Semibold", "Segoe UI"]
    default:
        candidates = ["Segoe UI"]
    }

    for name in candidates {
        if let font = NSFont(name: name, size: size) {
            return font
        }
    }

    return NSFont.systemFont(ofSize: size, weight: weight)
}

func windowsMonospacedDigitFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
}
