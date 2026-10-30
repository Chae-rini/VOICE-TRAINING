import Foundation

/// [기록] 탭에서 보는 기간.
enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    static let storageKey = "historyPeriod"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "7일"
        case .month: "30일"
        case .all: "전체"
        }
    }

    /// 이 기간의 첫날 0시. 오늘도 하루로 센다 (7일 = 오늘과 그 앞 6일). 전체면 nil.
    func start(now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .all: return nil
        }
    }

    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let start = start(now: now, calendar: calendar) else { return true }
        return date >= start
    }
}

/// 그래프에 찍을 연습 한 번. 저장된 기록(PracticeSession)에서 필요한 값만 꺼낸 것이라 테스트에서 바로 만들 수 있다.
struct SessionPoint: Identifiable, Equatable {
    let startedAt: Date
    /// [s] 시작~정지 시간
    let practiceSeconds: TimeInterval
    /// [Hz] 중앙값, 아래 10%, 위 10%
    let median: Double
    let low: Double
    let high: Double
    let language: PracticeLanguage
    /// [Hz] 연습 전체의 F2 중앙값 (공명 밝기). 2026-10-25 전의 연습과 포먼트를 충분히 못 잡은 연습은 nil
    var f2: Double? = nil

    var id: Date { startedAt }
}

extension SessionPoint {
    init(_ session: PracticeSession) {
        self.init(startedAt: session.startedAt, practiceSeconds: session.practiceSeconds,
                  median: session.medianHz, low: session.lowHz, high: session.highHz, language: session.language,
                  f2: session.f2MedianHz)
    }
}

/// 하루 동안 연습한 시간 (막대그래프용)
struct DailyPractice: Identifiable, Equatable {
    /// 그날 0시
    let day: Date
    let minutes: Double

    var id: Date { day }
}

/// [기록] 탭의 계산 규칙. 점수·향상률·연속 기록(스트릭)은 만들지 않고, 있는 숫자를 모으기만 한다.
enum PracticeHistory {
    struct Totals: Equatable {
        let sessionCount: Int
        /// 연습한 날 수 (연속 여부는 따지지 않음)
        let dayCount: Int
        /// [s]
        let practiceSeconds: TimeInterval
    }

    /// 기간과 언어(nil이면 모두)에 맞는 연습만 남긴다.
    static func filter(_ points: [SessionPoint], period: HistoryPeriod, language: PracticeLanguage?,
                       now: Date, calendar: Calendar) -> [SessionPoint] {
        points.filter { point in
            period.contains(point.startedAt, now: now, calendar: calendar)
                && (language == nil || point.language == language)
        }
    }

    /// 날마다 연습한 시간을 더한다. 연습을 시작한 날로 센다 (자정을 넘긴 연습도 시작한 날).
    static func dailyPractice(_ points: [SessionPoint], calendar: Calendar) -> [DailyPractice] {
        let byDay = Dictionary(grouping: points) { calendar.startOfDay(for: $0.startedAt) }
        return byDay
            .map { day, points in DailyPractice(day: day, minutes: points.map(\.practiceSeconds).reduce(0, +) / 60) }
            .sorted { $0.day < $1.day }
    }

    static func totals(_ points: [SessionPoint], calendar: Calendar) -> Totals {
        Totals(
            sessionCount: points.count,
            dayCount: Set(points.map { calendar.startOfDay(for: $0.startedAt) }).count,
            practiceSeconds: points.map(\.practiceSeconds).reduce(0, +)
        )
    }

    /// 그래프 가로축: 기간 첫날 0시 ~ 내일 0시. 전체면 가장 이른 연습한 날부터 (연습이 없으면 최근 7일).
    static func dateDomain(_ points: [SessionPoint], period: HistoryPeriod, now: Date, calendar: Calendar) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let start = period.start(now: now, calendar: calendar)
            ?? points.map(\.startedAt).min().map { calendar.startOfDay(for: $0) }
            ?? HistoryPeriod.week.start(now: now, calendar: calendar)
            ?? today
        return start...end
    }

    /// [반음] 이보다 좁게는 보여 주지 않는다 (작은 차이가 크게 부풀어 보이지 않게)
    static let minimumPitchSpanSemitones = 6.0
    /// [반음] 위아래 여유
    static let pitchPaddingSemitones = 1.5

    /// 그래프 세로축 [Hz]: 연습의 범위, 목표 범위, 기준이 모두 들어가게 잡고 앱의 분석 범위(70~400 Hz) 안으로 자른다.
    /// 그래프가 반음 눈금이라 여유와 최소 폭도 Hz가 아니라 반음으로 잡는다 (높은 쪽·낮은 쪽이 같은 여유를 갖게).
    static func pitchDomain(_ points: [SessionPoint], target: ClosedRange<Double>?, baseline: Double?) -> ClosedRange<Double> {
        pitchDomain(values: points.flatMap { [$0.low, $0.high] }, target: target, baseline: baseline)
    }

    /// 높이 [Hz]들이 모두 들어가는 축 범위 (두 녹음 비교 그래프도 쓴다). 규칙은 위와 같다.
    static func pitchDomain(values: [Double], target: ClosedRange<Double>?, baseline: Double?) -> ClosedRange<Double> {
        var values = values
        if let target {
            values += [target.lowerBound, target.upperBound]
        }
        if let baseline {
            values.append(baseline)
        }
        return semitoneDomain(values: values, axis: PitchDetector.frequencyRange)
    }

    /// 공명 밝기 그래프의 세로축 [Hz]: 연습마다 F2 중앙값과 기준 F2가 모두 들어가게, 높이 축과 같은 반음 여유·최소 폭으로 잡고
    /// 모음 지도의 F2 범위(600~3000 Hz) 안으로 자른다. F2가 없는 연습은 세지 않는다.
    static func resonanceDomain(_ points: [SessionPoint], baseline: Double?) -> ClosedRange<Double> {
        semitoneDomain(values: points.compactMap(\.f2) + [baseline].compactMap { $0 }, axis: VowelSpace.f2Range)
    }

    /// 값 [Hz]들이 모두 들어가는 반음(로그) 눈금 축. 위아래 반음 `pitchPaddingSemitones`개 여유, 최소 반음 `minimumPitchSpanSemitones`개 폭,
    /// `axis` 밖으로 나가면 안쪽으로 민다. 값이 없으면 `axis` 전체.
    private static func semitoneDomain(values: [Double], axis: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let lowest = values.min(), let highest = values.max() else { return axis }

        var lower = PitchScale.frequency(lowest, offsetBy: -pitchPaddingSemitones)
        var upper = PitchScale.frequency(highest, offsetBy: pitchPaddingSemitones)
        if PitchScale.semitones(from: lower, to: upper) < minimumPitchSpanSemitones {
            // 반음 눈금의 가운데 = 두 끝의 기하평균
            let center = (lower * upper).squareRoot()
            lower = PitchScale.frequency(center, offsetBy: -minimumPitchSpanSemitones / 2)
            upper = PitchScale.frequency(center, offsetBy: minimumPitchSpanSemitones / 2)
        }
        // 범위 밖으로 나가면 안쪽으로 밀어 넣는다 (가능한 한 반음 폭은 유지).
        if lower < axis.lowerBound {
            let shift = PitchScale.semitones(from: lower, to: axis.lowerBound)
            upper = min(PitchScale.frequency(upper, offsetBy: shift), axis.upperBound)
            lower = axis.lowerBound
        }
        if upper > axis.upperBound {
            let shift = PitchScale.semitones(from: upper, to: axis.upperBound)  // 음수
            lower = max(PitchScale.frequency(lower, offsetBy: shift), axis.lowerBound)
            upper = axis.upperBound
        }
        return lower...upper
    }

    /// 예: 45초 → "45초", 1500초 → "25분", 11400초 → "3시간 10분". 1분이 넘으면 초는 버린다.
    static func totalLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 {
            return "\(total)초"
        }
        let hours = total / 3600
        let minutes = total % 3600 / 60
        if hours == 0 {
            return "\(minutes)분"
        }
        return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
    }
}
