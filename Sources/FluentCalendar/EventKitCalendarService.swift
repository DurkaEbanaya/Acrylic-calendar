import AppKit
import EventKit

struct CalendarEventSummary {
    let identifier: String
    let eventIdentifier: String?
    let calendarItemIdentifier: String
    let externalIdentifier: String?
    let title: String
    let location: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let color: NSColor
}

enum CalendarServiceError: LocalizedError {
    case missingUsageDescription
    case accessDenied
    case writeOnlyAccess
    case restricted
    case noWritableCalendar
    case requestFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingUsageDescription:
            return "Build and run the .app bundle to enable calendar permissions. The bundle contains the required calendar privacy description."
        case .accessDenied:
            return "Calendar access is denied. Enable it in System Settings > Privacy & Security > Calendars."
        case .writeOnlyAccess:
            return "Calendar access is write-only. Full calendar access is required to show events."
        case .restricted:
            return "Calendar access is restricted by macOS policy."
        case .noWritableCalendar:
            return "No writable calendar is available for new events. Add or enable a calendar in macOS Calendar settings."
        case .requestFailed(let error):
            return error.localizedDescription
        }
    }
}

final class EventKitCalendarService {
    private let eventStore = EKEventStore()

    func fetchEvents(in interval: DateInterval, completion: @escaping (Result<[CalendarEventSummary], CalendarServiceError>) -> Void) {
        requestReadAccess { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                DispatchQueue.main.async {
                    let predicate = self.eventStore.predicateForEvents(
                        withStart: interval.start,
                        end: interval.end,
                        calendars: nil
                    )

                    let events = self.eventStore.events(matching: predicate).map { self.summary(from: $0) }

                    completion(.success(events))
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    func createEvent(title: String, location: String?, startDate: Date, endDate: Date, alarmOffsetMinutes: Int? = nil, completion: @escaping (Result<CalendarEventSummary, CalendarServiceError>) -> Void) {
        requestReadAccess { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                DispatchQueue.main.async {
                    guard let calendar = self.eventStore.defaultCalendarForNewEvents else {
                        completion(.failure(.noWritableCalendar))
                        return
                    }

                    let event = EKEvent(eventStore: self.eventStore)
                    event.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.text("newEvent") : title
                    let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
                    event.location = trimmedLocation?.isEmpty == false ? trimmedLocation : nil
                    event.startDate = startDate
                    event.endDate = max(endDate, startDate.addingTimeInterval(30 * 60))
                    if let alarmOffsetMinutes {
                        event.alarms = [EKAlarm(relativeOffset: TimeInterval(-alarmOffsetMinutes * 60))]
                    }
                    event.calendar = calendar

                    do {
                        try self.eventStore.save(event, span: .thisEvent, commit: true)
                        let summary = self.summary(from: event)
                        NotificationCenter.default.post(name: .fluentCalendarEventsChanged, object: self)
                        completion(.success(summary))
                    } catch {
                        completion(.failure(.requestFailed(error)))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    static func openEventInCalendar(_ event: CalendarEventSummary) {
        let calendarURLs = [
            URL(fileURLWithPath: "/System/Applications/Calendar.app"),
            URL(fileURLWithPath: "/Applications/Calendar.app")
        ]

        for url in calendarURLs where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return
        }
    }

    private func summary(from event: EKEvent) -> CalendarEventSummary {
        CalendarEventSummary(
            identifier: event.eventIdentifier ?? event.calendarItemIdentifier,
            eventIdentifier: event.eventIdentifier,
            calendarItemIdentifier: event.calendarItemIdentifier,
            externalIdentifier: event.calendarItemExternalIdentifier,
            title: event.title?.isEmpty == false ? event.title : "Untitled event",
            location: event.location?.isEmpty == false ? event.location : nil,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            color: NSColor(cgColor: event.calendar.cgColor) ?? AppSettings.shared.accentColor
        )
    }

    private func requestReadAccess(completion: @escaping (Result<Void, CalendarServiceError>) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)

        if status == .notDetermined && !Self.hasCalendarUsageDescription {
            completion(.failure(.missingUsageDescription))
            return
        }

        if #available(macOS 14.0, *) {
            switch status {
            case .fullAccess, .authorized:
                completion(.success(()))
            case .writeOnly:
                completion(.failure(.writeOnlyAccess))
            case .notDetermined:
                eventStore.requestFullAccessToEvents { granted, error in
                    if let error {
                        completion(.failure(.requestFailed(error)))
                    } else if granted {
                        completion(.success(()))
                    } else {
                        completion(.failure(.accessDenied))
                    }
                }
            case .denied:
                completion(.failure(.accessDenied))
            case .restricted:
                completion(.failure(.restricted))
            @unknown default:
                completion(.failure(.accessDenied))
            }
        } else {
            switch status {
            case .authorized, .fullAccess:
                completion(.success(()))
            case .writeOnly:
                completion(.failure(.writeOnlyAccess))
            case .notDetermined:
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error {
                        completion(.failure(.requestFailed(error)))
                    } else if granted {
                        completion(.success(()))
                    } else {
                        completion(.failure(.accessDenied))
                    }
                }
            case .denied:
                completion(.failure(.accessDenied))
            case .restricted:
                completion(.failure(.restricted))
            @unknown default:
                completion(.failure(.accessDenied))
            }
        }
    }

    private static var hasCalendarUsageDescription: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSCalendarsUsageDescription") != nil
            || Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
    }
}
