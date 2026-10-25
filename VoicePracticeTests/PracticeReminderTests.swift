import Foundation
import Testing
import UserNotifications
@testable import VoicePractice

@MainActor
struct PracticeReminderTests {
    /// 서울 시간대로 고정한 달력 (테스트를 돌리는 기기의 시간대와 상관없이 같은 결과)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test("알림 시각 전이고 아직 연습하지 않았으면 오늘부터 14일, 하루 한 번")
    func fourteenDays() {
        let dates = PracticeReminder.fireDates(now: date(25, 19), minuteOfDay: 20 * 60, practicedToday: false, calendar: calendar)
        #expect(dates.count == 14)
        #expect(dates.first == date(25, 20))
        #expect(dates.last == date(7, 20, month: 11))
        #expect(Set(dates.map { calendar.startOfDay(for: $0) }).count == 14)
    }

    @Test("오늘 이미 연습했거나 오늘 알림 시각이 지났으면 내일부터")
    func skipsToday() {
        let practiced = PracticeReminder.fireDates(now: date(25, 19), minuteOfDay: 20 * 60, practicedToday: true, calendar: calendar)
        #expect(practiced.count == 13)
        #expect(practiced.first == date(26, 20))

        let late = PracticeReminder.fireDates(now: date(25, 21), minuteOfDay: 20 * 60, practicedToday: false, calendar: calendar)
        #expect(late.first == date(26, 20))
        // 바로 그 시각이면 이미 지난 것으로 본다
        let exact = PracticeReminder.fireDates(now: date(25, 20), minuteOfDay: 20 * 60, practicedToday: false, calendar: calendar)
        #expect(exact.first == date(26, 20))
    }

    @Test("분 단위 시각도 그대로 (오전 7:30)")
    func minuteOfDay() {
        let dates = PracticeReminder.fireDates(now: date(25, 6), minuteOfDay: 7 * 60 + 30, practicedToday: false, calendar: calendar)
        #expect(dates.first == date(25, 7, 30))
        #expect(PracticeReminder.minuteOfDay(of: date(25, 7, 30), calendar: calendar) == 450)
    }

    @Test("알림 요청: 날마다 이름이 다르고, 한 번만 울리며, 압박하는 말이 없다")
    func requests() throws {
        let dates = PracticeReminder.fireDates(now: date(25, 19), minuteOfDay: 20 * 60, practicedToday: false, calendar: calendar)
        let requests = PracticeReminder.requests(for: dates, calendar: calendar)
        #expect(requests.count == 14)
        #expect(Set(requests.map(\.identifier)).count == 14)
        #expect(requests[0].identifier == "practiceReminder-2026-10-25")

        let trigger = try #require(requests[0].trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.day == 25)
        #expect(trigger.dateComponents.hour == 20)
        #expect(trigger.dateComponents.minute == 0)

        let text = requests[0].content.title + requests[0].content.body
        for pressure in ["빼먹", "놓쳤", "연속", "점수", "벌써"] {
            #expect(!text.contains(pressure))
        }
    }

    @Test("오늘 연습 기록이 남았는지: 오늘 끝난 연습만 센다 (자정을 넘긴 연습은 끝난 날에도 센다)")
    func hasPractice() throws {
        let archive = PracticeArchive(inMemory: true, recordingsDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("reminder-\(UUID().uuidString)"))
        #expect(!archive.hasPractice(on: date(25, 12), calendar: calendar))

        func save(start: Date, minutes: Double) throws {
            var log = PracticeSessionLog(startedAt: start, language: .korean)
            log.beginTake()
            log.add((0..<500).map { PitchReading(time: Double($0) * 0.02, frequency: 180) })
            archive.saveSession(try #require(log.finish(at: start.addingTimeInterval(minutes * 60), target: nil)))
        }

        try save(start: date(24, 10), minutes: 10)  // 어제 낮
        #expect(!archive.hasPractice(on: date(25, 12), calendar: calendar))
        #expect(archive.hasPractice(on: date(24, 12), calendar: calendar))

        try save(start: date(24, 23, 50), minutes: 20)  // 어제 밤 ~ 오늘 0:10
        #expect(archive.hasPractice(on: date(25, 12), calendar: calendar))
        #expect(!archive.hasPractice(on: date(26, 12), calendar: calendar))
    }
}
