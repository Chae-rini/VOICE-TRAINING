#if DEBUG
import Foundation
import SwiftData

/// 개발용 가짜 연습 기록. 시뮬레이터는 마이크 소리가 들어오지 않아 진짜 연습 기록을 만들 수 없어서, [기록] 탭을 확인할 때만 쓴다.
/// 실행 인자 `-seedSampleHistory YES`를 줄 때, 연습 기록이 하나도 없을 때만 넣는다. 출시용(Release) 빌드에는 들어가지 않는다.
extension PracticeArchive {
    static let seedArgumentKey = "seedSampleHistory"

    func seedSampleHistoryIfRequested(defaults: UserDefaults = .standard, now: Date = .now, calendar: Calendar = .current) {
        guard defaults.bool(forKey: Self.seedArgumentKey),
              (try? context.fetchCount(FetchDescriptor<PracticeSession>())) == 0 else { return }

        let today = calendar.startOfDay(for: now)
        // 40일 전부터 오늘까지, 사흘에 하루는 쉰다. 나흘마다 영어 발표 연습, 닷새마다 아침에도 한 번.
        // 공명 밝기(F2)는 30일 전부터만 남긴다 (그 전 연습은 이 값을 저장하기 전의 기록처럼). 영어는 모음이 달라 F2가 다르게 나온다.
        for daysAgo in stride(from: 40, through: 0, by: -1) where daysAgo % 3 != 1 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let language: PracticeLanguage = daysAgo % 4 == 0 ? .english : .korean
            let median = 150 + Double(40 - daysAgo) * 0.4 + (language == .english ? 12 : 0) + sin(Double(daysAgo)) * 4
            let f2 = daysAgo > 30 ? nil
                : 1450 + Double(30 - daysAgo) * 3 + (language == .english ? -90 : 0) + cos(Double(daysAgo)) * 40
            addSample(at: day.addingTimeInterval(20 * 3600), minutes: 6 + Double(daysAgo % 5) * 3, median: median,
                      takes: 2 + daysAgo % 4, language: language, f2: f2)
            if daysAgo % 5 == 0 {
                addSample(at: day.addingTimeInterval(8 * 3600), minutes: 4, median: median - 6, takes: 1, language: .korean,
                          f2: f2.map { $0 - 30 })
            }
        }
        for daysAgo in [38, 20, 3] {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let median = 148 + Double(40 - daysAgo) * 0.3
            // 개발용 가짜 기록이라 저장 실패는 무시한다.
            try? saveBaseline(VoiceBaseline(median: median, low: median - 18, high: median + 22,
                                            f2: daysAgo > 30 ? nil : 1480 + Double(30 - daysAgo) * 2),
                              measuredAt: day.addingTimeInterval(19 * 3600))
        }
    }

    private func addSample(at start: Date, minutes: Double, median: Double, takes: Int, language: PracticeLanguage,
                           f2: Double?) {
        let target = TargetRangeStore.savedTarget(in: .standard)
        // 중앙값 ±20 Hz에 고르게 퍼진 높이 → 아래 10%·위 10%는 중앙값 ±16 Hz
        let voiced = (0..<100).map { median - 20 + 40 * Double($0) / 99 }
        let duration = minutes * 60
        guard let pitch = PitchSummary(voiced: voiced, voicedSeconds: duration * 0.4, duration: duration,
                                       target: target) else { return }
        // 녹음마다: 1분씩, 녹음할수록 중앙값이 3 Hz씩 오른다
        let takeSummaries: [PracticeSessionLog.Take] = (1...takes).compactMap { round in
            let takeMedian = median - 4 + Double(round - 1) * 3
            let takeVoiced = (0..<50).map { takeMedian - 15 + 30 * Double($0) / 49 }
            guard let takePitch = PitchSummary(voiced: takeVoiced, voicedSeconds: 25, duration: 60, target: target) else {
                return nil
            }
            return PracticeSessionLog.Take(round: round, endedAt: start.addingTimeInterval(Double(round) * 90),
                                           pitch: takePitch)
        }
        try? saveSession(PracticeSessionLog.Summary(startedAt: start, endedAt: start.addingTimeInterval(duration),
                                                    takeCount: takes, language: language, pitch: pitch,
                                                    takes: takeSummaries, f2Median: f2))
    }
}
#endif
