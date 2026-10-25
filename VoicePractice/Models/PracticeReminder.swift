import Foundation
import UserNotifications

/// 연습 알림: 정한 시각에 하루 한 번 알려 주는 로컬 알림. 기기 안에서 예약하고 네트워크는 쓰지 않는다 (원칙 2).
/// 그날 이미 연습했으면 그날은 알리지 않는다. 연속 기록이나 "어제 빼먹었어요" 같은 압박 문구는 쓰지 않는다 (원칙 4).
/// 하루씩 따로 예약해 두고(앞으로 14일), 앱을 열 때·연습을 마칠 때마다 다시 맞춘다.
enum PracticeReminder {
    static let enabledKey = "practiceReminderEnabled"
    /// 알림 시각: 자정부터 몇 분째인지 (예: 1200 = 오후 8시)
    static let minuteOfDayKey = "practiceReminderMinuteOfDay"
    static let defaultMinuteOfDay = 20 * 60
    /// 앞으로 며칠치를 예약해 두는지. 앱을 14일 넘게 열지 않으면 알림도 멈춘다 (계속 조르지 않게).
    static let daysAhead = 14
    static let identifierPrefix = "practiceReminder-"
    static let title = "목소리 연습"
    static let body = "오늘 목소리 연습할 시간이에요. 목 상태를 보며 편하게 시작해요."

    /// 알림을 보낼 시각들: 오늘부터 `daysAhead`일 동안 하루 한 번. 오늘은 이미 지난 시각이거나 이미 연습했으면 뺀다.
    static func fireDates(now: Date, minuteOfDay: Int, practicedToday: Bool, calendar: Calendar) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let date = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day) else {
                return nil
            }
            if offset == 0, practicedToday || date <= now {
                return nil
            }
            return date
        }
    }

    /// 날짜마다 알림 하나. 같은 날의 알림은 이름(identifier)이 같다.
    static func requests(for dates: [Date], calendar: Calendar) -> [UNNotificationRequest] {
        dates.map { date in
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            return UNNotificationRequest(identifier: identifier(for: date, calendar: calendar), content: content, trigger: trigger)
        }
    }

    /// 예: "practiceReminder-2026-10-25"
    static func identifier(for date: Date, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return identifierPrefix + String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// 알림 시각을 "오후 8:00"처럼 보여 줄 때 쓰는 날짜 (오늘 그 시각)
    static func date(forMinuteOfDay minuteOfDay: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: .now) ?? .now
    }

    static func minuteOfDay(of date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    // MARK: - 예약

    /// 설정과 오늘 연습 여부로 알림 예약을 새로 맞춘다.
    /// 이 앱이 보내는 알림은 이것뿐이라, 예약된 것을 모두 지우고 다시 넣는다. 꺼져 있으면 지우기만 한다.
    /// 기다리지 않고 바로 돌아오므로 앱이 백그라운드로 가는 순간에도 부를 수 있다.
    static func refresh(practicedToday: Bool, defaults: UserDefaults = .standard, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard defaults.bool(forKey: enabledKey) else { return }
        let minuteOfDay = defaults.object(forKey: minuteOfDayKey) as? Int ?? defaultMinuteOfDay
        let calendar = Calendar.current
        let dates = fireDates(now: now, minuteOfDay: minuteOfDay, practicedToday: practicedToday, calendar: calendar)
        for request in requests(for: dates, calendar: calendar) {
            center.add(request, withCompletionHandler: nil)
        }
    }

    /// 저장된 연습 기록으로 오늘 연습했는지 보고 다시 맞춘다.
    static func refresh(using archive: PracticeArchive) {
        refresh(practicedToday: archive.hasPractice(on: .now))
    }

    // MARK: - 권한

    enum Permission {
        case notDetermined
        case allowed
        case denied
    }

    static func permission() async -> Permission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .allowed
        }
    }

    /// 처음이면 알림 권한을 묻는다 (알림을 켤 때만 묻는다). 알림을 보낼 수 있으면 true.
    static func requestPermission() async -> Bool {
        switch await permission() {
        case .allowed:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }
}
