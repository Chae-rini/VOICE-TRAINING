import Foundation
import Testing
@testable import VoicePractice

@MainActor
struct PracticeHistoryTests {
    /// 서울 시간대로 고정한 달력 (테스트를 돌리는 기기의 시간대와 상관없이 같은 결과)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    /// 2026-10-25 21:00 (서울)
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 21))!
    }

    private func date(_ day: Int, _ hour: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func point(_ start: Date, minutes: Double = 10, median: Double = 160, low: Double = 140, high: Double = 185,
                       language: PracticeLanguage = .korean) -> SessionPoint {
        SessionPoint(startedAt: start, practiceSeconds: minutes * 60, median: median, low: low, high: high, language: language)
    }

    @Test("기간: 7일은 오늘과 그 앞 6일, 30일은 오늘과 그 앞 29일, 전체는 처음부터")
    func periods() {
        #expect(HistoryPeriod.week.start(now: now, calendar: calendar) == date(19, 0))
        #expect(HistoryPeriod.month.start(now: now, calendar: calendar) == date(26, 0, month: 9))
        #expect(HistoryPeriod.all.start(now: now, calendar: calendar) == nil)
        #expect(HistoryPeriod.week.contains(date(19, 0), now: now, calendar: calendar))
        #expect(!HistoryPeriod.week.contains(date(18, 23), now: now, calendar: calendar))
        #expect(HistoryPeriod.all.contains(date(1, 0, month: 1), now: now, calendar: calendar))
    }

    @Test("기간과 언어로 거른다")
    func filters() {
        let points = [
            point(date(25, 20)), point(date(24, 20), language: .english),
            point(date(10, 20)), point(date(10, 8), language: .japanese),
        ]
        #expect(PracticeHistory.filter(points, period: .week, language: nil, now: now, calendar: calendar).count == 2)
        #expect(PracticeHistory.filter(points, period: .week, language: .english, now: now, calendar: calendar)
                == [points[1]])
        #expect(PracticeHistory.filter(points, period: .all, language: .korean, now: now, calendar: calendar)
                == [points[0], points[2]])
    }

    @Test("하루에 여러 번 연습하면 그날 시간을 더하고, 자정을 넘긴 연습은 시작한 날로 센다")
    func dailyPractice() {
        let points = [
            point(date(24, 8), minutes: 5), point(date(24, 20), minutes: 12),
            point(date(25, 23).addingTimeInterval(1800), minutes: 40),  // 25일 23:30 시작 → 26일 0:10 끝
        ]
        #expect(PracticeHistory.dailyPractice(points, calendar: calendar) == [
            DailyPractice(day: date(24, 0), minutes: 17),
            DailyPractice(day: date(25, 0), minutes: 40),
        ])
    }

    @Test("모아 보기: 연습 횟수, 연습한 날 수(연속 여부는 따지지 않음), 모두 합친 시간")
    func totals() {
        let points = [point(date(20, 20), minutes: 10), point(date(20, 21), minutes: 5), point(date(25, 8), minutes: 30)]
        #expect(PracticeHistory.totals(points, calendar: calendar)
                == PracticeHistory.Totals(sessionCount: 3, dayCount: 2, practiceSeconds: 45 * 60))
        #expect(PracticeHistory.totals([], calendar: calendar) == PracticeHistory.Totals(sessionCount: 0, dayCount: 0, practiceSeconds: 0))
    }

    @Test("가로축: 기간 첫날 0시 ~ 내일 0시, 전체는 가장 이른 연습한 날부터")
    func dateDomain() {
        let points = [point(date(3, 20, month: 8)), point(date(25, 8))]
        #expect(PracticeHistory.dateDomain(points, period: .week, now: now, calendar: calendar) == date(19, 0)...date(26, 0))
        #expect(PracticeHistory.dateDomain(points, period: .all, now: now, calendar: calendar) == date(3, 0, month: 8)...date(26, 0))
        #expect(PracticeHistory.dateDomain([], period: .all, now: now, calendar: calendar) == date(19, 0)...date(26, 0))
    }

    /// 두 높이가 반음으로 몇 개 떨어졌는지
    private func semitones(_ a: Double, _ b: Double) -> Double {
        PitchScale.semitones(from: a, to: b)
    }

    @Test("세로축(반음 눈금): 연습 범위·목표 범위·기준이 모두 들어가고, 위아래 반음 1.5개 여유, 70~400 Hz 안, 최소 반음 6개 폭")
    func pitchDomain() {
        let points = [point(.now, low: 140, high: 185), point(.now, low: 150, high: 210)]
        // 가장 낮은 값 140, 가장 높은 값은 목표 상한 230 → 위아래로 반음 1.5개씩 여유
        let domain = PracticeHistory.pitchDomain(points, target: 190...230, baseline: 165)
        #expect(abs(semitones(domain.lowerBound, 140) - 1.5) < 1e-9)
        #expect(abs(semitones(230, domain.upperBound) - 1.5) < 1e-9)

        // 폭이 좁으면 가운데(반음 눈금의 가운데)를 두고 반음 6개로 넓힌다
        let narrow = PracticeHistory.pitchDomain([point(.now, low: 200, high: 210)], target: nil, baseline: nil)
        #expect(abs(semitones(narrow.lowerBound, narrow.upperBound) - 6) < 1e-9)
        #expect(abs(semitones(narrow.lowerBound, 200) - semitones(210, narrow.upperBound)) < 1e-9)

        // 아래 끝을 넘으면 안쪽으로 민다 (반음 폭은 그대로)
        let low = PracticeHistory.pitchDomain([point(.now, low: 75, high: 100)], target: nil, baseline: nil)
        #expect(low.lowerBound == 70)
        #expect(low.contains(100))
        #expect(abs(semitones(70, low.upperBound) - semitones(75, 100) - 3) < 1e-9)

        // 위 끝
        let high = PracticeHistory.pitchDomain([point(.now, low: 360, high: 395)], target: nil, baseline: nil)
        #expect(high.upperBound == 400)
        #expect(abs(semitones(high.lowerBound, 400) - 6) < 1e-9)

        // 아무것도 없으면 분석 범위 전체
        #expect(PracticeHistory.pitchDomain([], target: nil, baseline: nil) == 70...400)
    }

    @Test("세로축 여유는 낮은 목소리와 높은 목소리에 똑같이 (반음으로) 준다")
    func pitchDomainFairForLowAndHigh() {
        let lowVoice = PracticeHistory.pitchDomain([point(.now, low: 100, high: 130)], target: nil, baseline: nil)
        let highVoice = PracticeHistory.pitchDomain([point(.now, low: 220, high: 286)], target: nil, baseline: nil)
        // 두 연습 모두 반음 약 4.5개 폭 → 그래프 높이에서 차지하는 비율이 같다
        let lowShare = semitones(100, 130) / semitones(lowVoice.lowerBound, lowVoice.upperBound)
        let highShare = semitones(220, 286) / semitones(highVoice.lowerBound, highVoice.upperBound)
        #expect(abs(lowShare - highShare) < 1e-3)
    }

    @Test("모두 합친 시간 표시", arguments: [
        (45.0, "45초"), (59.6, "1분"), (1500.0, "25분"), (3600.0, "1시간"), (11_400.0, "3시간 10분"), (11_430.0, "3시간 10분"),
    ])
    func totalLabel(seconds: Double, expected: String) {
        #expect(PracticeHistory.totalLabel(seconds) == expected)
    }
}
